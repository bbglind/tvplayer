import '../favourites/favourites_data.dart';
import '../favourites/favourites_logic.dart';
import '../watch/watch_data.dart';
import 'sync_clock.dart';
import 'sync_engine.dart';
import 'sync_record.dart';

/// The records of [records] to take over [current]: the ones that win
/// over the local copy, or all with [force].
List<SyncRecord> _winners(
  List<SyncRecord> records,
  Map<String, SyncRecord> current, {
  required bool force,
}) => [
  for (final r in records)
    if (force || r.beats(current[r.key]?.version)) r,
];

/// The watch history of one account as a [SyncSpace]. [read] gives the
/// current data and [write] takes changed data (which the app saves).
class WatchSyncSpace extends SyncSpace {
  WatchSyncSpace({
    required this.id,
    required this.read,
    required this.write,
    required this.clock,
    this.backup,
  });

  @override
  final String id;
  final WatchData Function() read;
  final void Function(WatchData data) write;
  final SyncClock clock;

  /// Saves a copy of the local data before the first sync.
  final Future<void> Function()? backup;

  @override
  Future<Map<String, SyncRecord>> localRecords() async => read().syncRecords;

  @override
  Future<void> apply(List<SyncRecord> records, {bool force = false}) async {
    final data = read();
    final take = _winners(records, data.syncRecords, force: force);
    if (take.isNotEmpty) write(data.withSyncRecords(take));
  }

  @override
  Future<void> beforeFirstSync() async => backup?.call();

  /// A movie or episode watched on one device stays watched, whichever
  /// copy is newer.
  @override
  Future<void> mergeFirst(List<SyncRecord> pulled) async {
    final data = read();
    final remote = WatchData.fromJson({
      'records': [for (final r in pulled) r.toJson()],
    });
    final changed = <String, WatchProgress>{};
    for (final MapEntry(:key, value: theirs) in remote.items.entries) {
      final ours = data.items[key];
      if (ours == null || ours.watched == theirs.watched) continue;
      final newer = theirs.updatedAt.isAfter(ours.updatedAt) ? theirs : ours;
      changed[key] = newer.copyWith(watched: true, updatedAt: clock.now());
    }
    if (changed.isNotEmpty) write(data.withItems(changed));
  }
}

/// The favourites and category settings of one account as a [SyncSpace].
class FavouritesSyncSpace extends SyncSpace {
  FavouritesSyncSpace({
    required this.id,
    required this.read,
    required this.write,
    required this.clock,
    this.backup,
  });

  @override
  final String id;
  final FavouritesData Function() read;
  final void Function(FavouritesData data) write;
  final SyncClock clock;
  final Future<void> Function()? backup;

  @override
  Future<Map<String, SyncRecord>> localRecords() async => read().syncRecords;

  @override
  Future<void> apply(List<SyncRecord> records, {bool force = false}) async {
    final data = read();
    final take = _winners(records, data.syncRecords, force: force);
    if (take.isNotEmpty) write(data.withSyncRecords(take));
  }

  @override
  Future<void> beforeFirstSync() async => backup?.call();

  /// Categories made on this device with the name of a synced one are
  /// combined into it ([combineCategoriesByName]).
  @override
  Future<void> afterFirstPull(Set<String> serverKeys) async {
    const prefix = 'category:';
    final synced = {
      for (final k in serverKeys)
        if (k.startsWith(prefix)) k.substring(prefix.length),
    };
    final data = read();
    final combined = combineCategoriesByName(data, synced, now: clock.now());
    if (!identical(combined, data)) write(combined);
  }
}

/// Settings as a [SyncSpace]: one record `setting:<name>` per setting,
/// with its JSON value and the time it was last changed ([stamps]; 0 for
/// never). On the first sync the backend's settings win, and the ones it
/// lacks are sent with the current time, so the first device to sync sets
/// them all.
class SettingsSyncSpace extends SyncSpace {
  SettingsSyncSpace({
    required this.id,
    required this.values,
    required this.stamps,
    required this.write,
    required this.clock,
    this.backup,
  });

  @override
  final String id;

  /// The current value of each synced setting by name (null for unset).
  final Map<String, Object?> Function() values;

  /// When each setting was last changed, in milliseconds since the epoch.
  final Map<String, int> Function() stamps;

  /// Takes changed [values] with their new [stamps].
  final void Function(Map<String, Object?> values, Map<String, int> stamps)
  write;
  final SyncClock clock;
  final Future<void> Function()? backup;

  static const _prefix = 'setting:';

  @override
  bool get remoteWinsOnFirstSync => true;

  @override
  Future<Map<String, SyncRecord>> localRecords() async {
    final times = stamps();
    return {
      for (final MapEntry(:key, :value) in values().entries)
        '$_prefix$key': SyncRecord(
          key: '$_prefix$key',
          t: times[key] ?? 0,
          value: value,
        ),
    };
  }

  @override
  Future<void> apply(List<SyncRecord> records, {bool force = false}) async {
    final known = values();
    final take = _winners(records, await localRecords(), force: force);
    final changed = <String, Object?>{};
    final times = <String, int>{};
    for (final r in take) {
      final name = r.key.startsWith(_prefix)
          ? r.key.substring(_prefix.length)
          : null;
      // Settings this version doesn't sync (or know) are ignored.
      if (name == null || !known.containsKey(name) || r.deleted) continue;
      changed[name] = r.value;
      times[name] = r.t;
    }
    if (times.isNotEmpty) write(changed, times);
  }

  @override
  Future<void> beforeFirstSync() async => backup?.call();

  @override
  Future<void> afterFirstPull(Set<String> serverKeys) async {
    final current = values();
    final missing = [
      for (final name in current.keys)
        if (!serverKeys.contains('$_prefix$name')) name,
    ];
    if (missing.isEmpty) return;
    final t = clock.now().millisecondsSinceEpoch;
    write(
      {for (final n in missing) n: current[n]},
      {for (final n in missing) n: t},
    );
  }
}
