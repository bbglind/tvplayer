import 'dart:convert';
import 'dart:io';

import '../util/json.dart';
import 'sync_record.dart';

/// How far one space is synced: where the next pull continues, and the
/// version of every record the backend is known to hold (the shadow).
///
/// Local records that win over their shadow are the ones still to be
/// sent, so changes made offline wait in the data itself, with no queue
/// that could get lost.
final class SyncState {
  const SyncState({
    this.cursor,
    this.head,
    this.shadow = const {},
    this.complete = false,
  });

  final String? cursor;

  /// The backend's latest change seen ([SyncPage.head]).
  final String? head;
  final Map<String, SyncVersion> shadow;

  /// Whether the first sync of the space went through to the end. Until
  /// then each run merges like a first sync.
  final bool complete;

  static const initial = SyncState();

  Map<String, Object?> toJson() => {
    'version': 1,
    'cursor': ?cursor,
    'head': ?head,
    'complete': complete,
    'shadow': {
      for (final MapEntry(:key, :value) in shadow.entries) key: value.toJson(),
    },
  };

  /// Inverse of [toJson]; null when [json] isn't a sync state.
  static SyncState? fromJson(Object? json) {
    final map = readMap(json);
    final shadow = readMap(map?['shadow']);
    if (map == null || shadow == null) return null;
    final cursor = map['cursor'];
    final head = map['head'];
    return SyncState(
      cursor: cursor is String ? cursor : null,
      head: head is String ? head : null,
      complete: map['complete'] == true,
      shadow: {
        for (final MapEntry(:key, :value) in shadow.entries)
          key: ?SyncVersion.fromJson(value),
      },
    );
  }
}

/// Persists the [SyncState] of each space.
abstract interface class SyncStateStore {
  /// The saved state of [space]; null when it never synced (or the state
  /// can't be read, which makes the next sync a first one again: safe,
  /// as a first sync only merges).
  Future<SyncState?> load(String space);

  Future<void> save(String space, SyncState state);

  /// Forgets every space, e.g. after switching to another server.
  Future<void> clear();
}

/// [SyncStateStore] with one JSON file per space in [directory].
class JsonFileSyncStateStore implements SyncStateStore {
  JsonFileSyncStateStore(this.directory);

  final Directory directory;

  File _file(String space) => File('${directory.path}/$space.json');

  @override
  Future<SyncState?> load(String space) async {
    try {
      final file = _file(space);
      if (!await file.exists()) return null;
      return SyncState.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> save(String space, SyncState state) async {
    await directory.create(recursive: true);
    final file = _file(space);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

/// [SyncStateStore] in memory, for tests.
class MemorySyncStateStore implements SyncStateStore {
  final states = <String, SyncState>{};

  @override
  Future<SyncState?> load(String space) async => states[space];

  @override
  Future<void> save(String space, SyncState state) async =>
      states[space] = state;

  @override
  Future<void> clear() async => states.clear();
}
