import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// One page of changes from [SyncStore.changes].
typedef ChangePage = ({
  List<SyncRecord> records,
  int cursor,
  bool more,
  int head,
  bool reset,
});

/// A saved login token, without the token itself.
typedef TokenInfo = ({String name, DateTime created, DateTime? lastUsed});

/// The server's data in one SQLite file: the synced records with a
/// sequence number per change, the salt, and the hashes of the login
/// tokens. Tombstones are kept like any record.
class SyncStore {
  SyncStore._(this._db) {
    _db.execute('PRAGMA busy_timeout = 5000');
    _db.execute('PRAGMA journal_mode = WAL');
    _migrate();
  }

  factory SyncStore.open(String path) {
    final db = sqlite3.open(path);
    try {
      return SyncStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  factory SyncStore.inMemory() => SyncStore._(sqlite3.openInMemory());

  final Database _db;

  static const schemaVersion = 1;

  void _migrate() {
    if (_db.userVersion > schemaVersion) {
      throw StateError(
        'The database was written by a newer version of the server '
        '(schema ${_db.userVersion}). Install that version again.',
      );
    }
    if (_db.userVersion < 1) {
      _db.execute('BEGIN');
      _db.execute('''
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE records (
          space TEXT NOT NULL,
          key TEXT NOT NULL,
          t INTEGER NOT NULL,
          hash TEXT NOT NULL,
          deleted INTEGER NOT NULL,
          value TEXT NOT NULL,
          seq INTEGER NOT NULL,
          PRIMARY KEY (space, key)
        );
        CREATE INDEX records_seq ON records (space, seq);
        CREATE TABLE tokens (
          name TEXT PRIMARY KEY,
          hash TEXT NOT NULL UNIQUE,
          created INTEGER NOT NULL,
          last_used INTEGER
        );
      ''');
      _db.execute("INSERT INTO meta VALUES ('salt', ?), ('seq', '0')", [
        _randomHex(32),
      ]);
      _db.userVersion = 1;
      _db.execute('COMMIT');
    }
  }

  static String _randomHex(int bytes) {
    final r = Random.secure();
    return [
      for (var i = 0; i < bytes; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  String _meta(String key) =>
      _db.select('SELECT value FROM meta WHERE key = ?', [key]).single['value']
          as String;

  /// Made once with the database; see `SyncInfo.salt`.
  String get salt => _meta('salt');

  /// The number of the latest change, in any space.
  int get head => int.parse(_meta('seq'));

  /// The records of [space] changed after [since], oldest change first:
  /// at most [limit] and, after the first, about [maxBytes] of values.
  /// `head` is the latest change. With `reset` (and no records) when
  /// [since] or [known] is a change this database never had: it was
  /// restored from an older backup.
  ChangePage changes(
    String space,
    int since, {
    int known = 0,
    int limit = syncMaxRecords,
    int maxBytes = syncMaxPageBytes,
  }) {
    final head = this.head;
    if (since > head || known > head) {
      return (
        records: const [],
        cursor: 0,
        more: false,
        head: head,
        reset: true,
      );
    }
    final rows = _db.select(
      'SELECT key, t, deleted, value, seq FROM records '
      'WHERE space = ? AND seq > ? ORDER BY seq LIMIT ?',
      [space, since, limit + 1],
    );
    final records = <SyncRecord>[];
    var cursor = since;
    var bytes = 0;
    for (final row in rows.take(limit)) {
      final value = row['value'] as String;
      bytes += value.length + (row['key'] as String).length + 32;
      if (records.isNotEmpty && bytes > maxBytes) break;
      records.add(
        SyncRecord(
          key: row['key'] as String,
          t: row['t'] as int,
          value: jsonDecode(value),
          deleted: row['deleted'] == 1,
        ),
      );
      cursor = row['seq'] as int;
    }
    return (
      records: records,
      cursor: cursor,
      more: records.length < rows.length,
      head: head,
      reset: false,
    );
  }

  /// Stores each of [records] in [space] unless the stored copy wins
  /// ([SyncRecord.compareTo]); returns the stored copies that did, where
  /// they differ.
  List<SyncRecord> push(String space, List<SyncRecord> records) {
    final stale = <SyncRecord>[];
    final find = _db.prepare(
      'SELECT t, hash, deleted, value FROM records WHERE space = ? AND key = ?',
    );
    final upsert = _db.prepare(
      'INSERT INTO records (space, key, t, hash, deleted, value, seq) '
      'VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (space, key) DO UPDATE SET t = excluded.t, '
      'hash = excluded.hash, deleted = excluded.deleted, '
      'value = excluded.value, seq = excluded.seq',
    );
    _db.execute('BEGIN IMMEDIATE');
    try {
      var seq = int.parse(_meta('seq'));
      for (final r in records) {
        final current = find.select([space, r.key]).firstOrNull;
        if (current != null) {
          final version = SyncVersion(
            current['t'] as int,
            current['hash'] as String,
          );
          if (!r.beats(version)) {
            if (version != r.version) {
              stale.add(
                SyncRecord(
                  key: r.key,
                  t: version.t,
                  value: jsonDecode(current['value'] as String),
                  deleted: current['deleted'] == 1,
                ),
              );
            }
            continue;
          }
        }
        upsert.execute([
          space,
          r.key,
          r.t,
          r.hash,
          r.deleted ? 1 : 0,
          jsonEncode(r.value),
          ++seq,
        ]);
      }
      _db.execute("UPDATE meta SET value = ? WHERE key = 'seq'", ['$seq']);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      find.close();
      upsert.close();
    }
    return stale;
  }

  /// How many records each space holds.
  Map<String, int> counts() => {
    for (final row in _db.select(
      'SELECT space, COUNT(*) AS n FROM records GROUP BY space ORDER BY space',
    ))
      row['space'] as String: row['n'] as int,
  };

  static String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  /// A new login token named [name] (e.g. the device). Only its hash is
  /// kept: the token is shown once. Throws [ArgumentError] when [name] is
  /// taken.
  String createToken(String name, {DateTime? now}) {
    final bytes = List.generate(32, (_) => Random.secure().nextInt(256));
    final token = 'tvps_${base64Url.encode(bytes).replaceAll('=', '')}';
    try {
      _db.execute('INSERT INTO tokens VALUES (?, ?, ?, NULL)', [
        name,
        _hash(token),
        (now ?? DateTime.now()).millisecondsSinceEpoch,
      ]);
    } on SqliteException {
      throw ArgumentError.value(name, 'name', 'A token with this name exists');
    }
    return token;
  }

  List<TokenInfo> tokens() => [
    for (final row in _db.select(
      'SELECT name, created, last_used FROM tokens ORDER BY name',
    ))
      (
        name: row['name'] as String,
        created: DateTime.fromMillisecondsSinceEpoch(row['created'] as int),
        lastUsed: switch (row['last_used']) {
          final int t => DateTime.fromMillisecondsSinceEpoch(t),
          _ => null,
        },
      ),
  ];

  /// Deletes the token named [name]; false when there is none.
  bool revokeToken(String name) {
    _db.execute('DELETE FROM tokens WHERE name = ?', [name]);
    return _db.updatedRows > 0;
  }

  /// The name of [token]'s entry, or null when it isn't a saved token.
  /// Tokens are looked up by their hash, so the comparison never depends
  /// on how much of a guess is right.
  String? authenticate(String token, {DateTime? now}) {
    final hash = _hash(token);
    final row = _db.select(
      'SELECT name, last_used FROM tokens WHERE hash = ?',
      [hash],
    ).firstOrNull;
    if (row == null) return null;
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final last = row['last_used'] as int?;
    // Written at most once a minute.
    if (last == null || time - last > 60000) {
      _db.execute('UPDATE tokens SET last_used = ? WHERE hash = ?', [
        time,
        hash,
      ]);
    }
    return row['name'] as String;
  }

  /// A consistent copy of the database at [path] (which must not exist),
  /// also while the server runs.
  void backup(String path) {
    if (File(path).existsSync()) {
      throw ArgumentError.value(path, 'path', 'The file exists already');
    }
    _db.execute('VACUUM INTO ?', [path]);
  }

  void close() => _db.close();
}
