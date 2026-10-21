import '../util/json.dart';

/// An episode of a series.
final class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.episodeNumber,
    required this.title,
    this.containerExtension,
    this.plot,
    this.duration,
    this.coverUrl,
    this.rating,
    this.releaseDate,
  });

  /// Parses an episode object from `get_series_info`. [fallbackSeason] is
  /// used when the episode itself doesn't state its season (it is then taken
  /// from the key it was listed under). Returns null when the id is missing.
  static Episode? fromJson(Map<String, Object?> json, {int? fallbackSeason}) {
    final id = readString(json['id']);
    if (id == null) return null;
    final info = readMap(json['info']) ?? const {};
    final durationSecs = readInt(info['duration_secs']);
    final episodeNumber = readInt(json['episode_num']) ?? 0;
    return Episode(
      id: id,
      season: readInt(json['season']) ?? fallbackSeason ?? 0,
      episodeNumber: episodeNumber,
      title: readString(json['title']) ?? 'Episode $episodeNumber',
      containerExtension: readString(json['container_extension']),
      plot: readString(info['plot']),
      duration: durationSecs != null ? Duration(seconds: durationSecs) : null,
      coverUrl:
          readString(info['movie_image']) ?? readString(info['cover_big']),
      rating: readDouble(info['rating']),
      releaseDate:
          readString(info['releasedate']) ?? readString(info['air_date']),
    );
  }

  /// Stream id of the episode, used to build its URL.
  final String id;
  final int season;
  final int episodeNumber;
  final String title;
  final String? containerExtension;
  final String? plot;
  final Duration? duration;
  final String? coverUrl;
  final double? rating;
  final String? releaseDate;

  @override
  String toString() => 'Episode($id, S${season}E$episodeNumber, $title)';
}
