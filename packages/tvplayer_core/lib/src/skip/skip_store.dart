import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../util/json.dart';
import 'skip_segments.dart';

/// How long SkipDB's answer for an episode is used before asking again:
/// times found, and "nothing known" (more likely to change).
const skipFoundTtl = Duration(days: 30);
const skipNotFoundTtl = Duration(days: 3);

/// A stored answer is for this copy when its length is this close.
const skipDurationTolerance = Duration(seconds: 2);

/// SkipDB's answers per episode (IMDb id, season, episode) in SQLite,
/// with the length they were asked for.
///
/// Only SkipDB's data belongs here (ODbL): TheIntroDB's terms allow no
/// lasting copy, so its answers are never stored.
class SkipStore {
  SkipStore._(this._db) {
    _db
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA busy_timeout = 5000');
    if (_db.userVersion < 1) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS skipdb_segment (
          imdb_id TEXT NOT NULL,
          season INTEGER NOT NULL,
          episode INTEGER NOT NULL,
          duration_ms INTEGER,
          found INTEGER NOT NULL,
          fetched_at INTEGER NOT NULL,
          segments_json TEXT NOT NULL,
          PRIMARY KEY (imdb_id, season, episode)
        ) WITHOUT ROWID;
      ''');
      _db.userVersion = 1;
    }
  }

  /// Opens (and creates) the database at [path].
  factory SkipStore.open(String path) => SkipStore._(sqlite3.open(path));

  factory SkipStore.inMemory() => SkipStore._(sqlite3.openInMemory());

  final Database _db;

  void close() => _db.close();

  /// The stored answer for the episode, or null when there is none, it
  /// is older than its TTL or it was asked for another length than
  /// [duration]. With [anyAge] (a downloaded episode, played without
  /// asking SkipDB) the age and the length don't matter.
  SkipSegments? get(
    String imdbId,
    int season,
    int episode, {
    Duration? duration,
    required DateTime now,
    bool anyAge = false,
  }) {
    final rows = _db.select(
      'SELECT duration_ms, found, fetched_at, segments_json '
      'FROM skipdb_segment WHERE imdb_id = ? AND season = ? AND episode = ?',
      [imdbId, season, episode],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final found = readInt(row['found']) == 1;
    if (!anyAge) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        readInt(row['fetched_at']) ?? 0,
        isUtc: true,
      );
      if (now.difference(at) > (found ? skipFoundTtl : skipNotFoundTtl)) {
        return null;
      }
      final stored = readInt(row['duration_ms']);
      if (duration != null &&
          (stored == null ||
              (stored - duration.inMilliseconds).abs() >
                  skipDurationTolerance.inMilliseconds)) {
        return null;
      }
    }
    try {
      return SkipSegments.fromJson(jsonDecode(row['segments_json'] as String));
    } on FormatException {
      return null;
    }
  }

  /// Stores SkipDB's answer [segments] for the episode, asked for a copy
  /// of [duration].
  void put(
    String imdbId,
    int season,
    int episode,
    SkipSegments segments, {
    Duration? duration,
    required DateTime at,
  }) => _db.execute(
    'INSERT OR REPLACE INTO skipdb_segment VALUES '
    '(?, ?, ?, ?, ?, ?, ?)',
    [
      imdbId,
      season,
      episode,
      duration?.inMilliseconds,
      segments.isEmpty ? 0 : 1,
      at.millisecondsSinceEpoch,
      jsonEncode(segments.toJson()),
    ],
  );
}
