import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/app_settings.dart';
import '../data/poster_cache.dart';
import '../data/service_credentials.dart';
import 'playlist_refresh.dart';
import 'providers.dart';
import 'variants.dart';

/// Keys of TMDB and the other metadata services. Overridden in tests.
final serviceCredentialsProvider = Provider<ServiceCredentials>(
  (ref) => SecureServiceCredentials(android: ref.watch(isAndroidProvider)),
);

/// The saved TMDB key; null when none is saved.
final tmdbCredentialProvider =
    AsyncNotifierProvider<TmdbCredentialNotifier, TmdbCredential?>(
      TmdbCredentialNotifier.new,
    );

class TmdbCredentialNotifier extends AsyncNotifier<TmdbCredential?> {
  @override
  Future<TmdbCredential?> build() async {
    final raw = await ref
        .watch(serviceCredentialsProvider)
        .read(MetadataService.tmdb);
    return raw == null ? null : TmdbCredential.parse(raw);
  }

  /// Saves the key in [text]. Throws [FormatException] when it doesn't look
  /// like a TMDB key, or ProviderStorageException.
  Future<void> save(String text) async {
    final credential = TmdbCredential.parse(text);
    if (credential == null) {
      throw const FormatException(
        "That doesn't look like a TMDB API Read Access Token or API Key.",
      );
    }
    await ref
        .read(serviceCredentialsProvider)
        .write(MetadataService.tmdb, credential.value);
    state = AsyncData(credential);
  }

  Future<void> remove() async {
    await ref.read(serviceCredentialsProvider).delete(MetadataService.tmdb);
    state = const AsyncData(null);
  }
}

/// Checks [credential] with TMDB: null when it works, else what failed.
typedef TmdbConnectionTester = Future<TmdbFailure?> Function(
  TmdbCredential credential,
);

/// Overridden in tests.
final tmdbConnectionTesterProvider = Provider<TmdbConnectionTester>((ref) {
  final client = ref.watch(httpClientProvider);
  return (credential) async {
    try {
      await TmdbClient(
        client,
        credential,
        maxRetries: 0,
        maxRateLimitRetries: 0,
      ).testConnection();
      return null;
    } on TmdbException catch (e) {
      return e.failure;
    }
  };
});

/// The result of "Test connection" in words.
String describeTmdbTest(TmdbFailure? failure) => switch (failure) {
  null => 'Connected to TMDB.',
  TmdbFailure.unauthorized =>
    "TMDB didn't accept this key. Check that you copied all of it.",
  TmdbFailure.network => "Couldn't reach TMDB. Check your internet connection.",
  TmdbFailure.rateLimited ||
  TmdbFailure.server => 'TMDB is busy. Try again in a minute.',
  TmdbFailure.notFound ||
  TmdbFailure.refused => 'TMDB refused the request. Check the key.',
};

/// Starts the [TmdbBackend] for a key.
typedef TmdbBackendFactory = Future<TmdbBackend> Function(
  TmdbCredential credential,
);

/// A [TmdbWorker] with the database in the app support directory (it is
/// kept, not a cache). Overridden in tests.
final tmdbBackendFactoryProvider = Provider<TmdbBackendFactory>(
  (ref) =>
      (credential) async => TmdbWorker.spawn(
        databasePath:
            '${(await getApplicationSupportDirectory()).path}/'
            'tmdb.sqlite',
        credential: credential,
      ),
);

/// Whether TMDB is turned on in the settings.
final tmdbEnabledProvider = Provider<bool>(
  (ref) => ref.watch(
    appSettingsProvider.select((s) => s.value?.tmdbEnabled ?? false),
  ),
);

/// Whether TMDB posters come first (TMDB on and "Prefer TMDB posters").
final tmdbPreferPostersProvider = Provider<bool>(
  (ref) =>
      ref.watch(tmdbEnabledProvider) &&
      ref.watch(
        appSettingsProvider.select((s) => s.value?.tmdbPreferPosters ?? false),
      ),
);

