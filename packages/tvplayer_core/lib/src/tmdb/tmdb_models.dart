import '../util/json.dart';

/// TMDB's two kinds of titles.
enum TmdbKind {
  movie,
  tv;

  /// The kind in a TMDB `media_type` or path segment; null for others
  /// (`person`…).
  static TmdbKind? parse(Object? value) => switch (value) {
    'movie' => movie,
    'tv' => tv,
    _ => null,
  };
}

/// A TMDB title: its kind and id. TMDB data is stored by this, never by a
/// provider's ids, so it is shared by variants and kept across providers.
final class TmdbKey {
  const TmdbKey(this.kind, this.id);

  /// Reads `movie/123` or `tv/45` as written by [toString].
  static TmdbKey? parse(String text) {
    final slash = text.indexOf('/');
    if (slash < 0) return null;
    final kind = TmdbKind.parse(text.substring(0, slash));
    final id = int.tryParse(text.substring(slash + 1));
    return kind == null || id == null || id <= 0 ? null : TmdbKey(kind, id);
  }

  /// A provider's `tmdb_id` value as a key of [kind]; null for missing,
  /// `0` or non-numeric ids.
  static TmdbKey? fromProvider(TmdbKind kind, String? tmdbId) {
    final id = tmdbId == null ? null : int.tryParse(tmdbId.trim());
    return id == null || id <= 0 ? null : TmdbKey(kind, id);
  }

  final TmdbKind kind;
  final int id;

  @override
  bool operator ==(Object other) =>
      other is TmdbKey && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '${kind.name}/$id';
}

/// One actor of a title's cast.
final class TmdbCast {
  const TmdbCast({
    required this.personId,
    required this.name,
    this.character,
    this.profilePath,
  });

  static TmdbCast? fromJson(Map<String, Object?> json) {
    final id = readInt(json['id']);
    final name = readString(json['name']);
    if (id == null || name == null) return null;
    return TmdbCast(
      personId: id,
      name: name,
      character: readString(json['character']),
      profilePath: readString(json['profile_path']),
    );
  }

  /// Compact form for storage, read back by [fromStored].
  List<Object?> toStored() => [personId, name, character, profilePath];

  static TmdbCast? fromStored(Object? value) {
    if (value is! List || value.length < 4) return null;
    final id = readInt(value[0]);
    final name = readString(value[1]);
    if (id == null || name == null) return null;
    return TmdbCast(
      personId: id,
      name: name,
      character: readString(value[2]),
      profilePath: readString(value[3]),
    );
  }

  final int personId;
  final String name;
  final String? character;
  final String? profilePath;
}

/// A genre as TMDB names it, e.g. `Drama`.
final class TmdbGenre {
  const TmdbGenre(this.id, this.name);

  final int id;
  final String name;
}

/// Everything kept about one movie or series.
final class TmdbTitle {
  const TmdbTitle({
    required this.key,
    required this.fetchedAt,
    this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.runtimeMinutes,
    this.seasonCount,
    this.status,
    this.vote,
    this.popularity,
    this.imdbId,
    this.posterPath,
    this.backdropPath,
    this.genres = const [],
    this.cast = const [],
    this.recommendations = const [],
  });

  /// Actors kept per title.
  static const maxCast = 15;

  /// Recommendations kept per title.
  static const maxRecommendations = 20;

  /// Parses `/movie/{id}` or `/tv/{id}` with `credits`, `recommendations`,
  /// `images` and (series) `external_ids` appended. Null without an id.
  static TmdbTitle? fromJson(
    TmdbKind kind,
    Map<String, Object?> json, {
    required DateTime fetchedAt,
  }) {
    final id = readInt(json['id']);
    if (id == null) return null;
    final movie = kind == TmdbKind.movie;
    final credits = readMap(json['credits']) ?? const {};
    final externalIds = readMap(json['external_ids']) ?? const {};
    final runtimes = readList(json['episode_run_time']).map(readInt);
    return TmdbTitle(
      key: TmdbKey(kind, id),
      fetchedAt: fetchedAt,
      title: readString(movie ? json['title'] : json['name']),
      originalTitle: readString(
        movie ? json['original_title'] : json['original_name'],
      ),
      year: readYear(
        readString(movie ? json['release_date'] : json['first_air_date']),
      ),
      overview: readString(json['overview']),
      runtimeMinutes: switch (movie
          ? readInt(json['runtime'])
          : runtimes.whereType<int>().firstOrNull) {
        final m? when m > 0 => m,
        _ => null,
      },
      seasonCount: movie ? null : readInt(json['number_of_seasons']),
      status: readString(json['status']),
      vote: switch (readDouble(json['vote_average'])) {
        final v? when v > 0 => v,
        _ => null,
      },
      popularity: readDouble(json['popularity']),
      imdbId: readImdbId(json['imdb_id'] ?? externalIds['imdb_id']),
      posterPath: readString(json['poster_path']),
      backdropPath: chooseBackdrop(
        readMap(json['images']),
        readString(json['backdrop_path']),
      ),
      genres: [
        for (final g in readList(json['genres']))
          if (readMap(g) case final g?)
            if ((readInt(g['id']), readString(g['name'])) case (
              final id?,
              final name?,
            ))
              TmdbGenre(id, name),
      ],
      cast: [
        for (final c in readList(credits['cast']).take(maxCast))
          if (readMap(c) case final c?) ?TmdbCast.fromJson(c),
      ],
      recommendations: [
        for (final r in readList(
          readMap(json['recommendations'])?['results'],
        ).take(maxRecommendations))
          if (readMap(r) case final r?)
            if (readInt(r['id']) case final id?)
              TmdbKey(TmdbKind.parse(r['media_type']) ?? kind, id),
      ],
    );
  }

