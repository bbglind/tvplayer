import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/errors.dart';
import 'providers.dart';
import 'vod_controller.dart';

/// The Search page's search text, once typing pauses. Kept while switching
/// sections; resets when the provider changes.
final globalQueryProvider = NotifierProvider<GlobalQuery, String>(
  GlobalQuery.new,
);

class GlobalQuery extends Notifier<String> {
  @override
  String build() {
    ref.watch(providerKeyProvider);
    return '';
  }

  void set(String query) => state = query;
}

/// Whether a group's catalogue can be searched yet.
enum SearchGroupStatus { loading, ready, error, unsupported }

/// The results of one kind (channels, movies or series), best first.
@immutable
final class SearchGroup<T> {
  const SearchGroup({
    this.status = SearchGroupStatus.loading,
    this.items = const [],
    this.error,
  });

  final SearchGroupStatus status;
  final List<T> items;

  /// Why the catalogue couldn't be loaded, without URLs or credentials.
  final String? error;
}

/// Results of the Search page for [query].
@immutable
final class GlobalSearchState {
  const GlobalSearchState({
    this.query = '',
    this.live = const SearchGroup(),
    this.movies = const SearchGroup(),
    this.series = const SearchGroup(),
    this.searching = false,
  });

  final String query;
  final SearchGroup<LiveStream> live;
  final SearchGroup<Movie> movies;
  final SearchGroup<Series> series;

  /// Whether newer results are being computed; the groups still hold the
  /// previous ones.
  final bool searching;
}

/// Searches channels, movies and series for [globalQueryProvider].
///
/// Watching it loads the catalogues that aren't loaded yet. Items in
/// hidden categories are left out unless the "Show hidden categories in
/// global search" setting is on. The search runs in a background isolate,
/// on the catalogues' prebuilt search indexes.
final globalSearchProvider =
    NotifierProvider<GlobalSearchController, GlobalSearchState>(
      GlobalSearchController.new,
    );

class GlobalSearchController extends Notifier<GlobalSearchState> {
  int _generation = 0;
  GlobalSearchState? _last;

  @override
  GlobalSearchState build() {
    final query = ref.watch(globalQueryProvider);
    final live = ref.watch(liveCatalogProvider);
    final movies = ref.watch(movieCatalogProvider);
    final series = ref.watch(seriesCatalogProvider);
    final favourites = ref.watch(favouritesProvider);
    final showHidden = ref.watch(
      appSettingsProvider.select(
        (s) => s.value?.showHiddenInGlobalSearch ?? false,
      ),
    );
    final liveCatalog = live.value;
    final liveStatus = switch (live) {
      AsyncData() => SearchGroupStatus.ready,
      AsyncError() when liveCatalog == null => SearchGroupStatus.error,
      _ when liveCatalog != null => SearchGroupStatus.ready,
      _ => SearchGroupStatus.loading,
    };
    final liveError = live is AsyncError && liveCatalog == null
        ? describeRefreshError(live.error!)
        : null;
    final generation = ++_generation;
    final previous = _last;
    // Keep the previous items for the same kind of search while the new
    // ones are computed, so the page doesn't flash empty.
    List<T> keep<T>(List<T>? items) =>
        previous != null && previous.query.isNotEmpty ? items ?? [] : [];
    final pending = GlobalSearchState(
      query: query,
      live: SearchGroup(
        status: liveStatus,
        items: keep(previous?.live.items),
        error: liveError,
      ),
      movies: _group(movies, keep(previous?.movies.items)),
      series: _group(series, keep(previous?.series.items)),
      searching: !SearchQuery(query).isEmpty,
    );
    if (SearchQuery(query).isEmpty) {
      final empty = GlobalSearchState(
        query: query,
        live: SearchGroup(status: liveStatus, error: liveError),
        movies: _group(movies, const []),
        series: _group(series, const []),
      );
      _last = empty;
      return empty;
    }
    final hiddenOf = showHidden
        ? (ContentKind _) => const <String>{}
        : favourites.hiddenIds;
    final task = (
      query: query,
      live: liveCatalog?.searchIndex,
      liveWithin: liveCatalog == null
          ? null
          : _liveWithin(liveCatalog, hiddenOf(ContentKind.live)),
      movies: movies.catalog?.searchIndex,
      moviesWithin: switch (movies.catalog) {
        final c? => _vodWithin(
          c,
          hiddenOf(ContentKind.movie),
          (m) => m.categoryId,
        ),
        null => null,
      },
      series: series.catalog?.searchIndex,
      seriesWithin: switch (series.catalog) {
        final c? => _vodWithin(
          c,
          hiddenOf(ContentKind.series),
          (s) => s.categoryId,
        ),
        null => null,
      },
    );
    unawaited(
      _run(
        generation,
        task,
        pending,
        liveCatalog,
        movies.catalog,
        series.catalog,
      ),
    );
    _last = pending;
    return pending;
  }