/// The running backend while TMDB is on and a key is saved; null otherwise,
/// and then the app works without TMDB.
final tmdbBackendProvider = FutureProvider<TmdbBackend?>((ref) async {
  if (!ref.watch(tmdbEnabledProvider)) return null;
  final credential = ref.watch(tmdbCredentialProvider).value;
  if (credential == null) return null;
  final factory = ref.read(tmdbBackendFactoryProvider);
  final backend = await factory(credential);
  if (!ref.mounted) {
    await backend.close();
    return null;
  }
  ref.onDispose(() => unawaited(backend.close()));
  return backend;
});

/// The catalogues' titles for the background fetch, built in the
/// background.
final tmdbWorkProvider = FutureProvider<TmdbWork>((ref) async {
  final movies = ref.watch(movieCatalogProvider.select((s) => s.catalog));
  final series = ref.watch(seriesCatalogProvider.select((s) => s.catalog));
  final tags = ref.watch(providerTagsProvider);
  if (movies == null && series == null) return TmdbWork.empty;
  final movieItems = movies?.items ?? const <Movie>[];
  final seriesItems = series?.items ?? const <Series>[];
  return ref.read(backgroundRunnerProvider)(
    () => TmdbWork.of(
      movies: tmdbMovieItems(movieItems),
      series: tmdbSeriesItems(seriesItems),
      tags: tags,
    ),
  );
});

/// How far the background fetch got; null while TMDB is off or before the
/// first report. Kept alive by the app shell, so the fetch runs app-wide.
///
/// It is paused while something plays and when the user paused it, and is
/// given the catalogues' titles whenever they change (a playlist refresh),
/// so only new ones are fetched.
final tmdbSyncProvider = NotifierProvider<TmdbSyncController, TmdbProgress?>(
  TmdbSyncController.new,
);

class TmdbSyncController extends Notifier<TmdbProgress?> {
  @override
  TmdbProgress? build() {
    final backend = ref.watch(tmdbBackendProvider).value;
    if (backend == null) return null;
    final events = backend.events.listen((e) {
      if (e is TmdbProgressEvent && ref.mounted) state = e.progress;
    });
    ref.onDispose(events.cancel);
    void pause() => unawaited(
      backend.setPause(
        ref.read(appSettingsProvider).value?.tmdbPaused ?? false
            ? TmdbPause.user
            : ref.read(playbackActiveProvider)
            ? TmdbPause.playback
            : null,
      ),
    );
    ref.listen(playbackActiveProvider, (_, _) => pause());
    ref.listen(
      appSettingsProvider.select((s) => s.value?.tmdbPaused ?? false),
      (_, _) => pause(),
    );
    // Before the work, so nothing starts while something plays.
    pause();
    ref.listen(tmdbWorkProvider, (_, work) {
      if (work.value case final w?) {
        unawaited(backend.setWork(w.wanted, w.searches));
      }
    }, fireImmediately: true);
    return null;
  }

  /// Pauses or resumes the background fetch; kept across restarts.
  Future<void> setPaused(bool paused) => ref
      .read(appSettingsProvider.notifier)
      .change((s) => s.copyWith(tmdbPaused: paused));

  /// Gives the backend the titles again, e.g. after matching was allowed
  /// again.
  Future<void> resendWork() async {
    final backend = ref.read(tmdbBackendProvider).value;
    final work = ref.read(tmdbWorkProvider).value;
    if (backend != null && work != null) {
      await backend.setWork(work.wanted, work.searches);
    }
  }
}

/// The posters and backdrops of the stored TMDB titles.
final class TmdbArtworkIndex {
  const TmdbArtworkIndex(this.posters, this.backdrops);

  static const empty = TmdbArtworkIndex({}, {});

  final Map<TmdbKey, String> posters;
  final Map<TmdbKey, String> backdrops;
}

/// [TmdbArtworkIndex] of the store, updated every few seconds while the
/// background fetch adds titles.
final tmdbArtworkProvider =
    NotifierProvider<TmdbArtworkController, TmdbArtworkIndex>(
      TmdbArtworkController.new,
    );

