import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// The provider's past listing of one channel, as fetched at [fetchedAt].
final class ArchiveEntry {
  const ArchiveEntry({required this.fetchedAt, required this.programs});

  final DateTime fetchedAt;

  /// Sorted by start.
  final List<EpgProgram> programs;
}

/// Caches the providers' past listings (see [LiveSource.archiveListings])
/// per channel, so replay can reach back over the whole archive without
/// asking again.
abstract interface class ArchiveEpgRepository {
  /// The cached listings of [providerKey] by [LiveStream.id]; empty when
  /// there are none or they can't be read.
  Future<Map<String, ArchiveEntry>> load(String providerKey);

  Future<void> save(String providerKey, Map<String, ArchiveEntry> entries);

  Future<void> clear(String providerKey);
}

/// [ArchiveEpgRepository] in `<cache>/archive_epg/<providerKey>.json`.
class FileArchiveEpgRepository implements ArchiveEpgRepository {
  FileArchiveEpgRepository([Future<Directory> Function()? directory])
    : _directory = directory ?? getApplicationCacheDirectory;

  final Future<Directory> Function() _directory;

  /// Cache format version.
  static const version = 1;

  Future<File> _file(String providerKey) async {
    final dir = Directory('${(await _directory()).path}/archive_epg');
    await dir.create(recursive: true);
    return File('${dir.path}/$providerKey.json');
  }

  @override
  Future<Map<String, ArchiveEntry>> load(String providerKey) async {
    try {
      final file = await _file(providerKey);
      if (!await file.exists()) return {};
      return decodeArchive(jsonDecode(await file.readAsString()));
    } on Exception {
      return {};
    }
  }

  @override
  Future<void> save(
    String providerKey,
    Map<String, ArchiveEntry> entries,
  ) async {
    final file = await _file(providerKey);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(encodeArchive(entries)));
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear(String providerKey) async {
    final file = await _file(providerKey);
    if (await file.exists()) await file.delete();
  }
}

/// Compact JSON of [entries]; times are UTC epoch seconds.
Map<String, Object?> encodeArchive(Map<String, ArchiveEntry> entries) => {
  'v': FileArchiveEpgRepository.version,
  'streams': {
    for (final MapEntry(:key, :value) in entries.entries)
      key: {
        'fetchedAt': _seconds(value.fetchedAt),
        'programs': [
          for (final p in value.programs)
            [
              _seconds(p.start),
              _seconds(p.stop),
              p.title,
              p.description,
              p.archived,
            ],
        ],
      },
  },
};

/// Inverse of [encodeArchive]; empty for another version or unreadable
/// data. Unreadable streams are left out.
Map<String, ArchiveEntry> decodeArchive(Object? json) {
  if (json is! Map || json['v'] != FileArchiveEpgRepository.version) {
    return {};
  }
  final streams = json['streams'];
  if (streams is! Map) return {};
  final result = <String, ArchiveEntry>{};
  for (final MapEntry(:key, :value) in streams.entries) {
    if (key is! String || value is! Map) continue;
    final fetchedAt = value['fetchedAt'];
    final programs = value['programs'];
    if (fetchedAt is! int || programs is! List) continue;
    final list = <EpgProgram>[];
    for (final p in programs) {
      if (p is! List || p.length != 5) continue;
      final [start, stop, title, description, archived] = p;
      if (start is! int || stop is! int || title is! String) continue;
      list.add(
        EpgProgram(
          channelId: '',
          title: title,
          description: description is String ? description : null,
          archived: archived is bool ? archived : null,
          start: _fromSeconds(start),
          stop: _fromSeconds(stop),
        ),
      );
    }
    result[key] = ArchiveEntry(
      fetchedAt: _fromSeconds(fetchedAt),
      programs: list,
    );
  }
  return result;
}

int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

DateTime _fromSeconds(int s) =>
    DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
