import 'sync_record.dart';

/// Why talking to a sync backend failed.
enum SyncFailure {
  /// No answer in time.
  timeout,

  /// The server couldn't be reached (wrong address, offline, not on the
  /// home network).
  network,

  /// The token was missing, wrong or revoked.
  auth,

  /// Something answered, but not a tvplayer sync server.
  notSyncServer,

  /// The server had a problem (HTTP 5xx).
  server,

  /// The server refused records dated too far ahead of its clock.
  clock,

  /// The server answered with something that couldn't be read.
  invalidData,

  /// Anything else, e.g. an unexpected HTTP status.
  other,
}

/// A failed sync request. Its [message] never contains an address, a
/// token or a record.
class SyncException implements Exception {
  const SyncException(this.kind, {this.statusCode});

  final SyncFailure kind;
  final int? statusCode;

  String get message =>
      statusCode == null ? kind.name : '${kind.name} (HTTP $statusCode)';

  @override
  String toString() => 'SyncException: $message';
}

/// What a backend says about itself.
final class SyncInfo {
  const SyncInfo({required this.salt, required this.serverTime});

  /// Random and fixed for the backend's lifetime; makes the account ids
  /// (see `syncAccountId`) unguessable.
  final String salt;

  /// The backend's clock, in milliseconds since the epoch.
  final int serverTime;
}

/// One page of changes since a cursor.
final class SyncPage {
  const SyncPage({
    required this.records,
    required this.cursor,
    required this.more,
    required this.serverTime,
    this.head,
    this.reset = false,
  });

  final List<SyncRecord> records;

  /// Where the next pull continues; opaque to the engine.
  final String? cursor;

  /// Whether more changes follow right away.
  final bool more;
  final int serverTime;

  /// The backend's latest change (opaque), passed back as `head` to
  /// [SyncBackend.pull] so a backend that lost changes can tell.
  final String? head;

  /// The cursor or head is ahead of the backend (e.g. restored from a
  /// backup): it lost changes this device saw, so the space must be
  /// synced from the start. No records come with it.
  final bool reset;
}

/// The answer to a push.
final class PushResult {
  const PushResult({required this.stale, required this.serverTime, this.head});

  /// The backend's copies of pushed records it already had newer: they
  /// replace the local ones. Every other pushed record was taken.
  final List<SyncRecord> stale;
  final int serverTime;

  /// The backend's latest change after the push, as in [SyncPage.head].
  final String? head;
}

/// Where synced records are kept: a sync server today; a sync file on
/// WebDAV or a cloud drive could be another implementation. Records are
/// grouped in spaces (`settings`, one per provider account and kind of
/// data); each space has its own cursor.
abstract interface class SyncBackend {
  /// Checks the connection and login. Throws [SyncException].
  Future<SyncInfo> info();

  /// Changes in [space] after [cursor] (null: from the start), at most
  /// [limit] records. [head] is the latest [SyncPage.head] or
  /// [PushResult.head] seen. Throws [SyncException].
  Future<SyncPage> pull(
    String space,
    String? cursor, {
    int limit,
    String? head,
  });

  /// Stores [records] in [space]; each is kept unless the backend has a
  /// copy that wins ([SyncRecord.compareTo]). Throws [SyncException].
  Future<PushResult> push(String space, List<SyncRecord> records);

  void close();
}