class TmdbArtworkController extends Notifier<TmdbArtworkIndex> {
  /// How often new images are applied, so lists don't rebuild for each.
  static const flushEvery = Duration(seconds: 3);

  final _pending = <TmdbArtwork>[];
  Timer? _flush;

  @override
  TmdbArtworkIndex build() {
    final backend = ref.watch(tmdbBackendProvider).value;
    _pending.clear();
    if (backend == null) return TmdbArtworkIndex.empty;
    final events = backend.events.listen((e) {
      if (e is! TmdbArtworkEvent) return;
      _pending.addAll(e.artwork);
      _flush ??= Timer(flushEvery, _apply);
    });
    ref.onDispose(() {
      events.cancel();
      _flush?.cancel();
      _flush = null;
    });
    unawaited(
      backend.artwork().then((all) {
        if (!ref.mounted) return;
        _pending.insertAll(0, all);
        _apply();
      }, onError: (Object e) => debugPrint('TMDB artwork: ${e.runtimeType}')),
    );
    return TmdbArtworkIndex.empty;
  }

  void _apply() {
    _flush = null;
    if (_pending.isEmpty || !ref.mounted) return;
    final posters = Map.of(state.posters);
    final backdrops = Map.of(state.backdrops);
    for (final a in _pending) {
      if (a.poster case final p?) posters[a.key] = p;
      if (a.backdrop case final b?) backdrops[a.key] = b;
    }
    _pending.clear();
    state = TmdbArtworkIndex(posters, backdrops);
  }
}

/// The genre names of the stored TMDB titles, updated every few seconds
/// while the background fetch adds titles.
final tmdbGenresProvider =
    NotifierProvider<TmdbGenresController, TmdbGenreIndex>(
      TmdbGenresController.new,
    );

class TmdbGenresController extends Notifier<TmdbGenreIndex> {
  /// How often new genres are applied, so lists don't recount for each.
  static const flushEvery = Duration(seconds: 3);

  final _pending = <TmdbKey, List<String>>{};
  Timer? _flush;

  @override
  TmdbGenreIndex build() {
    final backend = ref.watch(tmdbBackendProvider).value;
    _pending.clear();
    if (backend == null) return const {};
    final events = backend.events.listen((e) {
      if (e is! TmdbGenresEvent) return;
      _pending.addAll(e.genres);
      _flush ??= Timer(flushEvery, _apply);
    });
    ref.onDispose(() {
      events.cancel();
      _flush?.cancel();
      _flush = null;
    });
    unawaited(
      backend.genres().then((all) {
        if (!ref.mounted) return;
        // Genres that arrived meanwhile are newer.
        _pending.addAll({...all, ..._pending});
        _apply();
      }, onError: (Object e) => debugPrint('TMDB genres: ${e.runtimeType}')),
    );
    return const {};
  }

  void _apply() {
    _flush = null;
    if (_pending.isEmpty || !ref.mounted) return;
    state = {...state, ..._pending};
    _pending.clear();
  }
}

/// The genres of the Movies filter: TMDB's; null while TMDB is off (the
/// provider sends none).
final movieGenreSourceProvider = Provider<GenreSource<Movie>?>((ref) {
  if (ref.watch(tmdbBackendProvider).value == null) return null;
  return tmdbMovieGenres(
    ref.watch(tmdbLinksProvider),
    ref.watch(tmdbGenresProvider),
  );
});

/// The genres of the Series filter: TMDB's, else the provider's with
/// TMDB's names.
final seriesGenreSourceProvider = Provider<GenreSource<Series>>((ref) {
  if (ref.watch(tmdbBackendProvider).value == null) {
    return providerSeriesGenres;
  }
  return tmdbSeriesGenres(
    ref.watch(tmdbLinksProvider),
    ref.watch(tmdbGenresProvider),
  );
});