  final TmdbKey key;
  final DateTime fetchedAt;
  final String? title;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final int? runtimeMinutes;

  /// Number of seasons (series).
  final int? seasonCount;

  /// TMDB's status, e.g. `Returning Series` or `Released`.
  final String? status;

  /// Average vote out of 10; null without votes.
  final double? vote;
  final double? popularity;
  final String? imdbId;
  final String? posterPath;

  /// The chosen backdrop (see [chooseBackdrop]).
  final String? backdropPath;
  final List<TmdbGenre> genres;
  final List<TmdbCast> cast;
  final List<TmdbKey> recommendations;

  /// Whether new episodes may still come, so seasons are worth refreshing.
  bool get ongoing => status == 'Returning Series' || status == 'In Production';

  /// Genre names as one text, e.g. `Drama, Crime`.
  String? get genreText =>
      genres.isEmpty ? null : genres.map((g) => g.name).join(', ');
}

/// The backdrop to show from a title's `images.backdrops`: one without
/// text (no language) first, then an English one, the best voted of each;
/// [fallback] (the title's `backdrop_path`) when there are none.
String? chooseBackdrop(Map<String, Object?>? images, String? fallback) {
  final backdrops = [
    for (final b in readList(images?['backdrops']))
      if (readMap(b) case final b?)
        if (readString(b['file_path']) case final path?)
          (
            path: path,
            language: readString(b['iso_639_1']),
            vote: readDouble(b['vote_average']) ?? 0,
          ),
  ];
  for (final language in [null, 'en']) {
    final best = backdrops.where((b) => b.language == language).toList()
      ..sort((a, b) => b.vote.compareTo(a.vote));
    if (best.isNotEmpty) return best.first.path;
  }
  return fallback;
}

/// One episode of a [TmdbSeason].
final class TmdbEpisode {
  const TmdbEpisode({
    required this.season,
    required this.number,
    this.name,
    this.overview,
    this.stillPath,
    this.airDate,
    this.runtimeMinutes,
  });

  static TmdbEpisode? fromJson(Map<String, Object?> json, int season) {
    final number = readInt(json['episode_number']);
    if (number == null) return null;
    return TmdbEpisode(
      season: readInt(json['season_number']) ?? season,
      number: number,
      name: readString(json['name']),
      overview: readString(json['overview']),
      stillPath: readString(json['still_path']),
      airDate: readString(json['air_date']),
      runtimeMinutes: readInt(json['runtime']),
    );
  }

  Map<String, Object?> toJson() => {
    's': season,
    'n': number,
    'name': ?name,
    'overview': ?overview,
    'still': ?stillPath,
    'air': ?airDate,
    'runtime': ?runtimeMinutes,
  };

  static TmdbEpisode? fromStored(Object? value) {
    final json = readMap(value);
    final season = readInt(json?['s']);
    final number = readInt(json?['n']);
    if (json == null || season == null || number == null) return null;
    return TmdbEpisode(
      season: season,
      number: number,
      name: readString(json['name']),
      overview: readString(json['overview']),
      stillPath: readString(json['still']),
      airDate: readString(json['air']),
      runtimeMinutes: readInt(json['runtime']),
    );
  }

  final int season;
  final int number;
  final String? name;
  final String? overview;
  final String? stillPath;
  final String? airDate;
  final int? runtimeMinutes;
}

