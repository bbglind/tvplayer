import '../metadata/metadata_source.dart';
import 'tmdb_images.dart';
import 'tmdb_models.dart';

/// Poster addresses to try in order: the provider's first, TMDB's where it
/// has none, or the other way round with [preferTmdb]. Empty when neither
/// has one.
List<String> posterChoices({
  required String? provider,
  required String? tmdbPath,
  required bool preferTmdb,
  TmdbImageSize size = TmdbImageSize.w342,
}) {
  final tmdb = tmdbImageRefOrNull(tmdbPath, size);
  final ordered = preferTmdb ? [tmdb, provider] : [provider, tmdb];
  return [
    for (final url in ordered)
      if (url != null && url.isNotEmpty) url,
  ];
}

/// The backdrop to show: TMDB's first, else the provider's first one.
String? backdropChoice({
  required String? tmdbPath,
  required Iterable<String> provider,
  bool compact = false,
}) =>
    tmdbImageRefOrNull(
      tmdbPath,
      compact ? TmdbImageSize.w780 : TmdbImageSize.w1280,
    ) ??
    provider.firstOrNull;

/// What a movie's or series' detail page shows: the provider's metadata
/// with gaps filled from TMDB. Text never replaces what the provider has;
/// images follow [posterChoices] and [backdropChoice].
final class DetailsView {
  const DetailsView({
    this.title,
    this.plot,
    this.year,
    this.genre,
    this.rating,
    this.runtime,
    this.cast,
    this.director,
    this.posterUrls = const [],
    this.backdropUrl,
    this.people = const [],
    this.recommendations = const [],
  });

  /// [provider] metadata (null while loading or when it failed), the list
  /// entry's [listPoster] and [listBackdrops], and [tmdb] when known.
  factory DetailsView.combine({
    MediaMetadata? provider,
    String? listPoster,
    Iterable<String> listBackdrops = const [],
    int? listYear,
    double? listRating,
    TmdbTitle? tmdb,
    bool preferTmdbPosters = false,
    bool compact = false,
  }) {
    final rating = switch (provider?.rating ?? listRating) {
      final r? when r > 0 => r,
      _ => tmdb?.vote,
    };
    final providerBackdrops = provider?.backdropUrls ?? const [];
    return DetailsView(
      title: provider?.title,
      plot: provider?.plot ?? tmdb?.overview,
      year: provider?.year ?? listYear ?? tmdb?.year,
      genre: provider?.genre ?? tmdb?.genreText,
      rating: rating,
      runtime:
          provider?.duration ??
          switch (tmdb?.runtimeMinutes) {
            final m? => Duration(minutes: m),
            null => null,
          },
      cast: provider?.cast,
      director: provider?.director,
      posterUrls: posterChoices(
        provider: provider?.posterUrl ?? listPoster,
        tmdbPath: tmdb?.posterPath,
        preferTmdb: preferTmdbPosters,
        size: TmdbImageSize.w500,
      ),
      backdropUrl: backdropChoice(
        tmdbPath: tmdb?.backdropPath,
        provider: providerBackdrops.isNotEmpty
            ? providerBackdrops
            : listBackdrops,
        compact: compact,
      ),
      people: tmdb?.cast ?? const [],
      recommendations: tmdb?.recommendations ?? const [],
    );
  }

  final String? title;
  final String? plot;
  final int? year;
  final String? genre;

  /// Out of 10.
  final double? rating;
  final Duration? runtime;

  /// The provider's cast and director texts.
  final String? cast;
  final String? director;

  /// Poster addresses to try in order.
  final List<String> posterUrls;
  final String? backdropUrl;

  /// TMDB's cast, for the Cast row.
  final List<TmdbCast> people;
  final List<TmdbKey> recommendations;
}

/// [provider]'s episode metadata with gaps filled from TMDB's [tmdb]
/// episode: the description, the still and the title.
EpisodeMetadata? withTmdbEpisode(EpisodeMetadata? provider, TmdbEpisode? tmdb) {
  if (tmdb == null) return provider;
  final fromTmdb = EpisodeMetadata(
    title: tmdb.name,
    plot: tmdb.overview,
    stillUrl: tmdbImageRefOrNull(tmdb.stillPath, TmdbImageSize.w300),
    airDate: tmdb.airDate,
    duration: switch (tmdb.runtimeMinutes) {
      final m? when m > 0 => Duration(minutes: m),
      _ => null,
    },
  );
  return provider?.mergedWith(fromTmdb) ?? fromTmdb;
}