/// TMDB's trending list as stored, fetched again at most once a day: only
/// while TMDB is on, its background fetch isn't paused and nothing plays.
/// Checked at start, when playback stops, on Resume and every hour. Kept
/// alive by the app shell. Each decision is logged as one
/// `TMDB trending: …` line (no addresses, keys or titles).
final tmdbTrendingProvider =
    NotifierProvider<TmdbTrendingController, TmdbTrendingList>(
      TmdbTrendingController.new,
    );

class TmdbTrendingController extends Notifier<TmdbTrendingList> {
  static const checkEvery = Duration(hours: 1);

  var _refreshing = false;

  @override
  TmdbTrendingList build() {
    final backend = ref.watch(tmdbBackendProvider).value;
    if (backend == null) {
      // Once the settings are read: these change only then and when TMDB
      // is turned on or off, so it is logged once.
      final loaded = ref.watch(appSettingsProvider.select((s) => s.hasValue));
      if (loaded && !ref.watch(tmdbEnabledProvider)) _log('skipped (off)');
      return TmdbTrendingList.empty;
    }
    ref.listen(playbackActiveProvider, (was, playing) {
      if (was == true && !playing) unawaited(_check());
    });
    ref.listen(
      appSettingsProvider.select((s) => s.value?.tmdbPaused ?? false),
      (_, _) => unawaited(_check()),
    );
    final timer = Timer.periodic(checkEvery, (_) => unawaited(_check()));
    ref.onDispose(timer.cancel);
    unawaited(_load(backend));
    return TmdbTrendingList.empty;
  }

  static void _log(String text) => debugPrint('TMDB trending: $text');

  /// The type and TMDB failure of [e] only: messages may quote requests.
  static String _describe(Object e) => switch (e) {
    TmdbException(:final failure) => 'TmdbException(${failure.name})',
    // From the worker, which sends only the type.
    StateError(:final message) => message,
    _ => '${e.runtimeType}',
  };

  Future<void> _load(TmdbBackend backend) async {
    await _whenLinked();
    if (!ref.mounted) return;
    try {
      final list = await backend.trending();
      if (!ref.mounted) return;
      state = list;
      if (list.titles.isNotEmpty &&
          usableTrending(list, ref.read(clockProvider)).isEmpty) {
        _log('stored list too old, not shown');
      }
    } catch (e) {
      _log('failed (${_describe(e)})');
    }
    await _check();
  }

  /// Waits (at most a minute) until the catalogue items are linked to
  /// TMDB, so the first check can say how many trending titles match.
  Future<void> _whenLinked() async {
    if (!identical(ref.read(tmdbLinksProvider), TmdbLinks.empty)) return;
    final linked = Completer<void>();
    final subscription = ref.listen(tmdbLinksProvider, (_, links) {
      if (!identical(links, TmdbLinks.empty) && !linked.isCompleted) {
        linked.complete();
      }
    });
    await linked.future.timeout(const Duration(minutes: 1), onTimeout: () {});
    subscription.close();
  }

  Future<void> _check() async {
    if (_refreshing || !ref.mounted) return;
    final backend = ref.read(tmdbBackendProvider).value;
    if (backend == null) return;
    final decision = trendingDecision(
      enabled: ref.read(tmdbEnabledProvider),
      paused: ref.read(appSettingsProvider).value?.tmdbPaused ?? false,
      playing: ref.read(playbackActiveProvider),
      fetchedAt: state.fetchedAt,
      now: ref.read(clockProvider),
    );
    if (decision != TrendingDecision.refresh) {
      _log('skipped (${decision.name})');
      return;
    }
    _refreshing = true;
    try {
      final list = await backend.refreshTrending();
      if (!ref.mounted) return;
      state = list;
      final links = ref.read(tmdbLinksProvider);
      final matched = list.titles
          .where((t) => links.itemsOf(t.key).isNotEmpty)
          .length;
      _log('refreshed (${list.titles.length} titles, $matched matched)');
    } catch (e) {
      _log('failed (${_describe(e)})');
    } finally {
      _refreshing = false;
    }
  }
}

/// The stored title search outcomes and the links the user removed.
final class TmdbMatchState {
  const TmdbMatchState(this.matches, this.removed, {this.loaded = true});

