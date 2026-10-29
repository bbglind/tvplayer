import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../util/json.dart';

/// One synced record: a key, its change time [t] and its value, or a
/// tombstone ([deleted]).
///
/// Which of two copies of a key wins is decided by [compareTo] alone, the
/// same on every device and on the server: the later [t], and on equal
/// times the higher [hash] of the content, so every copy ends up the same.
final class SyncRecord implements Comparable<SyncRecord> {
  SyncRecord({
    required this.key,
    required this.t,
    this.value,
    this.deleted = false,
  });

  final String key;

  /// Change time in milliseconds since the epoch, from a `SyncClock`.
  final int t;

  /// A JSON value (map, list, string, number, bool or null).
  final Object? value;
  final bool deleted;

  /// Short hash of [deleted] and [value] in canonical JSON: equal content
  /// gives an equal hash on every device.
  late final String hash = contentHash(value, deleted: deleted);

  SyncVersion get version => SyncVersion(t, hash);

  /// Positive when this copy wins over [other].
  @override
  int compareTo(SyncRecord other) => version.compareTo(other.version);

  /// Whether this copy wins over [other] (always over none).
  bool beats(SyncVersion? other) =>
      other == null || version.compareTo(other) > 0;

  /// This record with change time [t].
  SyncRecord at(int t) =>
      SyncRecord(key: key, t: t, value: value, deleted: deleted);

  Map<String, Object?> toJson() => {
    'k': key,
    't': t,
    'v': value,
    if (deleted) 'd': true,
  };

  /// Inverse of [toJson]; null for anything unreadable.
  static SyncRecord? fromJson(Object? json) {
    final map = readMap(json);
    final key = map?['k'];
    final t = map?['t'];
    if (map == null || key is! String || key.isEmpty || t is! int) {
      return null;
    }
    return SyncRecord(
      key: key,
      t: t,
      value: map['v'],
      deleted: map['d'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncRecord && other.key == key && other.version == version;

  @override
  int get hashCode => Object.hash(key, t, hash);

  /// Never the value: records hold names.
  @override
  String toString() => 'SyncRecord($key @$t)';
}

/// What decides a record's place: its change time and content hash.
final class SyncVersion implements Comparable<SyncVersion> {
  const SyncVersion(this.t, this.hash);

  final int t;
  final String hash;

  @override
  int compareTo(SyncVersion other) =>
      t != other.t ? t.compareTo(other.t) : hash.compareTo(other.hash);

  List<Object> toJson() => [t, hash];

  static SyncVersion? fromJson(Object? json) {
    if (json is! List || json.length != 2) return null;
    final [t, hash] = json;
    return t is int && hash is String ? SyncVersion(t, hash) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is SyncVersion && other.t == t && other.hash == hash;

  @override
  int get hashCode => Object.hash(t, hash);

  @override
  String toString() => 'SyncVersion($t, $hash)';
}

/// The first 16 hex digits of the SHA-256 of [value] (with [deleted]) in
/// canonical JSON (see [canonicalJson]).
String contentHash(Object? value, {bool deleted = false}) => sha256
    .convert(utf8.encode(canonicalJson({'d': deleted, 'v': value})))
    .toString()
    .substring(0, 16);

/// [value] as JSON with the keys of every map sorted, so equal values
/// always give the same text.
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys.map((k) => '$k').toList()..sort())
      key: _sorted(value[key]),
  },
  List() => [for (final v in value) _sorted(v)],
  _ => value,
};
