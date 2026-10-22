import '../models/episode.dart';
import '../models/movie.dart';
import '../models/series.dart';
import '../vod/vod_source.dart';

/// Descriptive information about one episode, for display.
final class EpisodeMetadata {
  const EpisodeMetadata({
    this.title,
    this.plot,
    this.stillUrl,
    this.rating,
    this.airDate,
    this.duration,
  });

  final String? title;
  final String? plot;

  /// Thumbnail image of the episode.
  final String? stillUrl;
  final double? rating;
  final String? airDate;
  final Duration? duration;

  /// This metadata with gaps filled from [other].
  EpisodeMetadata mergedWith(EpisodeMetadata other) => EpisodeMetadata(
    title: title ?? other.title,
    plot: plot ?? other.plot,
    stillUrl: stillUrl ?? other.stillUrl,
    rating: rating ?? other.rating,
    airDate: airDate ?? other.airDate,
    duration: duration ?? other.duration,
  );
}

/// Descriptive information about a movie or series, for display. Playback
/// never depends on it.
final class MediaMetadata {
  const MediaMetadata({
    this.title,
    this.year,
    this.plot,
    this.genre,
    this.rating,
    this.duration,
    this.cast,
    this.director,
    this.posterUrl,
    this.backdropUrls = const [],
    this.tmdbId,
    this.imdbId,
    this.episodes = const {},
  });

  /// Metadata from the provider's details of a movie (`get_vod_info`),
  /// with gaps filled from its list entry.
  factory MediaMetadata.fromMovie(Movie details, [Movie? listEntry]) =>
      MediaMetadata(
        title: _nonEmpty(details.name) ?? _nonEmpty(listEntry?.name),
        year: details.year ?? listEntry?.year,
        plot: details.plot,
        genre: details.genre,
        rating: details.rating ?? listEntry?.rating,
        duration: details.duration,
        cast: details.cast,
        director: details.director,
        posterUrl: details.posterUrl ?? listEntry?.posterUrl,
        backdropUrls: details.backdropUrls,
        tmdbId: details.tmdbId ?? listEntry?.tmdbId,
        imdbId: details.imdbId ?? listEntry?.imdbId,
      );

  /// Metadata from the provider's `get_series_info`, with gaps filled from
  /// the series' list entry.
  factory MediaMetadata.fromSeriesInfo(SeriesInfo info, [Series? listEntry]) {
    final s = info.series;
    return MediaMetadata(
      title: _nonEmpty(s.name) ?? _nonEmpty(listEntry?.name),
      year: s.year ?? listEntry?.year,
      plot: s.plot ?? listEntry?.plot,
      genre: s.genre ?? listEntry?.genre,
      rating: s.rating ?? listEntry?.rating,
      cast: s.cast ?? listEntry?.cast,
      director: s.director ?? listEntry?.director,
      posterUrl: s.coverUrl ?? listEntry?.coverUrl,
      backdropUrls: s.backdropUrls.isNotEmpty
          ? s.backdropUrls
          : listEntry?.backdropUrls ?? const [],
      tmdbId: s.tmdbId ?? listEntry?.tmdbId,
      imdbId: s.imdbId ?? listEntry?.imdbId,
      episodes: {
        for (final e in info.episodes)
          (e.season, e.episodeNumber): EpisodeMetadata(
            title: e.title,
            plot: e.plot,
            stillUrl: e.coverUrl,
            rating: e.rating,
            airDate: e.releaseDate,
            duration: e.duration,
          ),
      },
    );
  }

  final String? title;
  final int? year;
  final String? plot;
  final String? genre;

  /// Rating out of 10.
  final double? rating;
  final Duration? duration;
  final String? cast;
  final String? director;
  final String? posterUrl;
  final List<String> backdropUrls;
  final String? tmdbId;
  final String? imdbId;

  /// Per-episode metadata of a series, keyed by (season, episode number).
  final Map<(int, int), EpisodeMetadata> episodes;

  /// Metadata for [episode], if known.
  EpisodeMetadata? episode(Episode episode) =>
      episodes[(episode.season, episode.episodeNumber)];

  /// This metadata with gaps filled from [other]. Episodes are merged one
  /// by one.
  MediaMetadata mergedWith(MediaMetadata other) => MediaMetadata(
    title: title ?? other.title,
    year: year ?? other.year,
    plot: plot ?? other.plot,
    genre: genre ?? other.genre,
    rating: rating ?? other.rating,
    duration: duration ?? other.duration,
    cast: cast ?? other.cast,
    director: director ?? other.director,
    posterUrl: posterUrl ?? other.posterUrl,
    backdropUrls: backdropUrls.isNotEmpty ? backdropUrls : other.backdropUrls,
    tmdbId: tmdbId ?? other.tmdbId,
    imdbId: imdbId ?? other.imdbId,
    episodes: {
      ...other.episodes,
      for (final MapEntry(:key, :value) in episodes.entries)
        key: switch (other.episodes[key]) {
          final o? => value.mergedWith(o),
          null => value,
        },
    },
  );

  static String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
}

/// Somewhere to get descriptive metadata from: the provider today, maybe
/// TMDB later. Sources find items by the ids on [Movie] and [Series]
/// (`tmdbId`, `imdbId`) or by name.
abstract interface class MetadataSource {
  /// Metadata for [movie], or null when this source knows nothing about it.
  Future<MediaMetadata?> movie(Movie movie);

  /// Metadata for [series], including its episodes where known; null when
  /// this source knows nothing about it.
  Future<MediaMetadata?> series(Series series);
}

/// [MetadataSource] using the provider's own data (`get_vod_info`,
/// `get_series_info`).
class ProviderMetadataSource implements MetadataSource {
  ProviderMetadataSource(this._source);

  final VodSource _source;

  @override
  Future<MediaMetadata?> movie(Movie movie) async =>
      MediaMetadata.fromMovie(await _source.movieInfo(movie), movie);

  @override
  Future<MediaMetadata?> series(Series series) async =>
      MediaMetadata.fromSeriesInfo(
        await _source.seriesInfo(series.seriesId),
        series,
      );
}

/// Asks several sources and merges their answers: earlier sources win,
/// later ones fill gaps. A failing source is skipped; only when all fail is
/// the first error rethrown.
class CombinedMetadataSource implements MetadataSource {
  CombinedMetadataSource(this.sources);

  final List<MetadataSource> sources;

  @override
  Future<MediaMetadata?> movie(Movie movie) => _combine((s) => s.movie(movie));

  @override
  Future<MediaMetadata?> series(Series series) =>
      _combine((s) => s.series(series));

  Future<MediaMetadata?> _combine(
    Future<MediaMetadata?> Function(MetadataSource) ask,
  ) async {
    final results = await Future.wait([
      for (final s in sources)
        ask(s).then<Object?>((m) => m, onError: (Object e) => _Failed(e)),
    ]);
    MediaMetadata? merged;
    _Failed? firstFailure;
    for (final r in results) {
      switch (r) {
        case MediaMetadata m:
          merged = merged?.mergedWith(m) ?? m;
        case _Failed f:
          firstFailure ??= f;
      }
    }
    if (firstFailure != null && results.every((r) => r is _Failed)) {
      throw firstFailure.error;
    }
    return merged;
  }
}

final class _Failed {
  const _Failed(this.error);

  final Object error;
}