  static const empty = TmdbMatchState({}, {}, loaded: false);

  final Map<(TmdbKind, String), TitleMatch> matches;
  final Set<TmdbKey> removed;
  final bool loaded;

  /// Removed matches and links.
  int get removedCount =>
      removed.length +
      matches.values.where((m) => m.outcome == MatchOutcome.removed).length;
}

final tmdbMatchesProvider =
    NotifierProvider<TmdbMatchesController, TmdbMatchState>(
      TmdbMatchesController.new,
    );

class TmdbMatchesController extends Notifier<TmdbMatchState> {
  /// How often title search outcomes of the background fetch are applied.
  static const flushEvery = Duration(seconds: 5);

  Timer? _flush;

  @override
  TmdbMatchState build() {
    final backend = ref.watch(tmdbBackendProvider).value;
    if (backend == null) return TmdbMatchState.empty;
    final events = backend.events.listen((e) {
      if (e is TmdbMatchEvent) _flush ??= Timer(flushEvery, _reload);
    });
    ref.onDispose(() {
      events.cancel();
      _flush?.cancel();
      _flush = null;
    });
    unawaited(_reload());
    return TmdbMatchState.empty;
  }

  Future<void> _reload() async {
    _flush = null;
    final backend = ref.read(tmdbBackendProvider).value;
    if (backend == null) return;
    try {
      final (matches, removed) = (
        await backend.matches(),
        await backend.removedLinks(),
      );
      if (ref.mounted) state = TmdbMatchState(matches, removed);
    } catch (e) {
      debugPrint('TMDB matches: ${e.runtimeType}');
    }
  }

  /// Stops using [link]'s TMDB title for its provider title (and the other
  /// titles sharing the id or title); never matched again until allowed.
  Future<void> remove(TmdbKind kind, TmdbLink link) async {
    final backend = ref.read(tmdbBackendProvider).value;
    if (backend == null) return;
    if (link.titleKey case final key?) {
      await backend.removeMatch(kind, key);
    } else {
      await backend.removeLink(link.key);
    }
    await _reload();
  }

  /// Forgets every removed match and link, and looks them up again.
  Future<void> allowAgain() async {
    final backend = ref.read(tmdbBackendProvider).value;
    if (backend == null) return;
    await backend.allowMatchingAgain();
    await _reload();
    await ref.read(tmdbSyncProvider.notifier).resendWork();
  }
}

/// The TMDB title of each catalogue item, built in the background.
final tmdbLinksProvider = Provider<TmdbLinks>(
  (ref) => ref.watch(_tmdbLinks).value ?? TmdbLinks.empty,
);

final _tmdbLinks = FutureProvider<TmdbLinks>((ref) async {
  if (ref.watch(tmdbBackendProvider).value == null) return TmdbLinks.empty;
  final state = ref.watch(tmdbMatchesProvider);
  final movies = ref.watch(movieCatalogProvider.select((s) => s.catalog));
  final series = ref.watch(seriesCatalogProvider.select((s) => s.catalog));
  final tags = ref.watch(providerTagsProvider);
  if (!state.loaded) return TmdbLinks.empty;
  final movieItems = movies?.items ?? const <Movie>[];
  final seriesItems = series?.items ?? const <Series>[];
  return ref.read(backgroundRunnerProvider)(
    () => TmdbLinks.build(
      movies: tmdbMovieItems(movieItems),
      series: tmdbSeriesItems(seriesItems),
      tags: tags,
      matches: state.matches,
      removed: state.removed,
    ),
  );
});

/// A catalogue item as needed to find its TMDB title.
typedef TmdbItem = ({
  TmdbKind kind,
  int id,
  String name,
  String? tmdbId,
  int? year,
});

TmdbItem movieTmdbItem(Movie m) => (
  kind: TmdbKind.movie,
  id: m.streamId,
  name: m.name,
  tmdbId: m.tmdbId,
  year: m.year,
);

