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

/// SkipDB's answers per episode (IMDb id, season, episode) and the
/// length they were asked for, in SQLite: one copy's answer never
/// replaces another's (e.g. a prefetch with the provider's length and
/// playback with mpv's).
///
/// Only SkipDB's data belongs here (ODbL): TheIntroDB's terms allow no
/// lasting copy, so its answers are never stored.
class SkipStore {
  SkipStore._(this._db) {
    _db
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA busy_timeout = 5000');
    if (_db.userVersion < 3) {
      // Version 1 kept one answer per episode, and "nothing known" for
      // times only left out for another length; version 2 kept credits
      // that end early: start again.
      _db
        ..execute('DROP TABLE IF EXISTS skipdb_segment')
        ..execute('''
          CREATE TABLE skipdb_segment (
            imdb_id TEXT NOT NULL,
            season INTEGER NOT NULL,
            episode INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            found INTEGER NOT NULL,
            fetched_at INTEGER NOT NULL,
            segments_json TEXT NOT NULL,
            PRIMARY KEY (imdb_id, season, episode, duration_ms)
          ) WITHOUT ROWID;
        ''')
        ..userVersion = 3;
    }
  }

  /// Opens (and creates) the database at [path].
  factory SkipStore.open(String path) => SkipStore._(sqlite3.open(path));

  factory SkipStore.inMemory() => SkipStore._(sqlite3.openInMemory());

  final Database _db;

  void close() => _db.close();

  /// Stands for "asked without a length" in `duration_ms`.
  static const _noLength = -1;

  /// The stored answer for the episode asked for [duration] (within
  /// [skipDurationTolerance], the closest), or null when there is none or
  /// it is older than its TTL. With [anyAge] (a downloaded episode, played
  /// without asking SkipDB) any answer will do: the closest length, else
  /// the newest.
  SkipSegments? get(
    String imdbId,
    int season,
    int episode, {
    Duration? duration,
    required DateTime now,
    bool anyAge = false,
  }) {
    final wanted = duration?.inMilliseconds ?? _noLength;
    final rows = _db.select(
      'SELECT duration_ms, found, fetched_at, segments_json '
      'FROM skipdb_segment WHERE imdb_id = ? AND season = ? AND episode = ? '
      'ORDER BY found DESC, fetched_at DESC',
      [imdbId, season, episode],
    );
    int gap(Row r) => ((readInt(r['duration_ms']) ?? _noLength) - wanted).abs();
    final candidates = anyAge
        ? rows.toList()
        : [
            for (final r in rows)
              if (duration == null
                  ? readInt(r['duration_ms']) == _noLength
                  : gap(r) <= skipDurationTolerance.inMilliseconds)
                r,
          ];
    if (candidates.isEmpty) return null;
    // The closest; among equal gaps the first (found, newer: the order).
    var row = candidates.first;
    for (final r in candidates.skip(1)) {
      if (gap(r) < gap(row)) row = r;
    }
    final found = readInt(row['found']) == 1;
    if (!anyAge) {
      final at = DateTime.fromMillisecondsSinceEpoch(
        readInt(row['fetched_at']) ?? 0,
        isUtc: true,
      );
      if (now.difference(at) > (found ? skipFoundTtl : skipNotFoundTtl)) {
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
      duration?.inMilliseconds ?? _noLength,
      segments.isEmpty ? 0 : 1,
      at.millisecondsSinceEpoch,
      jsonEncode(segments.toJson()),
    ],
  );
}
