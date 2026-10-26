import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'providers.dart';
import 'variants.dart';
import 'vod_controller.dart';

/// The items of a start page row, and whether more may come (a catalogue
/// is still loading), so the row shows placeholders meanwhile.
@immutable
final class HomeRowItems<T> {
  const HomeRowItems(this.items, {this.loading = false});

  final List<T> items;
  final bool loading;

  /// Whether the row has nothing to show, now or later.
  bool get isEmpty => items.isEmpty && !loading;
}

/// Whether [state] has no catalogue yet but will get one.
bool _waiting(VodState<Object> state) =>
    state.supported && state.catalog == null && state.error == null;

/// "Featured" on the start page ([featuredPicks]).
final featuredProvider = Provider<HomeRowItems<VodPick>>((ref) {
  final movies = ref.watch(movieCatalogProvider);
  final series = ref.watch(seriesCatalogProvider);
  final picks = featuredPicks(
    movies: movies.catalog,
    series: series.catalog,
    favourites: ref.watch(favouritesProvider),
    // Read, not watched: the picks needn't change every clock tick.
    now: ref.read(clockProvider),
  );
  return HomeRowItems(picks, loading: _waiting(movies) || _waiting(series));
});

/// Details of a featured item from the metadata source: genre, runtime,
/// plot, backdrop and the number of seasons. Fetched only for the item on
/// screen and kept for the session; null when unavailable.
final featuredDetailsProvider = FutureProvider.family<MediaMetadata?, VodPick>((
  ref,
  pick,
) async {
  final source = ref.watch(metadataSourceProvider);
  if (source == null) return null;
  try {
    return await switch (pick) {
      MoviePick(:final movie) => source.movie(movie),
      SeriesPick(:final series) => source.series(series),
    };
  } catch (e) {
    // Optional: the banner shows the catalogue's data without it.
    debugPrint('Featured details unavailable (${e.runtimeType})');
    return null;
  }
});

/// "Recently added series", by last update, without hidden categories.
final recentSeriesProvider = Provider<HomeRowItems<Series>>((ref) {
  final state = ref.watch(seriesCatalogProvider);
  final hidden = ref.watch(
    favouritesProvider.select((f) => f.hiddenIds(ContentKind.series)),
  );
  final catalog = state.catalog;
  return HomeRowItems(
    catalog == null ? const [] : recentlyAdded(catalog, hidden: hidden),
    loading: _waiting(state),
  );
});

/// "Recently added movies", without hidden categories.
final recentMoviesProvider = Provider<HomeRowItems<Movie>>((ref) {
  final state = ref.watch(movieCatalogProvider);
  final hidden = ref.watch(
    favouritesProvider.select((f) => f.hiddenIds(ContentKind.movie)),
  );
  final catalog = state.catalog;
  return HomeRowItems(
    catalog == null ? const [] : recentlyAdded(catalog, hidden: hidden),
    loading: _waiting(state),
  );
});

/// A started movie or series on the start page, resolved in its catalogue.
sealed class ContinueItem {
  const ContinueItem();
}

final class ContinueMovieItem extends ContinueItem {
  const ContinueMovieItem(this.movie, this.progress);

  final Movie movie;
  final WatchProgress progress;
}

final class ContinueSeriesItem extends ContinueItem {
  const ContinueSeriesItem(this.series, this.progress, this.episode);

  final Series series;
  final SeriesProgress progress;

  /// Progress of the next episode, when it was started.
  final WatchProgress? episode;
}

/// "Continue watching": movies and series together, most recently watched
/// first, without hidden categories.
final homeContinueProvider = Provider<HomeRowItems<ContinueItem>>((ref) {
  final watch = ref.watch(watchProvider);
  final movies = ref.watch(movieCatalogProvider);
  final series = ref.watch(seriesCatalogProvider);
  final favourites = ref.watch(favouritesProvider);
  final hiddenMovies = favourites.hiddenIds(ContentKind.movie);
  final hiddenSeries = favourites.hiddenIds(ContentKind.series);
  final items = <ContinueItem>[
    for (final entry in continueAll(
      watch,
      movieGroups: ref.watch(movieVariantsProvider).groupOf,
      seriesGroups: ref.watch(seriesVariantsProvider).groupOf,
    ))
      ?switch (entry) {
        ContinueMovie(:final streamId, :final progress) => switch (movies
            .catalog
            ?.byId(streamId)) {
          final m? when !hiddenMovies.contains(m.categoryId) =>
            ContinueMovieItem(m, progress),
          _ => null,
        },
        ContinueSeries(:final seriesId, :final progress) => switch (series
            .catalog
            ?.byId(seriesId)) {
          final s? when !hiddenSeries.contains(s.categoryId) =>
            ContinueSeriesItem(
              s,
              progress,
              nextEpisodeProgress(
                ref.watch(episodeViewProvider(seriesId)),
                progress,
              ),
            ),
          _ => null,
        },
      },
  ];
  return HomeRowItems(items, loading: _waiting(movies) || _waiting(series));
});

/// "Recently viewed channels": the channels the provider still lists,
/// newest first, with when they were watched.
final recentChannelsProvider = Provider<HomeRowItems<(LiveStream, DateTime)>>((
  ref,
) {
  final recent = recentChannels(ref.watch(watchProvider));
  if (recent.isEmpty) return const HomeRowItems([]);
  final catalog = ref.watch(liveCatalogProvider);
  final c = catalog.value;
  if (c == null) return HomeRowItems(const [], loading: catalog.isLoading);
  return HomeRowItems([
    for (final (id, time) in recent)
      if (c.byStableId(id) case final channel?) (channel, time),
  ]);
});