TmdbItem seriesTmdbItem(Series s) => (
  kind: TmdbKind.tv,
  id: s.seriesId,
  name: s.name,
  tmdbId: s.tmdbId,
  year: s.year,
);

/// How [item] is linked to TMDB; searched for at once when it has no TMDB
/// id and hasn't been searched yet. Null when it has no TMDB title, the
/// link was removed or TMDB is off.
final tmdbLinkProvider = FutureProvider.autoDispose.family<TmdbLink?, TmdbItem>(
  (ref, item) async {
    final state = ref.watch(tmdbMatchesProvider);
    final tags = ref.watch(providerTagsProvider);
    final backend = ref.watch(tmdbBackendProvider).value;
    if (backend == null || !state.loaded) return null;
    return findTmdbLink(item, state: state, tags: tags, backend: backend);
  },
);

/// How [item] is linked to TMDB with the stored outcomes [state] (see
/// [tmdbLinkProvider]); searched for at once when needed.
Future<TmdbLink?> findTmdbLink(
  TmdbItem item, {
  required TmdbMatchState state,
  required ProviderTags tags,
  required TmdbBackend backend,
}) async {
  if (TmdbKey.fromProvider(item.kind, item.tmdbId) case final key?) {
    return state.removed.contains(key) ? null : TmdbLink(key);
  }
  final search = TitleSearch.of(item.kind, item.name, tags, year: item.year);
  if (search == null) return null;
  switch (state.matches[(item.kind, search.key)]) {
    case TitleMatch(outcome: MatchOutcome.removed):
      return null;
    case TitleMatch(outcome: MatchOutcome.matched, :final tmdbId?):
      return TmdbLink(TmdbKey(item.kind, tmdbId), titleKey: search.key);
    case _:
  }
  try {
    final key = await backend.resolve(search);
    return key == null ? null : TmdbLink(key, titleKey: search.key);
  } catch (e) {
    debugPrint('TMDB search: ${e.runtimeType}');
    return null;
  }
}

/// TMDB title [key], fetched at once when it isn't stored yet.
final tmdbTitleProvider = FutureProvider.autoDispose
    .family<TmdbTitle?, TmdbKey>((ref, key) async {
      final backend = ref.watch(tmdbBackendProvider).value;
      if (backend == null) return null;
      try {
        return await backend.title(key);
      } catch (e) {
        debugPrint('TMDB title: ${e.runtimeType}');
        return null;
      }
    });

/// The TMDB title of [item] (see [tmdbLinkProvider]).
final tmdbItemTitleProvider = FutureProvider.autoDispose
    .family<TmdbTitle?, TmdbItem>((ref, item) async {
      final link = await ref.watch(tmdbLinkProvider(item).future);
      if (link == null) return null;
      return ref.watch(tmdbTitleProvider(link.key).future);
    });

/// A season of a series.
typedef TmdbSeasonRequest = ({int tvId, int number, bool ongoing});

final tmdbSeasonProvider = FutureProvider.autoDispose
    .family<TmdbSeason?, TmdbSeasonRequest>((ref, request) async {
      final backend = ref.watch(tmdbBackendProvider).value;
      if (backend == null) return null;
      try {
        return await backend.season(
          request.tvId,
          request.number,
          ongoing: request.ongoing,
        );
      } catch (e) {
        debugPrint('TMDB season: ${e.runtimeType}');
        return null;
      }
    });

final tmdbPersonProvider = FutureProvider.autoDispose.family<TmdbPerson?, int>((
  ref,
  id,
) async {
  final backend = ref.watch(tmdbBackendProvider).value;
  if (backend == null) return null;
  try {
    return await backend.person(id);
  } catch (e) {
    debugPrint('TMDB person: ${e.runtimeType}');
    return null;
  }
});

