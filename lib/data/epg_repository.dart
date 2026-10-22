import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// Downloads, parses and caches the TV guide.
abstract interface class EpgRepository {
  /// The cached guide, or null when there is none or it can't be read.
  Future<EpgGuide?> loadCache();

  /// Downloads the guide from [source], keeps the programmes the
  /// [channels] can use and from [keepFrom] on, and caches the result.
  /// Throws [XtreamException] on download errors.
  Future<EpgGuide> refresh(
    LiveSource source,
    List<LiveStream> channels, {
    required DateTime now,
    required DateTime keepFrom,
  });

  /// Deletes the cache, e.g. when the provider changes.
  Future<void> clear();
}

/// [EpgRepository] with the cache as a JSON file in the app cache
/// directory. Parsing and (de)serialising run in background isolates, so
/// large guides don't freeze the UI.
class FileEpgRepository implements EpgRepository {
  FileEpgRepository([Future<Directory> Function()? directory])
    : _directory = directory ?? getApplicationCacheDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file(String name) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}/$name');
  }

  static const _cacheName = 'epg_cache.json';

  @override
  Future<EpgGuide?> loadCache() async {
    final path = (await _file(_cacheName)).path;
    return Isolate.run(() async {
      try {
        final file = File(path);
        if (!await file.exists()) return null;
        return EpgGuide.fromJson(jsonDecode(await file.readAsString()));
      } on Exception {
        return null;
      }
    });
  }

  @override
  Future<EpgGuide> refresh(
    LiveSource source,
    List<LiveStream> channels, {
    required DateTime now,
    required DateTime keepFrom,
  }) async {
    final download = await _file('epg_download.xml');
    final cachePath = (await _file(_cacheName)).path;
    final epgIds = [
      for (final c in channels)
        if (c.epgChannelId case final id? when id.isNotEmpty) id,
    ];
    final names = [for (final c in channels) c.name];
    try {
      await source.downloadGuide(download);
      final downloadPath = download.path;
      return await Isolate.run(() async {
        final guide = await buildGuideFromXmltvFile(
          downloadPath,
          fetchedAt: now,
          epgIds: epgIds,
          names: names,
          keepFrom: keepFrom,
        );
        final tmp = File('$cachePath.tmp');
        await tmp.writeAsString(jsonEncode(guide.toJson()));
        await tmp.rename(cachePath);
        return guide;
      });
    } finally {
      if (await download.exists()) await download.delete();
    }
  }

  @override
  Future<void> clear() async {
    final file = await _file(_cacheName);
    if (await file.exists()) await file.delete();
  }
}
