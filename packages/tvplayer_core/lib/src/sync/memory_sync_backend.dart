import 'sync_backend.dart';
import 'sync_protocol.dart';
import 'sync_record.dart';

/// [SyncBackend] in memory, with the server's rules: the newest copy of
/// each record is kept, each change gets the next sequence number, and a
/// pull returns the changes after a sequence number. For tests.
class MemorySyncBackend implements SyncBackend {
  MemorySyncBackend({this.salt = 'test-salt', DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String salt;
  final DateTime Function() _clock;

  /// Records by space and key, each with its sequence number.
  final _spaces = <String, Map<String, (int, SyncRecord)>>{};
  var _seq = 0;

  /// When set, every request throws it (e.g. to simulate being offline).
  SyncException? failure;

  /// The pushes received, for checking batch sizes.
  final pushes = <(String, List<SyncRecord>)>[];

  int get _now => _clock().millisecondsSinceEpoch;

  /// The records of [space] by key.
  Map<String, SyncRecord> records(String space) => {
    for (final MapEntry(:key, :value) in (_spaces[space] ?? const {}).entries)
      key: value.$2,
  };

  void _check() {
    if (failure case final f?) throw f;
  }

  @override
  Future<SyncInfo> info() async {
    _check();
    return SyncInfo(salt: salt, serverTime: _now);
  }

  @override
  Future<SyncPage> pull(
    String space,
    String? cursor, {
    int limit = syncMaxRecords,
  }) async {
    _check();
    final since = int.tryParse(cursor ?? '') ?? 0;
    final changes = [
      for (final (seq, r) in (_spaces[space] ?? const {}).values)
        if (seq > since) (seq, r),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final page = changes.take(limit).toList();
    return SyncPage(
      records: [for (final (_, r) in page) r],
      cursor: page.isEmpty ? cursor : '${page.last.$1}',
      more: changes.length > page.length,
      serverTime: _now,
    );
  }

  @override
  Future<PushResult> push(String space, List<SyncRecord> records) async {
    _check();
    pushes.add((space, records));
    final limit = _now + syncMaxAhead.inMilliseconds;
    if (records.any((r) => r.t > limit)) {
      throw const SyncException(SyncFailure.clock, statusCode: 422);
    }
    final stored = _spaces.putIfAbsent(space, () => {});
    final stale = <SyncRecord>[];
    for (final r in records) {
      final current = stored[r.key]?.$2;
      if (current != null && !r.beats(current.version)) {
        if (current.version != r.version) stale.add(current);
        continue;
      }
      stored[r.key] = (++_seq, r);
    }
    return PushResult(stale: stale, serverTime: _now);
  }

  @override
  void close() {}
}