/// TMDB images, cached on disk apart from the provider's, up to the size
/// chosen in the settings. Overridden in tests.
final tmdbImageLoaderProvider = Provider<PosterCache>((ref) {
  final mb = ref.watch(
    appSettingsProvider.select(
      (s) => s.value?.tmdbImageCacheMb ?? AppSettings.defaultTmdbImageCacheMb,
    ),
  );
  return PosterCache(
    client: ref.watch(httpClientProvider),
    directory: () async =>
        Directory('${(await getApplicationCacheDirectory()).path}/tmdb_images'),
    maxBytes: mb * 1000 * 1000,
  );
});

/// The first two of poster addresses, for an image and its fallback.
extension PosterUrls on List<String> {
  String? get primary => firstOrNull;
  String? get fallback => elementAtOrNull(1);
}

/// The poster addresses of [movie] to try in order (see [posterChoices]);
/// [providerPoster] instead of the list entry's, e.g. from the details.
List<String> moviePosterUrls(
  WidgetRef ref,
  Movie movie, {
  String? providerPoster,
  TmdbImageSize size = TmdbImageSize.w342,
}) => posterChoices(
  provider: providerPoster ?? movie.posterUrl,
  tmdbPath: _tmdbPoster(ref, ref.watch(_movieKey(movie.streamId))),
  preferTmdb: ref.watch(tmdbPreferPostersProvider),
  size: size,
);

/// The poster addresses of [series] to try in order.
List<String> seriesPosterUrls(
  WidgetRef ref,
  Series series, {
  String? providerPoster,
  TmdbImageSize size = TmdbImageSize.w342,
}) => posterChoices(
  provider: providerPoster ?? series.coverUrl,
  tmdbPath: _tmdbPoster(ref, ref.watch(_seriesKey(series.seriesId))),
  preferTmdb: ref.watch(tmdbPreferPostersProvider),
  size: size,
);

/// The wide image of [movie] for 16:9 cards (and, [large], the Featured
/// banner): TMDB's backdrop first, then the provider's; null when neither
/// has one.
String? movieBackdropUrl(WidgetRef ref, Movie movie, {bool large = false}) =>
    backdropChoice(
      tmdbPath: _tmdbBackdrop(ref, ref.watch(_movieKey(movie.streamId))),
      provider: movie.backdropUrls,
      compact: !large,
    );

String? seriesBackdropUrl(WidgetRef ref, Series series, {bool large = false}) =>
    backdropChoice(
      tmdbPath: _tmdbBackdrop(ref, ref.watch(_seriesKey(series.seriesId))),
      provider: series.backdropUrls,
      compact: !large,
    );

// Selected per item, so a card only rebuilds when its own image changes.
final _movieKey = Provider.autoDispose.family<TmdbKey?, int>(
  (ref, id) => ref.watch(tmdbLinksProvider.select((l) => l.movie(id)?.key)),
);

final _seriesKey = Provider.autoDispose.family<TmdbKey?, int>(
  (ref, id) => ref.watch(tmdbLinksProvider.select((l) => l.series(id)?.key)),
);

String? _tmdbPoster(WidgetRef ref, TmdbKey? key) => key == null
    ? null
    : ref.watch(tmdbArtworkProvider.select((a) => a.posters[key]));

String? _tmdbBackdrop(WidgetRef ref, TmdbKey? key) => key == null
    ? null
    : ref.watch(tmdbArtworkProvider.select((a) => a.backdrops[key]));

/// The catalogue titles (a [Movie] or a [Series]) of the TMDB titles
/// [keys], in their order: one per TMDB title and per variant group, none
/// from hidden categories (as Other sources).
List<Object> catalogTitles(WidgetRef ref, Iterable<TmdbKey> keys) {
  final favourites = ref.watch(favouritesProvider);
  return catalogTitlesOf(
    keys,
    movies: ref.watch(movieCatalogProvider).catalog,
    series: ref.watch(seriesCatalogProvider).catalog,
    links: ref.watch(tmdbLinksProvider),
    movieGroups: ref.watch(movieVariantsProvider),
    seriesGroups: ref.watch(seriesVariantsProvider),
    hiddenMovies: favourites.hiddenIds(ContentKind.movie),
    hiddenSeries: favourites.hiddenIds(ContentKind.series),
  );
}
