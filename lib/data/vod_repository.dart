import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// Caches movie and series catalogues on disk, per provider (by
/// [providerKey]), so the tabs open instantly.
abstract interface class VodRepository {
  /// The cached catalogue, or null when there is none or it can't be read.
  Future<VodCatalog<Movie>?> loadMovies(String providerKey);

  Future<VodCatalog<Series>?> loadSeries(String providerKey);

  Future<void> saveMovies(String providerKey, VodCatalog<Movie> catalog);

  Future<void> saveSeries(String providerKey, VodCatalog<Series> catalog);

  /// Deletes both caches of a provider, e.g. when it is removed.
  Future<void> clear(String providerKey);
}

/// [VodRepository] with JSON files in the app cache directory. Reading,
/// parsing and writing run in background isolates, so catalogues with tens
/// of thousands of items don't freeze the UI.
class FileVodRepository implements VodRepository {
  FileVodRepository([Future<Directory> Function()? directory])
    : _directory = directory ?? getApplicationCacheDirectory;

  final Future<Directory> Function() _directory;

  Future<String> _path(String providerKey, String kind) async {
    final dir = Directory('${(await _directory()).path}/catalog');
    await dir.create(recursive: true);
    return '${dir.path}/${providerKey}_$kind.json';
  }

  @override
  Future<VodCatalog<Movie>?> loadMovies(String providerKey) async {
    final path = await _path(providerKey, 'movies');
    return Isolate.run(
      // The search index is built here too, off the UI thread.
      () async =>
          VodCatalog.moviesFromJson(await _readJson(path))?..searchIndex,
    );
  }

  @override
  Future<VodCatalog<Series>?> loadSeries(String providerKey) async {
    final path = await _path(providerKey, 'series');
    return Isolate.run(
      () async =>
          VodCatalog.seriesFromJson(await _readJson(path))?..searchIndex,
    );
  }

  @override
  Future<void> saveMovies(String providerKey, VodCatalog<Movie> catalog) async {
    final path = await _path(providerKey, 'movies');
    await Isolate.run(
      () => _writeJson(path, catalog.toJson((m) => m.toJson())),
    );
  }

  @override
  Future<void> saveSeries(
    String providerKey,
    VodCatalog<Series> catalog,
  ) async {
    final path = await _path(providerKey, 'series');
    await Isolate.run(
      () => _writeJson(path, catalog.toJson((s) => s.toJson())),
    );
  }

  @override
  Future<void> clear(String providerKey) async {
    for (final kind in ['movies', 'series']) {
      final file = File(await _path(providerKey, kind));
      if (await file.exists()) await file.delete();
    }
  }

  static Future<Object?> _readJson(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on Exception {
      return null;
    }
  }

  static Future<void> _writeJson(String path, Object? json) async {
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('$path.tmp');
    await tmp.writeAsString(jsonEncode(json));
    await tmp.rename(path);
  }
}
