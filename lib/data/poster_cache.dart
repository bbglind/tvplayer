import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// A poster could not be loaded. [message] never contains the image URL.
class PosterException implements Exception {
  const PosterException(this.message);

  final String message;

  @override
  String toString() => 'PosterException: $message';
}

/// Loads poster and logo images by URL.
abstract interface class PosterLoader {
  /// The image's bytes. Throws [PosterException].
  Future<Uint8List> load(String url);
}

/// [PosterLoader] that keeps downloaded images on disk, up to [maxBytes].
/// When the cache grows past that, the least recently used files are
/// deleted first.
///
/// Files are named by a hash of the URL, so provider addresses never appear
/// on disk, and URLs are never logged.
class PosterCache implements PosterLoader {
  PosterCache({
    required this._client,
    Future<Directory> Function()? directory,
    this.maxBytes = 500 * 1024 * 1024,
    this.maxDownloads = 6,
    this.maxImageBytes = 10 * 1024 * 1024,
    this.timeout = const Duration(seconds: 20),
  }) : _directory = directory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationCacheDirectory()).path}/posters');

  final http.Client _client;
  final Future<Directory> Function() _directory;

  /// Size limit of the whole cache.
  final int maxBytes;

  /// Downloads running at the same time; more wait their turn.
  final int maxDownloads;

  /// Larger responses are rejected.
  final int maxImageBytes;
  final Duration timeout;

  final _inFlight = <String, Future<Uint8List>>{};
  final _waiting = Queue<Completer<void>>();
  var _downloads = 0;

  /// File name → (size, last use), oldest use first after [_scan].
  Map<String, _Entry>? _index;
  Future<void>? _scanning;
  int _total = 0;
  Directory? _dir;

  /// Total size of the cached files, once known.
  @visibleForTesting
  Future<int> get totalBytes async {
    await _ensureIndex();
    return _total;
  }

  @override
  Future<Uint8List> load(String url) {
    final name = _fileName(url);
    // A block body: returning the removed future would make the load wait
    // for itself.
    return _inFlight[name] ??= _load(url, name).whenComplete(() {
      _inFlight.remove(name);
    });
  }

  static String _fileName(String url) =>
      sha256.convert(utf8.encode(url)).toString().substring(0, 40);

  Future<Uint8List> _load(String url, String name) async {
    await _ensureIndex();
    final file = File('${_dir!.path}/$name');
    if (_index!.containsKey(name)) {
      try {
        final bytes = await file.readAsBytes();
        _touch(name, file);
        return bytes;
      } on FileSystemException {
        _forget(name);
      }
    }
    final bytes = await _download(url);
    await _store(name, file, bytes);
    return bytes;
  }

  Future<Uint8List> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      throw const PosterException('Not an http(s) image address');
    }
    await _acquire();
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw PosterException('HTTP ${response.statusCode}');
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) throw const PosterException('Empty image');
      if (bytes.length > maxImageBytes) {
        throw const PosterException('Image too large');
      }
      return bytes;
    } on PosterException {
      rethrow;
    } on TimeoutException {
      throw const PosterException('Timed out');
    } catch (e) {
      // Client exceptions may contain the URL; keep only the type.
      throw PosterException('Download failed (${e.runtimeType})');
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_downloads < maxDownloads) {
      _downloads++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _downloads--;
    }
  }

  Future<void> _store(String name, File file, Uint8List bytes) async {
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: false);
      await tmp.rename(file.path);
    } on FileSystemException catch (e) {
      // Still show the image; it just isn't cached.
      debugPrint('Could not cache a poster (${e.osError?.message})');
      return;
    }
    _forget(name);
    _index![name] = _Entry(bytes.length, DateTime.now());
    _total += bytes.length;
    if (_total > maxBytes) await _evict(keep: name);
  }

  /// Deletes least recently used files until the cache is at 90 % of
  /// [maxBytes], keeping [keep].
  Future<void> _evict({required String keep}) async {
    final index = _index!;
    final byAge = index.entries.toList()
      ..sort((a, b) => a.value.used.compareTo(b.value.used));
    final target = maxBytes * 9 ~/ 10;
    for (final MapEntry(key: name, value: entry) in byAge) {
      if (_total <= target) break;
      if (name == keep) continue;
      try {
        await File('${_dir!.path}/$name').delete();
      } on FileSystemException {
        // Already gone.
      }
      if (identical(index[name], entry)) _forget(name);
    }
  }

  void _touch(String name, File file) {
    final entry = _index![name];
    if (entry == null) return;
    final now = DateTime.now();
    entry.used = now;
    // The file time keeps the order across restarts.
    file.setLastModified(now).catchError((_) {});
  }

  void _forget(String name) {
    final entry = _index!.remove(name);
    if (entry != null) _total -= entry.size;
  }

  Future<void> _ensureIndex() =>
      _index != null ? Future.value() : _scanning ??= _scan();

  Future<void> _scan() async {
    final dir = _dir = await _directory();
    await dir.create(recursive: true);
    final index = <String, _Entry>{};
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.endsWith('.tmp')) {
        await entity.delete().catchError((_) => entity);
        continue;
      }
      try {
        final stat = await entity.stat();
        index[name] = _Entry(stat.size, stat.modified);
        total += stat.size;
      } on FileSystemException {
        // Vanished meanwhile.
      }
    }
    _index = index;
    _total = total;
    if (_total > maxBytes) await _evict(keep: '');
  }
}

class _Entry {
  _Entry(this.size, this.used);

  final int size;
  DateTime used;
}
