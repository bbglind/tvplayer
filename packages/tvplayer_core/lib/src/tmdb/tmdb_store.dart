import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../util/json.dart';
import 'tmdb_models.dart';

/// How a title search ended.
enum MatchOutcome {
  /// Found; [TitleMatch.tmdbId] is the title.
  matched,

  /// Nothing surely the same; tried again later.
  noMatch,

  /// The user removed a wrong match; never searched again until allowed.
  removed,
}

/// The stored outcome of a title search.
final class TitleMatch {
  const TitleMatch(this.outcome, this.at, [this.tmdbId]);

  final MatchOutcome outcome;
  final DateTime at;
  final int? tmdbId;
}

/// A title's images, for lists.
typedef TmdbArtwork = ({TmdbKey key, String? poster, String? backdrop});

/// TMDB data kept permanently in a SQLite database, keyed by TMDB kind and
/// id (see [TmdbKey]): titles, genres, seasons, people, the outcomes of
/// title searches, the links the user removed and the trending list.
///
/// Synchronous; the app uses it from one background isolate.
class TmdbStore {
  TmdbStore._(this._db) {
    _db
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA synchronous = NORMAL')
      ..execute('PRAGMA busy_timeout = 5000');
    _migrate();
  }

  /// Opens (and creates) the database at [path].
  factory TmdbStore.open(String path) => TmdbStore._(sqlite3.open(path));

  factory TmdbStore.inMemory() => TmdbStore._(sqlite3.openInMemory());

  /// 2 added the trending list and `meta`.
  static const _version = 2;

  final Database _db;

  void close() => _db.close();

  void _migrate() {
    final version = _db.userVersion;
    if (version >= _version) return;
    _db.execute('''
      CREATE TABLE IF NOT EXISTS title (
        kind TEXT NOT NULL,
        id INTEGER NOT NULL,
        found INTEGER NOT NULL,
        fetched_at INTEGER NOT NULL,
        title TEXT,
        original_title TEXT,
        year INTEGER,
        overview TEXT,
        runtime INTEGER,
        seasons INTEGER,
        status TEXT,
        vote REAL,
        popularity REAL,
        imdb_id TEXT,
        poster_path TEXT,
        backdrop_path TEXT,
        cast_json TEXT,
        recs_json TEXT,
        PRIMARY KEY (kind, id)
      ) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS genre (
        kind TEXT NOT NULL,
        id INTEGER NOT NULL,
        name TEXT NOT NULL,
        PRIMARY KEY (kind, id)
      ) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS title_genre (
        kind TEXT NOT NULL,
        title_id INTEGER NOT NULL,
        genre_id INTEGER NOT NULL,
        PRIMARY KEY (kind, title_id, genre_id)
      ) WITHOUT ROWID;
      CREATE INDEX IF NOT EXISTS title_genre_by_genre
        ON title_genre (kind, genre_id);
      CREATE TABLE IF NOT EXISTS season (
        tv_id INTEGER NOT NULL,
        number INTEGER NOT NULL,
        fetched_at INTEGER NOT NULL,
        episodes_json TEXT NOT NULL,
        PRIMARY KEY (tv_id, number)
      ) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS person (
        id INTEGER PRIMARY KEY,
        fetched_at INTEGER NOT NULL,
        name TEXT NOT NULL,
        biography TEXT,
        profile_path TEXT,
        credits_json TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS title_match (
        kind TEXT NOT NULL,
        title_key TEXT NOT NULL,
        outcome TEXT NOT NULL,
        tmdb_id INTEGER,
        at INTEGER NOT NULL,
        PRIMARY KEY (kind, title_key)
      ) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS removed_link (
        kind TEXT NOT NULL,
        tmdb_id INTEGER NOT NULL,
        at INTEGER NOT NULL,
        PRIMARY KEY (kind, tmdb_id)
      ) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS trending (
        kind TEXT NOT NULL,
        id INTEGER NOT NULL,
        rank INTEGER NOT NULL,
        genre_ids TEXT NOT NULL,
        PRIMARY KEY (kind, id)
      ) WITHOUT ROWID;
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value INTEGER
      ) WITHOUT ROWID;
    ''');
    _db.userVersion = _version;
  }

