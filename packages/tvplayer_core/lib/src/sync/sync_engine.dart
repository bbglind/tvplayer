import 'dart:convert';

import 'sync_backend.dart';
import 'sync_clock.dart';
import 'sync_protocol.dart';
import 'sync_record.dart';
import 'sync_state.dart';

/// The local side of one synced space: turns the app's data into
/// [SyncRecord]s and takes changes back.
abstract class SyncSpace {
  /// The space name ([isSyncSpace]).
  String get id;

  /// Whether, on the first sync, every record the backend has replaces
  /// the local one, however recent (settings: the first device to sync
  /// sets them).
  bool get remoteWinsOnFirstSync => false;

  /// The local records by key.
  Future<Map<String, SyncRecord>> localRecords();

  /// Takes [records] from the backend. Each replaces the local record
  /// with its key if it [SyncRecord.beats] it, checked again against the
  /// current data (it may have changed meanwhile); with [force], always.
  Future<void> apply(List<SyncRecord> records, {bool force = false});

  /// Before the first sync: e.g. a backup of the local data.
  Future<void> beforeFirstSync() async {}

  /// First sync only, before [pulled] (a page of the backend's records) is
  /// applied: combines both copies where newest-wins would lose something.
  /// What it changes gets a new time and is sent like any change.
  Future<void> mergeFirst(List<SyncRecord> pulled) async {}

  /// First sync only, after everything was pulled; [serverKeys] are the
  /// keys the backend holds.
  Future<void> afterFirstPull(Set<String> serverKeys) async {}
}

/// What one sync of one space did.
final class SpaceReport {
  const SpaceReport({
    this.pulled = 0,
    this.applied = 0,
    this.pushed = 0,
    this.skipped = 0,
    this.first = false,
  });

  /// Records received, and how many of them changed local data.
  final int pulled;
  final int applied;

  /// Records the backend took.
  final int pushed;

  /// Records too large to send (none in practice).
  final int skipped;
  final bool first;
}

/// What a whole sync did.
final class SyncReport {
  const SyncReport(this.spaces);

  final Map<String, SpaceReport> spaces;

  int get pulled => spaces.values.fold(0, (n, r) => n + r.applied);
  int get pushed => spaces.values.fold(0, (n, r) => n + r.pushed);
  int get skipped => spaces.values.fold(0, (n, r) => n + r.skipped);
}

/// Syncs spaces with a [SyncBackend], record by record, the newest copy
/// winning ([SyncRecord.compareTo]; deletions are tombstone records).
///
/// Each space: pull the changes since the last cursor and apply the ones
/// that win; then push the local records that win over what the backend
/// is known to hold, in requests of at most [maxPushBytes]. The state is
/// saved after every step and every step can be repeated, so an
/// interrupted sync just continues next time.
class SyncEngine {
  SyncEngine({
    required this.backend,
    required this.states,
    required this.clock,
    this.pageLimit = syncMaxRecords,
    this.maxPushBytes = syncMaxPushBytes,
    this.maxPushRecords = syncMaxRecords,
  });

  final SyncBackend backend;
  final SyncStateStore states;
  final SyncClock clock;
  final int pageLimit;
  final int maxPushBytes;
  final int maxPushRecords;

  /// Checks the backend and sets [clock]'s offset to its time.
  Future<SyncInfo> connect() async {
    final sent = clock.deviceTime;
    final info = await backend.info();
    clock.calibrate(
      sent: sent,
      received: clock.deviceTime,
      serverTime: info.serverTime,
    );
    return info;
  }

  /// [connect]s, then syncs the [spaces] made for the backend, in order.
  /// Throws [SyncException]; spaces synced before a failure stay synced.
  Future<SyncReport> run(List<SyncSpace> Function(SyncInfo info) spaces) async {
    final info = await connect();
    final reports = <String, SpaceReport>{};
    for (final space in spaces(info)) {
      reports[space.id] = await sync(space);
    }
    return SyncReport(reports);
  }

  /// Syncs one [space]. Throws [SyncException].
  Future<SpaceReport> sync(SyncSpace space) async {
    var state = await states.load(space.id);
    if (state == null) {
      await space.beforeFirstSync();
      state = SyncState.initial;
      await states.save(space.id, state);
    }
    final first = !state.complete;
    final force = first && space.remoteWinsOnFirstSync;
    final shadow = {...state.shadow};
    var cursor = state.cursor;
    var pulled = 0, applied = 0;

    Future<void> save({bool complete = false}) => states.save(
      space.id,
      SyncState(cursor: cursor, shadow: shadow, complete: complete),
    );

    while (true) {
      final page = await backend.pull(space.id, cursor, limit: pageLimit);
      for (final r in page.records) {
        clock.observe(r.t);
      }
      if (first) await space.mergeFirst(page.records);
      final local = await space.localRecords();
      final winners = [
        for (final r in page.records)
          if (force || r.beats(local[r.key]?.version)) r,
      ];
      if (winners.isNotEmpty) await space.apply(winners, force: force);
      for (final r in page.records) {
        shadow[r.key] = r.version;
      }
      pulled += page.records.length;
      applied += winners.length;
      cursor = page.cursor ?? cursor;
      await save();
      if (!page.more || page.records.isEmpty) break;
    }
    if (first) await space.afterFirstPull(shadow.keys.toSet());

    var local = await space.localRecords();
    // Dated by a clock that was far ahead before sync was set up: such a
    // record would win every later change. Redated to now.
    final ahead = [
      for (final r in local.values)
        if (clock.isFarAhead(r.t)) r.at(clock.now().millisecondsSinceEpoch),
    ];
    if (ahead.isNotEmpty) {
      await space.apply(ahead, force: true);
      local = await space.localRecords();
    }

    final outgoing = [
      for (final r in local.values)
        if (r.beats(shadow[r.key])) r,
    ];
    final (batches, skipped) = _batches(outgoing);
    var pushed = 0;
    for (final batch in batches) {
      final result = await backend.push(space.id, batch);
      final stale = {for (final s in result.stale) s.key: s};
      for (final r in batch) {
        if (!stale.containsKey(r.key)) {
          shadow[r.key] = r.version;
          pushed++;
        }
      }
      for (final s in stale.values) {
        clock.observe(s.t);
        shadow[s.key] = s.version;
      }
      if (stale.isNotEmpty) {
        await space.apply(stale.values.toList());
        applied += stale.length;
      }
      await save();
    }
    await save(complete: true);
    return SpaceReport(
      pulled: pulled,
      applied: applied,
      pushed: pushed,
      skipped: skipped,
      first: first,
    );
  }

  /// [records] in push requests of at most [maxPushBytes] (the whole body)
  /// and [maxPushRecords]; and how many didn't fit in any.
  (List<List<SyncRecord>>, int) _batches(List<SyncRecord> records) {
    // `{"records":[...]}` around the records, a comma between them.
    const envelope = 14;
    final batches = <List<SyncRecord>>[];
    var batch = <SyncRecord>[];
    var size = envelope;
    var skipped = 0;
    for (final r in records) {
      final bytes = utf8.encode(jsonEncode(r.toJson())).length + 1;
      if (envelope + bytes > maxPushBytes) {
        skipped++;
        continue;
      }
      if (size + bytes > maxPushBytes || batch.length >= maxPushRecords) {
        batches.add(batch);
        batch = [];
        size = envelope;
      }
      batch.add(r);
      size += bytes;
    }
    if (batch.isNotEmpty) batches.add(batch);
    return (batches, skipped);
  }
}
