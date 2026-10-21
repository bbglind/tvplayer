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
      tmdbId: readString(info['tmdb_id']),
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
  final String? plot;
  final String? genre;
  final String? cast;
  final String? director;

  /// Release date as given by the panel (format varies, usually YYYY-MM-DD).
  final String? releaseDate;
  final Duration? duration;
  final List<String> backdropUrls;
  final String? trailerId;

  @override
  String toString() => 'Movie($streamId, $name)';
}