/// The episodes of one season of a series (`/tv/{id}/season/{n}`).
final class TmdbSeason {
  const TmdbSeason({
    required this.tvId,
    required this.number,
    required this.fetchedAt,
    this.episodes = const [],
  });

  static TmdbSeason fromJson(
    int tvId,
    int number,
    Map<String, Object?> json, {
    required DateTime fetchedAt,
  }) => TmdbSeason(
    tvId: tvId,
    number: number,
    fetchedAt: fetchedAt,
    episodes: [
      for (final e in readList(json['episodes']))
        if (readMap(e) case final e?) ?TmdbEpisode.fromJson(e, number),
    ],
  );

  final int tvId;
  final int number;
  final DateTime fetchedAt;
  final List<TmdbEpisode> episodes;

  TmdbEpisode? episode(int number) =>
      episodes.where((e) => e.number == number).firstOrNull;
}

/// A title a person acted in.
final class TmdbCredit {
  const TmdbCredit(this.key, {this.character, this.year});

  final TmdbKey key;
  final String? character;
  final int? year;
}

/// A person (`/person/{id}` with `combined_credits`); only acting credits
/// are kept.
final class TmdbPerson {
  const TmdbPerson({
    required this.id,
    required this.name,
    required this.fetchedAt,
    this.biography,
    this.profilePath,
    this.credits = const [],
  });

  static TmdbPerson? fromJson(
    Map<String, Object?> json, {
    required DateTime fetchedAt,
  }) {
    final id = readInt(json['id']);
    final name = readString(json['name']);
    if (id == null || name == null) return null;
    final seen = <TmdbKey>{};
    final credits = <TmdbCredit>[];
    for (final c in readList(readMap(json['combined_credits'])?['cast'])) {
      final credit = readMap(c);
      if (credit == null) continue;
      final kind = TmdbKind.parse(credit['media_type']);
      final creditId = readInt(credit['id']);
      if (kind == null || creditId == null) continue;
      final key = TmdbKey(kind, creditId);
      if (!seen.add(key)) continue;
      credits.add(
        TmdbCredit(
          key,
          character: readString(credit['character']),
          year: readYear(
            readString(credit['release_date'] ?? credit['first_air_date']),
          ),
        ),
      );
    }
    return TmdbPerson(
      id: id,
      name: name,
      fetchedAt: fetchedAt,
      biography: readString(json['biography']),
      profilePath: readString(json['profile_path']),
      credits: credits,
    );
  }

  final int id;
  final String name;
  final DateTime fetchedAt;
  final String? biography;
  final String? profilePath;
  final List<TmdbCredit> credits;
}

/// One result of a title search.
final class TmdbSearchResult {
  const TmdbSearchResult(this.key, {this.title, this.originalTitle, this.year});

  static TmdbSearchResult? fromJson(TmdbKind kind, Map<String, Object?> json) {
    final id = readInt(json['id']);
    if (id == null) return null;
    final movie = kind == TmdbKind.movie;
    return TmdbSearchResult(
      TmdbKey(kind, id),
      title: readString(movie ? json['title'] : json['name']),
      originalTitle: readString(
        movie ? json['original_title'] : json['original_name'],
      ),
      year: readYear(
        readString(movie ? json['release_date'] : json['first_air_date']),
      ),
    );
  }

  final TmdbKey key;
  final String? title;
  final String? originalTitle;
  final int? year;
}

/// A title on TMDB's weekly trending list.
final class TmdbTrending {
  const TmdbTrending(
    this.key,
    this.rank, {
    this.genreIds = const [],
    this.genres = const [],
  });

  static TmdbTrending? fromJson(
    TmdbKind kind,
    Map<String, Object?> json,
    int rank,
  ) {
    final id = readInt(json['id']);
    if (id == null || id <= 0) return null;
    return TmdbTrending(
      TmdbKey(kind, id),
      rank,
      genreIds: [for (final g in readList(json['genre_ids'])) ?readInt(g)],
    );
  }

  final TmdbKey key;

  /// 1 for the most trending title of its kind.
  final int rank;

  /// TMDB's genre ids, as on the list.
  final List<int> genreIds;

  /// The genre names when read from the store: the stored title's, else
  /// those of [genreIds] that the store knows.
  final List<String> genres;
}

/// The stored trending list and when it was fetched (null: never).
final class TmdbTrendingList {
  const TmdbTrendingList(this.titles, this.fetchedAt);

  static const empty = TmdbTrendingList([], null);

  final List<TmdbTrending> titles;
  final DateTime? fetchedAt;
}
