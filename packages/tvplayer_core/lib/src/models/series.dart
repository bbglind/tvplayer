import '../util/json.dart';
import 'episode.dart';

/// A TV series.
final class Series {
  const Series({
    required this.seriesId,
    required this.name,
    this.coverUrl,
    this.categoryId,
    this.plot,
    this.genre,
    this.cast,
    this.director,
    this.releaseDate,
    this.rating,
    this.backdropUrls = const [],
    this.trailerId,
    this.lastModified,
    this.tmdbId,
    this.imdbId,
  });

  /// Parses a `get_series` entry, or the `info` object of `get_series_info`
  /// (pass [seriesId] there since that object usually lacks it). Returns
  /// null when no id is available.
  static Series? fromJson(Map<String, Object?> json, {int? seriesId}) {
    final id = readInt(json['series_id']) ?? seriesId;
    if (id == null) return null;
    return Series(
      seriesId: id,
      name: readString(json['name']) ?? readString(json['title']) ?? '',
      coverUrl: readString(json['cover']),
      categoryId: readString(json['category_id']),
      plot: readString(json['plot']),
      genre: readString(json['genre']),
      cast: readString(json['cast']),
      director: readString(json['director']),
      releaseDate:
          readString(json['releaseDate']) ?? readString(json['release_date']),
      rating: readDouble(json['rating']),
      backdropUrls: readStringList(json['backdrop_path']),
      trailerId: readString(json['youtube_trailer']),
      lastModified: readEpochSeconds(json['last_modified']),
      tmdbId: readString(json['tmdb_id'] ?? json['tmdb']),
      imdbId: readImdbId(json['imdb_id'] ?? json['imdb']),
    );
  }

  final int seriesId;
  final String name;
  final String? coverUrl;
  final String? categoryId;
  final String? plot;
  final String? genre;
  final String? cast;
  final String? director;
  final String? releaseDate;
  final double? rating;
  final List<String> backdropUrls;
  final String? trailerId;
  final DateTime? lastModified;
  final String? tmdbId;

  /// IMDb id like `tt0903747`, when the panel sends one.
  final String? imdbId;

  /// Release year from [releaseDate], or a trailing `(YYYY)` in [name].
  int? get year => readYear(releaseDate) ?? yearInName(name);

  /// The list fields in `get_series` shape, so [fromJson] reads them back.
  /// Used for the catalogue cache.
  Map<String, Object?> toJson() => {
    'series_id': seriesId,
    'name': name,
    'cover': ?coverUrl,
    'category_id': ?categoryId,
    'plot': ?plot,
    'genre': ?genre,
    'cast': ?cast,
    'director': ?director,
    'releaseDate': ?releaseDate,
    'rating': ?rating,
    if (backdropUrls.isNotEmpty) 'backdrop_path': backdropUrls,
    'youtube_trailer': ?trailerId,
    if (lastModified case final t?)
      'last_modified': t.millisecondsSinceEpoch ~/ 1000,
    'tmdb_id': ?tmdbId,
    'imdb_id': ?imdbId,
  };

  @override
  String toString() => 'Series($seriesId, $name)';
}

/// A season of a [Series].
final class Season {
  const Season({
    required this.seasonNumber,
    required this.name,
    this.episodeCount,
    this.coverUrl,
    this.overview,
    this.airDate,
  });

  static Season? fromJson(Map<String, Object?> json) {
    final number = readInt(json['season_number']);
    if (number == null) return null;
    return Season(
      seasonNumber: number,
      name: readString(json['name']) ?? 'Season $number',
      episodeCount: readInt(json['episode_count']),
      coverUrl: readString(json['cover_big']) ?? readString(json['cover']),
      overview: readString(json['overview']),
      airDate: readString(json['air_date']),
    );
  }

  final int seasonNumber;
  final String name;
  final int? episodeCount;
  final String? coverUrl;
  final String? overview;
  final String? airDate;

  @override
  String toString() => 'Season($seasonNumber, $name)';
}

/// Result of `get_series_info`: the series with its seasons and episodes.
final class SeriesInfo {
  const SeriesInfo({
    required this.series,
    required this.seasons,
    required this.episodes,
  });

  final Series series;

  /// Seasons sorted by number. When the panel sends no season metadata,
  /// seasons are derived from the episodes.
  final List<Season> seasons;

  /// All episodes, sorted by season then episode number.
  final List<Episode> episodes;

  List<Episode> episodesForSeason(int seasonNumber) =>
      episodes.where((e) => e.season == seasonNumber).toList();

  @override
  String toString() =>
      'SeriesInfo(${series.name}, ${seasons.length} seasons, '
      '${episodes.length} episodes)';
}
