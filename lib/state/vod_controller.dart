import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/errors.dart';
import 'category_selection.dart';
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
}

/// Shows the cached catalogue at once, then downloads a fresh one in the
/// background when it is older than [maxAge] (checked every
/// [checkInterval]) or on [refresh].
abstract class VodController<T extends Object> extends Notifier<VodState<T>> {
  static const maxAge = Duration(hours: 12);
  static const checkInterval = Duration(hours: 1);

  Future<void>? _refreshing;

  /// What is loaded, for log messages ("movies", "series").
  String get what;

  Future<VodCatalog<T>?> loadCache(String key);

  Future<VodCatalog<T>> download(VodSource source, DateTime now);

  Future<void> saveCache(String key, VodCatalog<T> catalog);

  @override
  VodState<T> build() {
    final source = ref.watch(vodSourceProvider);
    final key = ref.watch(providerKeyProvider);
    if (source == null || key == null) return VodState<T>(supported: false);
    final timer = Timer.periodic(checkInterval, (_) => _refreshIfStale());
    ref.onDispose(timer.cancel);
    unawaited(_start(key));
    return VodState<T>(loading: true);
  }

  Future<void> _start(String key) async {
    VodCatalog<T>? cached;
    try {
      cached = await loadCache(key);
    } catch (e) {
      debugPrint('Could not read the $what cache (${e.runtimeType})');
    }
    if (!ref.mounted) return;
    if (cached != null) state = VodState<T>(catalog: cached);
    await _refreshIfStale();
  }

  Future<void> _refreshIfStale() async {
    final catalog = state.catalog;
    final now = ref.read(clockProvider);
    if (catalog != null && now.difference(catalog.fetchedAt) < maxAge) return;
    await refresh();
  }

  /// Downloads a fresh catalogue, keeping the current one until it is
  /// ready. Concurrent calls share one download.
  Future<void> refresh() =>
      _refreshing ??= _download().whenComplete(() => _refreshing = null);

  Future<void> _download() async {
    final source = ref.read(vodSourceProvider);
    final key = ref.read(providerKeyProvider);
    if (source == null || key == null) return;
    state = VodState<T>(catalog: state.catalog, loading: true);
    try {
      final catalog = await download(source, ref.read(clockProvider));
      if (!ref.mounted) return;
      state = VodState<T>(catalog: catalog);
      try {
        await saveCache(key, catalog);
      } catch (e) {
        debugPrint('Could not save the $what cache (${e.runtimeType})');
      }
    } catch (e) {
      if (!ref.mounted) return;
      final message = describeProviderError(e);
      // Only the redacted description: never the URL or credentials.
      debugPrint('Loading $what failed: $message');
      state = VodState<T>(catalog: state.catalog, error: message);
    }
  }
}

class MovieCatalogController extends VodController<Movie> {
  @override
  String get what => 'movies';

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
  Future<VodCatalog<Series>?> loadCache(String key) =>
      ref.read(vodRepositoryProvider).loadSeries(key);

  @override
  Future<VodCatalog<Series>> download(VodSource source, DateTime now) =>
      source.loadSeries(now: now);

  @override
  Future<void> saveCache(String key, VodCatalog<Series> catalog) =>
      ref.read(vodRepositoryProvider).saveSeries(key, catalog);
}

/// Category and search text of a movie or series tab.
@immutable
final class VodFilter {
  const VodFilter({this.category = const AllCategories(), this.query = ''});

  final CategorySelection category;
  final String query;
}

/// [VodFilter] of one tab. Resets when the provider changes.
class VodFilterNotifier extends Notifier<VodFilter> {
  @override
  VodFilter build() {
    ref.watch(providerKeyProvider);
    return const VodFilter();
  }

  void selectCategory(CategorySelection category) =>
      state = VodFilter(category: category, query: state.query);

  void setQuery(String query) =>
      state = VodFilter(category: state.category, query: query);
}
