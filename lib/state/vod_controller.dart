import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/errors.dart';
import 'category_selection.dart';
import 'playlist_refresh.dart';
import 'providers.dart';

/// A movie or series catalogue as shown by the UI.
@immutable
final class VodState<T extends Object> {
  const VodState({
    this.supported = true,
    this.catalog,
    this.loading = false,
    this.error,
  });

  /// False when the provider has no movies or series (M3U playlists).
  final bool supported;

  /// The current catalogue; null until one is cached or downloaded.
  final VodCatalog<T>? catalog;

  /// Whether the cache is being read or the catalogue downloaded.
  final bool loading;

  /// Why the last download failed, if it did. Never contains URLs or
  /// credentials.
  final String? error;

  /// Whether there is no catalogue yet but one will come.
  bool get waiting => supported && catalog == null && error == null;
}

/// Shows the cached catalogue at once, downloads one when there is none,
/// and a fresh one on [refresh] (by hand or by automatic refresh, see
/// `PlaylistRefreshController`). Records each download in
/// [playlistStatusProvider].
abstract class VodController<T extends Object> extends Notifier<VodState<T>> {
  Future<String?>? _refreshing;
  Completer<void> _started = Completer();

  /// What is loaded, for log messages ("movies", "series").
  String get what;

  PlaylistPart get part;

  Future<VodCatalog<T>?> loadCache(String key);

  Future<VodCatalog<T>> download(VodSource source, DateTime now);

  Future<void> saveCache(String key, VodCatalog<T> catalog);

  /// Completes once the cache was read (and a download started when there
  /// was none).
  Future<void> get started => _started.future;

  @override
  VodState<T> build() {
    _started = Completer();
    final source = ref.watch(vodSourceProvider);
    final key = ref.watch(providerKeyProvider);
    if (source == null || key == null) {
      _started.complete();
      return VodState<T>(supported: false);
    }
    unawaited(_start(key));
    return VodState<T>(loading: true);
  }

  Future<void> _start(String key) async {
    final started = _started;
    VodCatalog<T>? cached;
    try {
      cached = await loadCache(key);
    } catch (e) {
      debugPrint('Could not read the $what cache (${e.runtimeType})');
    }
    if (cached != null) await _prepareSearch(cached);
    if (!ref.mounted) return started.complete();
    if (cached == null) {
      // One part at a time, like every other download: after the channels
      // (loaded when the provider is selected, outside the queue), then
      // through the queue. Providers may answer parallel requests with an
      // empty list.
      await ref
          .read(liveCatalogProvider.future)
          .then((_) {}, onError: (Object _) {});
      if (!ref.mounted) return started.complete();
      final download = ref.read(playlistRefreshProvider.notifier).refresh(part);
      started.complete();
      await download;
      return;
    }
    state = VodState<T>(catalog: cached);
    ref.read(playlistStatusProvider.notifier).seed(part, cached.fetchedAt);
    started.complete();
  }

  /// Builds [catalog]'s search index in the background unless it has one.
  Future<void> _prepareSearch(VodCatalog<T> catalog) async {
    if (catalog.hasSearchIndex) return;
    catalog.attachSearchIndex(
      await buildSearchIndex(ref.read(backgroundRunnerProvider), catalog.names),
    );
  }

  /// Downloads a fresh catalogue, keeping the current one until it is
  /// ready, or for good when the download fails. Returns why it failed, or
  /// null. Concurrent calls share one download.
  Future<String?> refresh() =>
      _refreshing ??= _download().whenComplete(() => _refreshing = null);

