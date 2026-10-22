import '../util/json.dart';

/// A VOD movie. List entries (`get_vod_streams`) carry the basic fields;
/// [Movie.fromVodInfoJson] (`get_vod_info`) fills in the details as well.
final class Movie {
  const Movie({
    required this.streamId,
    required this.name,
    this.containerExtension,
    this.posterUrl,
    this.categoryId,
    this.rating,
    this.added,
    this.tmdbId,
    this.imdbId,
    this.plot,
    this.genre,
    this.cast,
    this.director,
    this.releaseDate,
    this.duration,
    this.backdropUrls = const [],
    this.trailerId,
  });

  /// Parses a `get_vod_streams` entry; returns null when the stream id is
  /// missing or invalid.
  static Movie? fromJson(Map<String, Object?> json) {
    final streamId = readInt(json['stream_id']);
    if (streamId == null) return null;
    return Movie(
      streamId: streamId,
      name: readString(json['name']) ?? '',
      containerExtension: readString(json['container_extension']),
      posterUrl: readString(json['stream_icon']),
      categoryId: readString(json['category_id']),
      rating: readDouble(json['rating']),
      added: readEpochSeconds(json['added']),
      tmdbId: readString(json['tmdb_id'] ?? json['tmdb']),
      imdbId: readImdbId(json['imdb_id'] ?? json['imdb']),
    );
  }

  /// Parses a `get_vod_info` response (`{"info": {...}, "movie_data": {...}}`).
  /// Returns null when no stream id can be found.
  static Movie? fromVodInfoJson(Map<String, Object?> json) {
    final info = readMap(json['info']) ?? const {};
    final data = readMap(json['movie_data']) ?? const {};
    final streamId = readInt(data['stream_id']);
    if (streamId == null) return null;
    final durationSecs = readInt(info['duration_secs']);
    return Movie(
      streamId: streamId,
      name: readString(data['name']) ?? readString(info['name']) ?? '',
      containerExtension: readString(data['container_extension']),
      posterUrl:
          readString(info['movie_image']) ?? readString(info['cover_big']),
      categoryId: readString(data['category_id']),
      rating: readDouble(info['rating']),
      added: readEpochSeconds(data['added']),
      tmdbId: readString(info['tmdb_id'] ?? info['tmdb']),
      imdbId: readImdbId(info['imdb_id'] ?? info['imdb']),
      plot: readString(info['plot']) ?? readString(info['description']),
      genre: readString(info['genre']),
      cast: readString(info['cast']) ?? readString(info['actors']),
      director: readString(info['director']),
      releaseDate:
          readString(info['releasedate']) ?? readString(info['release_date']),
      duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      backdropUrls: readStringList(info['backdrop_path']),
      trailerId: readString(info['youtube_trailer']),
    );
  }

  final int streamId;
  final String name;

  /// File extension used to build the stream URL, e.g. `mkv` or `mp4`.
  final String? containerExtension;
  final String? posterUrl;
  final String? categoryId;
  final double? rating;
  final DateTime? added;
  final String? tmdbId;

  /// IMDb id like `tt0111161`, when the panel sends one.
  final String? imdbId;
  final String? plot;
  final String? genre;
  final String? cast;
  final String? director;

  /// Release date as given by the panel (format varies, usually YYYY-MM-DD).
  final String? releaseDate;
  final Duration? duration;
  final List<String> backdropUrls;
  final String? trailerId;

  /// Release year from [releaseDate], or a trailing `(YYYY)` in [name].
  int? get year => readYear(releaseDate) ?? yearInName(name);

  /// The list fields in `get_vod_streams` shape, so [fromJson] reads them
  /// back. Used for the catalogue cache.
  Map<String, Object?> toJson() => {
    'stream_id': streamId,
    'name': name,
    'container_extension': ?containerExtension,
    'stream_icon': ?posterUrl,
    'category_id': ?categoryId,
    'rating': ?rating,
    if (added case final added?) 'added': added.millisecondsSinceEpoch ~/ 1000,
    'tmdb_id': ?tmdbId,
    'imdb_id': ?imdbId,
  };

  @override
  String toString() => 'Movie($streamId, $name)';
}