  static SearchGroup<T> _group<T extends Object>(
    VodState<T> state,
    List<T> items,
  ) => SearchGroup(
    status: !state.supported
        ? SearchGroupStatus.unsupported
        : state.catalog != null
        ? SearchGroupStatus.ready
        : state.error != null
        ? SearchGroupStatus.error
        : SearchGroupStatus.loading,
    items: state.catalog == null ? const [] : items,
    error: state.catalog == null ? state.error : null,
  );

  /// Positions of the real channels outside [hidden] categories.
  static List<int> _liveWithin(LiveCatalog catalog, Set<String> hidden) => [
    for (final (i, c) in catalog.channels.indexed)
      if (!c.isSeparator && !LiveCatalog.isHidden(c, hidden)) i,
  ];

  /// Positions of the items outside [hidden] categories; null for all.
  static List<int>? _vodWithin<T extends Object>(
    VodCatalog<T> catalog,
    Set<String> hidden,
    String? Function(T) categoryOf,
  ) {
    if (hidden.isEmpty) return null;
    return [
      for (final (i, item) in catalog.items.indexed)
        if (!hidden.contains(categoryOf(item))) i,
    ];
  }

  Future<void> _run(
    int generation,
    _SearchTask task,
    GlobalSearchState pending,
    LiveCatalog? live,
    VodCatalog<Movie>? movies,
    VodCatalog<Series>? series,
  ) async {
    final _SearchHits hits;
    try {
      hits = await _searchInBackground(
        ref.read(backgroundRunnerProvider),
        task,
      );
    } catch (e) {
      debugPrint('Search failed (${e.runtimeType})');
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    final done = GlobalSearchState(
      query: pending.query,
      live: SearchGroup(
        status: pending.live.status,
        error: pending.live.error,
        items: [
          if (live != null)
            for (final i in hits.live) live.channels[i],
        ],
      ),
      movies: SearchGroup(
        status: pending.movies.status,
        error: pending.movies.error,
        items: [
          if (movies != null)
            for (final i in hits.movies) movies.items[i],
        ],
      ),
      series: SearchGroup(
        status: pending.series.status,
        error: pending.series.error,
        items: [
          if (series != null)
            for (final i in hits.series) series.items[i],
        ],
      ),
    );
    _last = done;
    state = done;
  }
}

typedef _SearchTask = ({
  String query,
  SearchIndex? live,
  List<int>? liveWithin,
  SearchIndex? movies,
  List<int>? moviesWithin,
  SearchIndex? series,
  List<int>? seriesWithin,
});

typedef _SearchHits = ({List<int> live, List<int> movies, List<int> series});

/// Runs [task] with [run]. A top-level function, so the closure sent to
/// the isolate captures only [task].
Future<_SearchHits> _searchInBackground(
  BackgroundRunner run,
  _SearchTask task,
) => run(() => _search(task));

_SearchHits _search(_SearchTask task) {
  final q = SearchQuery(task.query);
  return (
    live: task.live?.ranked(q, within: task.liveWithin) ?? const [],
    movies: task.movies?.ranked(q, within: task.moviesWithin) ?? const [],
    series: task.series?.ranked(q, within: task.seriesWithin) ?? const [],
  );
}
