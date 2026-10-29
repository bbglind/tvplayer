import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// What sync keeps between runs besides the per-space states: the clock,
/// when the last sync went through, the change times of the synced
/// settings, and the salt of the server they belong to.
final class SyncMeta {
  const SyncMeta({
    this.clock,
    this.lastSync,
    this.stamps = const {},
    this.salt,
  });

  /// [SyncClock.toJson].
  final Object? clock;
  final DateTime? lastSync;

  /// When each synced setting was last changed, in milliseconds.
  final Map<String, int> stamps;

  /// [SyncInfo.salt] of the server last synced with; another one means
  /// another server, which starts over with a first sync.
  final String? salt;

  SyncMeta copyWith({
    Object? clock,
    DateTime? lastSync,
    Map<String, int>? stamps,
    String? Function()? salt,
  }) => SyncMeta(
    clock: clock ?? this.clock,
    lastSync: lastSync ?? this.lastSync,
    stamps: stamps ?? this.stamps,
    salt: salt == null ? this.salt : salt(),
  );

  Map<String, Object?> toJson() => {
    'clock': ?clock,
    'lastSync': ?lastSync?.millisecondsSinceEpoch,
    'stamps': stamps,
    'salt': ?salt,
  };

  factory SyncMeta.fromJson(Object? json) {
    if (json is! Map) return const SyncMeta();
    final last = json['lastSync'];
    final stamps = json['stamps'];
    final salt = json['salt'];
    return SyncMeta(
      clock: json['clock'],
      lastSync: last is int
          ? DateTime.fromMillisecondsSinceEpoch(last, isUtc: true)
          : null,
      stamps: {
        if (stamps is Map)
          for (final MapEntry(:key, :value) in stamps.entries)
            if (key is String && value is int) key: value,
      },
      salt: salt is String ? salt : null,
    );
  }
}

/// Where sync keeps its files. Overridden in tests.
abstract interface class SyncStorage {
  Future<SyncStateStore> states();

  Future<SyncMeta> loadMeta();

  Future<void> saveMeta(SyncMeta meta);

  /// Writes [files] (name → JSON) to a new backup folder; returns the
  /// folder's name.
  Future<String> backup(Map<String, Object?> files);
}

/// [SyncStorage] in the app support directory: `sync/` for the states
/// and `sync/meta.json`, `sync_backup/<date-time>/` for the backups made
/// before a first sync.
class FileSyncStorage implements SyncStorage {
  FileSyncStorage([Future<Directory> Function()? root])
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  Future<String> get _path async => (await _root()).path;

  @override
  Future<SyncStateStore> states() async =>
      JsonFileSyncStateStore(Directory('${await _path}/sync/spaces'));

  Future<File> get _meta async => File('${await _path}/sync/meta.json');

  @override
  Future<SyncMeta> loadMeta() async {
    try {
      final file = await _meta;
      if (!await file.exists()) return const SyncMeta();
      return SyncMeta.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      return const SyncMeta();
    }
  }

  @override
  Future<void> saveMeta(SyncMeta meta) async =>
      _write(await _meta, meta.toJson());

  @override
  Future<String> backup(Map<String, Object?> files) async {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = DateTime.now();
    final root = await _path;
    var name =
        '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    var dir = Directory('$root/sync_backup/$name');
    for (var i = 2; await dir.exists(); i++) {
      dir = Directory('$root/sync_backup/$name-$i');
    }
    name = dir.path.substring(dir.parent.path.length + 1);
    for (final MapEntry(:key, :value) in files.entries) {
      await _write(File('${dir.path}/$key'), value);
    }
    return name;
  }

  static Future<void> _write(File file, Object? json) async {
    await file.parent.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(file.path);
  }
}