  Future<String?> _download() async {
    final source = ref.read(vodSourceProvider);
    final key = ref.read(providerKeyProvider);
    if (source == null || key == null) return null;
    final status = ref.read(playlistStatusProvider.notifier);
    final current = state.catalog;
    state = VodState<T>(catalog: current, loading: true);
    try {
      final catalog = await download(source, ref.read(clockProvider));
      checkNotEmpty(
        before: current?.items.length ?? 0,
        after: catalog.items.length,
        categories: catalog.categories.length,
      );
      await _prepareSearch(catalog);
      if (!ref.mounted) return null;
      state = VodState<T>(catalog: catalog);
      status.recordSuccess(part, catalog.fetchedAt);
      try {
        await saveCache(key, catalog);
      } catch (e) {
        debugPrint('Could not save the $what cache (${e.runtimeType})');
      }
      return null;
    } catch (e) {
      final message = describeRefreshError(e);
      // Only the plain description: never the URL or credentials.
      debugPrint('Loading $what failed: $message');
      if (!ref.mounted) return message;
      state = VodState<T>(catalog: state.catalog, error: message);
      status.recordFailure(part, ref.read(clockProvider), message);
      return message;
    }
  }
}

class MovieCatalogController extends VodController<Movie> {
  @override
  String get what => 'movies';

  @override
  PlaylistPart get part => PlaylistPart.movies;

  @override
  Future<VodCatalog<Movie>?> loadCache(String key) =>
      ref.read(vodRepositoryProvider).loadMovies(key);

  @override
  Future<VodCatalog<Movie>> download(VodSource source, DateTime now) =>
      source.loadMovies(now: now);

  @override
  Future<void> saveCache(String key, VodCatalog<Movie> catalog) =>
      ref.read(vodRepositoryProvider).saveMovies(key, catalog);
}

class SeriesCatalogController extends VodController<Series> {
  @override
  String get what => 'series';

  @override
  PlaylistPart get part => PlaylistPart.series;

  @override
  Future<VodCatalog<Series>?> loadCache(String key) =>
      ref.read(vodRepositoryProvider).loadSeries(key);

  @override
  Future<VodCatalog<Series>> download(VodSource source, DateTime now) =>
      source.loadSeries(now: now);

  @override
  Future<void> saveCache(String key, VodCatalog<Series> catalog) =>
      ref.read(vodRepositoryProvider).saveSeries(key, catalog);
}

/// Category, search text, filters and search scope of a movie or series
/// tab.
@immutable
final class VodFilter {
  const VodFilter({
    this.category = const AllCategories(),
    this.query = '',
    this.filters = const VodFilters(),
    this.searchInCategory = false,
  });

  final CategorySelection category;
  final String query;

  /// Year and genre filters.
  final VodFilters filters;

  /// Whether the search is limited to [category] ("Only in …"); otherwise
  /// it searches the whole section.
  final bool searchInCategory;

  VodFilter copyWith({
    CategorySelection? category,
    String? query,
    VodFilters? filters,
    bool? searchInCategory,
  }) => VodFilter(
    category: category ?? this.category,
    query: query ?? this.query,
    filters: filters ?? this.filters,
    searchInCategory: searchInCategory ?? this.searchInCategory,
  );

  @override
  bool operator ==(Object other) =>
      other is VodFilter &&
      other.category == category &&
      other.query == query &&
      other.filters == filters &&
      other.searchInCategory == searchInCategory;

  @override
  int get hashCode => Object.hash(category, query, filters, searchInCategory);
}

/// [VodFilter] of one tab, kept while switching tabs. Resets when the
/// provider changes.
class VodFilterNotifier extends Notifier<VodFilter> {
  @override
  VodFilter build() {
    ref.watch(providerKeyProvider);
    return const VodFilter();
  }

  void selectCategory(CategorySelection category) =>
      state = state.copyWith(category: category);

  void setQuery(String query) => state = state.copyWith(query: query);

  /// Selects [category] with no search or filters.
  void show(CategorySelection category) =>
      state = VodFilter(category: category);

  void setFilters(VodFilters filters) =>
      state = state.copyWith(filters: filters);

  void setSearchInCategory(bool value) =>
      state = state.copyWith(searchInCategory: value);
}