  static int _ms(DateTime t) => t.millisecondsSinceEpoch;

  static DateTime _time(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch(readInt(ms) ?? 0, isUtc: true);

  void _transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // Titles.

  void putTitle(TmdbTitle t) => putTitles([t]);

  void putTitles(List<TmdbTitle> titles) => _transaction(() {
    final insert = _db.prepare(
      'INSERT OR REPLACE INTO title VALUES '
      '(?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    final genre = _db.prepare('INSERT OR REPLACE INTO genre VALUES (?, ?, ?)');
    final clearGenres = _db.prepare(
      'DELETE FROM title_genre WHERE kind = ? AND title_id = ?',
    );
    final titleGenre = _db.prepare(
      'INSERT OR IGNORE INTO title_genre VALUES (?, ?, ?)',
    );
    try {
      for (final t in titles) {
        final kind = t.key.kind.name;
        insert.execute([
          kind,
          t.key.id,
          _ms(t.fetchedAt),
          t.title,
          t.originalTitle,
          t.year,
          t.overview,
          t.runtimeMinutes,
          t.seasonCount,
          t.status,
          t.vote,
          t.popularity,
          t.imdbId,
          t.posterPath,
          t.backdropPath,
          jsonEncode([for (final c in t.cast) c.toStored()]),
          jsonEncode([for (final r in t.recommendations) '$r']),
        ]);
        clearGenres.execute([kind, t.key.id]);
        for (final g in t.genres) {
          genre.execute([kind, g.id, g.name]);
          titleGenre.execute([kind, t.key.id, g.id]);
        }
      }
    } finally {
      insert.close();
      genre.close();
      clearGenres.close();
      titleGenre.close();
    }
  });

  /// Records that TMDB has no title [key], so it isn't asked again before
  /// [notFoundRetry].
  void putNotFound(TmdbKey key, DateTime at) => _db.execute(
    'INSERT OR REPLACE INTO title (kind, id, found, fetched_at) '
    'VALUES (?, ?, 0, ?)',
    [key.kind.name, key.id, _ms(at)],
  );

  /// The stored title [key]; null when it isn't stored or TMDB has none.
  TmdbTitle? title(TmdbKey key) {
    final rows = _db.select(
      'SELECT t.*, (SELECT json_group_array(json_array(g.id, g.name)) '
      'FROM title_genre tg JOIN genre g '
      'ON g.kind = tg.kind AND g.id = tg.genre_id '
      'WHERE tg.kind = t.kind AND tg.title_id = t.id) AS genres '
      'FROM title t WHERE kind = ? AND id = ? AND found = 1',
      [key.kind.name, key.id],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    List<Object?> list(Object? json) {
      if (json is! String) return const [];
      try {
        return readList(jsonDecode(json));
      } on FormatException {
        return const [];
      }
    }

    return TmdbTitle(
      key: key,
      fetchedAt: _time(r['fetched_at']),
      title: r['title'] as String?,
      originalTitle: r['original_title'] as String?,
      year: r['year'] as int?,
      overview: r['overview'] as String?,
      runtimeMinutes: r['runtime'] as int?,
      seasonCount: r['seasons'] as int?,
      status: r['status'] as String?,
      vote: (r['vote'] as num?)?.toDouble(),
      popularity: (r['popularity'] as num?)?.toDouble(),
      imdbId: r['imdb_id'] as String?,
      posterPath: r['poster_path'] as String?,
      backdropPath: r['backdrop_path'] as String?,
      genres: [
        for (final g in list(r['genres']))
          if (g case [final int id, final String name]) TmdbGenre(id, name),
      ]..sort((a, b) => a.name.compareTo(b.name)),
      cast: [for (final c in list(r['cast_json'])) ?TmdbCast.fromStored(c)],
      recommendations: [
        for (final k in list(r['recs_json']))
          if (k is String) ?TmdbKey.parse(k),
      ],
    );
  }

  /// When each stored title was fetched; titles TMDB doesn't have are
  /// included only when fetched after [notFoundSince].
  Map<TmdbKey, DateTime> fetchedTitles({required DateTime notFoundSince}) => {
    for (final r in _db.select(
      'SELECT kind, id, fetched_at FROM title '
      'WHERE found = 1 OR fetched_at >= ?',
      [_ms(notFoundSince)],
    ))
      if (TmdbKind.parse(r['kind']) case final kind?)
        TmdbKey(kind, r['id'] as int): _time(r['fetched_at']),
  };

  /// The poster and backdrop of every stored title.
  List<TmdbArtwork> artwork() => [
    for (final r in _db.select(
      'SELECT kind, id, poster_path, backdrop_path FROM title '
      'WHERE found = 1 AND (poster_path IS NOT NULL '
      'OR backdrop_path IS NOT NULL)',
    ))
      if (TmdbKind.parse(r['kind']) case final kind?)
        (
          key: TmdbKey(kind, r['id'] as int),
          poster: r['poster_path'] as String?,
          backdrop: r['backdrop_path'] as String?,
        ),
  ];

  /// The genre names of every stored title, A to Z.
  Map<TmdbKey, List<String>> genreNames() {
    final names = <TmdbKey, List<String>>{};
    for (final r in _db.select(
      'SELECT tg.kind, tg.title_id, g.name FROM title_genre tg '
      'JOIN genre g ON g.kind = tg.kind AND g.id = tg.genre_id '
      'JOIN title t ON t.kind = tg.kind AND t.id = tg.title_id '
      'WHERE t.found = 1 ORDER BY g.name',
    )) {
      if (TmdbKind.parse(r['kind']) case final kind?) {
        (names[TmdbKey(kind, r['title_id'] as int)] ??= []).add(
          r['name'] as String,
        );
      }
    }
    return names;
  }

  // Trending.

  static const _trendingFetchedAt = 'trending_fetched_at';

  /// Replaces the trending list with [titles], fetched [at].
  void putTrending(List<TmdbTrending> titles, DateTime at) => _transaction(() {
    _db.execute('DELETE FROM trending');
    final insert = _db.prepare(
      'INSERT OR IGNORE INTO trending VALUES (?, ?, ?, ?)',
    );
    try {
      for (final t in titles) {
        insert.execute([
          t.key.kind.name,
          t.key.id,
          t.rank,
          jsonEncode(t.genreIds),
        ]);
      }
    } finally {
      insert.close();
    }
    _db.execute('INSERT OR REPLACE INTO meta VALUES (?, ?)', [
      _trendingFetchedAt,
      _ms(at),
    ]);
  });

  /// The stored trending list by kind and rank, with genre names.
  TmdbTrendingList trending() {
    final at = _db.select('SELECT value FROM meta WHERE key = ?', [
      _trendingFetchedAt,
    ]);
    final fetchedAt = at.isEmpty || at.first['value'] == null
        ? null
        : _time(at.first['value']);
    final genreNames = {
      for (final r in _db.select('SELECT kind, id, name FROM genre'))
        (r['kind'] as String, r['id'] as int): r['name'] as String,
    };
    final rows = _db.select(
      'SELECT tr.kind, tr.id, tr.rank, tr.genre_ids, '
      '(SELECT json_group_array(g.name) FROM title_genre tg JOIN genre g '
      'ON g.kind = tg.kind AND g.id = tg.genre_id '
      'WHERE tg.kind = tr.kind AND tg.title_id = tr.id) AS names '
      'FROM trending tr ORDER BY tr.kind, tr.rank',
    );
    List<Object?> list(Object? json) {
      if (json is! String) return const [];
      try {
        return readList(jsonDecode(json));
      } on FormatException {
        return const [];
      }
    }

    return TmdbTrendingList([
      for (final r in rows)
        if (TmdbKind.parse(r['kind']) case final kind?)
          () {
            final ids = [for (final g in list(r['genre_ids'])) ?readInt(g)];
            final stored = [for (final n in list(r['names'])) ?readString(n)];
            return TmdbTrending(
              TmdbKey(kind, r['id'] as int),
              r['rank'] as int,
              genreIds: ids,
              genres: stored.isNotEmpty
                  ? (stored..sort())
                  : [for (final id in ids) ?genreNames[(kind.name, id)]],
            );
          }(),
    ], fetchedAt);
  }

  // Seasons.

  void putSeason(TmdbSeason season) =>
      _db.execute('INSERT OR REPLACE INTO season VALUES (?, ?, ?, ?)', [
        season.tvId,
        season.number,
        _ms(season.fetchedAt),
        jsonEncode([for (final e in season.episodes) e.toJson()]),
      ]);

  TmdbSeason? season(int tvId, int number) {
    final rows = _db.select(
      'SELECT fetched_at, episodes_json FROM season '
      'WHERE tv_id = ? AND number = ?',
      [tvId, number],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return TmdbSeason(
      tvId: tvId,
      number: number,
      fetchedAt: _time(r['fetched_at']),
      episodes: [
        for (final e in readList(jsonDecode(r['episodes_json'] as String)))
          ?TmdbEpisode.fromStored(e),
      ],
    );
  }

  // People.

  void putPerson(TmdbPerson p) =>
      _db.execute('INSERT OR REPLACE INTO person VALUES (?, ?, ?, ?, ?, ?)', [
        p.id,
        _ms(p.fetchedAt),
        p.name,
        p.biography,
        p.profilePath,
        jsonEncode([
          for (final c in p.credits) ['${c.key}', c.character, c.year],
        ]),
      ]);

  TmdbPerson? person(int id) {
    final rows = _db.select('SELECT * FROM person WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return TmdbPerson(
      id: id,
      name: r['name'] as String,
      fetchedAt: _time(r['fetched_at']),
      biography: r['biography'] as String?,
      profilePath: r['profile_path'] as String?,
      credits: [
        for (final c in readList(jsonDecode(r['credits_json'] as String)))
          if (c is List && c.length >= 3)
            if (TmdbKey.parse('${c[0]}') case final key?)
              TmdbCredit(key, character: readString(c[1]), year: readInt(c[2])),
      ],
    );
  }

  // Title searches and removed links.

  void putMatch(TmdbKind kind, String key, TitleMatch match) => _db.execute(
    'INSERT OR REPLACE INTO title_match VALUES (?, ?, ?, ?, ?)',
    [kind.name, key, match.outcome.name, match.tmdbId, _ms(match.at)],
  );

  /// Every stored title search outcome, by kind and title key.
  Map<(TmdbKind, String), TitleMatch> matches() => {
    for (final r in _db.select('SELECT * FROM title_match'))
      if ((
            TmdbKind.parse(r['kind']),
            MatchOutcome.values.asNameMap()[r['outcome']],
          )
          case (final kind?, final outcome?))
        (kind, r['title_key'] as String): TitleMatch(
          outcome,
          _time(r['at']),
          r['tmdb_id'] as int?,
        ),
  };

  /// Stops using TMDB title [key] for the provider titles linked to it by
  /// their own TMDB id.
  void removeLink(TmdbKey key, DateTime at) => _db.execute(
    'INSERT OR REPLACE INTO removed_link VALUES (?, ?, ?)',
    [key.kind.name, key.id, _ms(at)],
  );

  Set<TmdbKey> removedLinks() => {
    for (final r in _db.select('SELECT kind, tmdb_id FROM removed_link'))
      if (TmdbKind.parse(r['kind']) case final kind?)
        TmdbKey(kind, r['tmdb_id'] as int),
  };

  /// Removed matches and links together.
  int removedCount() =>
      (_db.select(
            'SELECT (SELECT count(*) FROM removed_link) + '
            '(SELECT count(*) FROM title_match WHERE outcome = ?) AS n',
            [MatchOutcome.removed.name],
          ).first['n']
          as int?) ??
      0;

  /// Forgets every removed match and link, so they are matched again.
  void allowMatchingAgain() => _transaction(() {
    _db
      ..execute('DELETE FROM removed_link')
      ..execute('DELETE FROM title_match WHERE outcome = ?', [
        MatchOutcome.removed.name,
      ]);
  });
}
