import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/epg_repository.dart';
import 'package:tvplayer/data/poster_cache.dart';
import 'package:tvplayer/data/provider_storage.dart';
import 'package:tvplayer/data/vod_repository.dart';
import 'package:tvplayer/state/playlist_refresh.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/player/player_hint.dart';
import 'package:tvplayer/ui/shell/snack_bar_dismisser.dart';
import 'package:tvplayer/ui/theme/app_theme.dart';
import 'package:tvplayer/ui/theme/input_mode.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// In-memory [ProviderStorage]. Set [failure] to simulate an unavailable
/// keyring.
class FakeProviderStorage implements ProviderStorage {
  FakeProviderStorage([this.saved]);

  ProviderConfig? saved;
  ProviderStorageException? failure;
  int saves = 0;

  @override
  Future<ProviderConfig?> load() async {
    if (failure case final f?) throw f;
    return saved;
  }

  @override
  Future<void> save(ProviderConfig config) async {
    if (failure case final f?) throw f;
    saves++;
    saved = config;
  }

  @override
  Future<void> delete() async {
    if (failure case final f?) throw f;
    saved = null;
  }
}

/// [LiveSource] serving a fixed catalog. Fails the first [failTimes] loads.
/// Has a guide only when [hasGuide] is set; [downloadGuide] writes
/// [guideXml].
class FakeLiveSource implements LiveSource {
  FakeLiveSource(
    this.catalog, {
    this.failTimes = 0,
    this.hasGuide = false,
    this.guideXml = '<tv></tv>',
  });

  final LiveCatalog catalog;
  String guideXml;

  @override
  bool hasGuide;

  @override
  Future<void> downloadGuide(File target) => target.writeAsString(guideXml);

  int failTimes;
  int loads = 0;
  Completer<void>? gate;

  @override
  Future<LiveCatalog> load() async {
    loads++;
    if (gate case final g?) await g.future;
    if (failTimes > 0) {
      failTimes--;
      throw const XtreamException(
        'Request timed out (get_live_streams)',
        kind: ProviderFailure.timeout,
      );
    }
    return catalog;
  }

  @override
  Uri streamUrl(LiveStream stream) =>
      Uri.parse('http://192.0.2.1/live/user/pass/${stream.id}.ts');

  @override
  Uri? replayUrl(LiveStream stream, TimeshiftStart start, int minutes) =>
      Uri.parse(
        'http://192.0.2.1/timeshift/user/pass/$minutes/${start.text}/'
        '${stream.id}.ts',
      );

  /// Past listings by stream id, served by [archiveListings].
  final archive = <String, List<EpgProgram>>{};

  /// The stream ids [archiveListings] was asked for, in order.
  final archiveRequests = <String>[];

  /// Most [archiveListings] requests that were running at once.
  int maxArchiveInFlight = 0;
  int _archiveInFlight = 0;

  /// Holds [archiveListings] requests until completed.
  Completer<void>? archiveGate;

  /// [archiveListings] fails while set.
  bool failArchive = false;

  @override
  Future<List<EpgProgram>> archiveListings(LiveStream stream) async {
    archiveRequests.add(stream.id);
    _archiveInFlight++;
    if (_archiveInFlight > maxArchiveInFlight) {
      maxArchiveInFlight = _archiveInFlight;
    }
    try {
      if (archiveGate case final g?) await g.future;
      if (failArchive) {
        throw const XtreamException(
          'Request timed out (get_simple_data_table)',
          kind: ProviderFailure.timeout,
        );
      }
      return archive[stream.id] ?? const [];
    } finally {
      _archiveInFlight--;
    }
  }

  String? serverZone = 'Europe/Stockholm';

  @override
  Future<String?> serverTimeZone() async => serverZone;

  @override
  void close() {}
}

/// In-memory [PlaylistStatusStore].
class MemoryPlaylistStatusStore implements PlaylistStatusStore {
  MemoryPlaylistStatusStore([this.status = PlaylistStatus.empty]);

  PlaylistStatus status;
  int saves = 0;

  @override
  Future<PlaylistStatus> load() async => status;

  @override
  Future<void> save(PlaylistStatus status) async {
    saves++;
    this.status = status;
  }
}

/// In-memory [SettingsStorage].
class FakeSettingsStorage implements SettingsStorage {
  FakeSettingsStorage([this.saved = const AppSettings()]);

  AppSettings saved;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

/// [EpgRepository] with an in-memory cache. [refresh] returns [next] (or
/// throws [failure]) after [gate] completes, if set.
class FakeEpgRepository implements EpgRepository {
  FakeEpgRepository({this.cached, this.next, this.failure});

  EpgGuide? cached;
  EpgGuide? next;
  Object? failure;
  Completer<void>? gate;
  int refreshes = 0;
  int clears = 0;
  List<LiveStream>? lastChannels;

  @override
  Future<EpgGuide?> loadCache() async => cached;

  @override
  Future<EpgGuide> refresh(
    LiveSource source,
    List<LiveStream> channels, {
    required DateTime now,
    required DateTime keepFrom,
    bool rejectEmpty = false,
  }) async {
    refreshes++;
    lastChannels = channels;
    if (gate case final g?) await g.future;
    if (failure case final f?) throw f;
    final guide = next ?? EpgGuide.empty(fetchedAt: now);
    cached = guide;
    return guide;
  }

  @override
  Future<void> clear() async {
    clears++;
    cached = null;
  }
}

/// A [Clock] that stays at [time] (UTC).
class FixedClock extends Clock {
  FixedClock(this.time);

  final DateTime time;

  @override
  DateTime build() => time;

  void set(DateTime value) => state = value;
}

/// In-memory [VodRepository].
class FakeVodRepository implements VodRepository {
  final movies = <String, VodCatalog<Movie>>{};
  final series = <String, VodCatalog<Series>>{};
  final cleared = <String>[];

  @override
  Future<VodCatalog<Movie>?> loadMovies(String key) async => movies[key];

  @override
  Future<VodCatalog<Series>?> loadSeries(String key) async => series[key];

  @override
  Future<void> saveMovies(String key, VodCatalog<Movie> catalog) async =>
      movies[key] = catalog;

  @override
  Future<void> saveSeries(String key, VodCatalog<Series> catalog) async =>
      series[key] = catalog;

  @override
  Future<void> clear(String key) async {
    cleared.add(key);
    movies.remove(key);
    series.remove(key);
  }
}

/// In-memory [WatchStore].
class MemoryWatchStore implements WatchStore {
  MemoryWatchStore([this.data = WatchData.empty]);

  WatchData data;
  int saves = 0;

  @override
  Future<WatchData> load() async => data;

  @override
  Future<void> save(WatchData data) async {
    saves++;
    this.data = data;
  }
}

/// In-memory [FavouritesStore].
class MemoryFavouritesStore implements FavouritesStore {
  MemoryFavouritesStore([FavouritesData? data])
    : data = data ?? FavouritesData.empty;

  FavouritesData data;
  int saves = 0;

  @override
  Future<FavouritesData> load() async => data;

  @override
  Future<void> save(FavouritesData data) async {
    saves++;
    this.data = data;
  }
}

/// [PosterLoader] that never has an image, so tests do no network or disk
/// access; [requests] records what was asked for.
class FakePosterLoader implements PosterLoader {
  final requests = <String>[];

  @override
  Future<Uint8List> load(String url) async {
    requests.add(url);
    throw const PosterException('No images in tests');
  }
}

/// [VodSource] serving fixed catalogues and series info.
class FakeVodSource implements VodSource {
  FakeVodSource({
    VodCatalog<Movie>? movies,
    VodCatalog<Series>? series,
    this.seriesInfos = const {},
    this.movieDetails = const {},
  }) : movies = movies ?? syntheticMovies(count: 0),
       series = series ?? syntheticSeries(count: 0);

  VodCatalog<Movie> movies;
  VodCatalog<Series> series;
  Map<int, SeriesInfo> seriesInfos;
  Map<int, Movie> movieDetails;
  int movieLoads = 0;
  int seriesLoads = 0;
  Object? failure;

  @override
  Future<VodCatalog<Movie>> loadMovies({required DateTime now}) async {
    movieLoads++;
    if (failure case final f?) throw f;
    return VodCatalog.movies(
      categories: movies.categories,
      items: movies.items,
      fetchedAt: now,
    );
  }

  @override
  Future<VodCatalog<Series>> loadSeries({required DateTime now}) async {
    seriesLoads++;
    if (failure case final f?) throw f;
    return VodCatalog.series(
      categories: series.categories,
      items: series.items,
      fetchedAt: now,
    );
  }

  @override
  Future<Movie> movieInfo(Movie movie) async =>
      movieDetails[movie.streamId] ?? movie;

  @override
  Future<SeriesInfo> seriesInfo(int seriesId) async {
    final info = seriesInfos[seriesId];
    if (info == null) throw XtreamException('Series $seriesId not found');
    return info;
  }

  @override
  Uri movieUrl(Movie movie) =>
      Uri.parse('http://192.0.2.1/movie/user/pass/${movie.streamId}.mkv');

  @override
  Uri episodeUrl(Episode episode) =>
      Uri.parse('http://192.0.2.1/series/user/pass/${episode.id}.mkv');

  @override
  void close() {}
}

/// [count] synthetic movies spread over [categories] categories.
VodCatalog<Movie> syntheticMovies({
  int count = 20000,
  int categories = 5,
  DateTime? fetchedAt,
}) => VodCatalog.movies(
  categories: [
    for (var c = 0; c < categories; c++)
      Category(id: 'm$c', name: 'Movie category $c'),
  ],
  items: [
    for (var i = 0; i < count; i++)
      Movie(
        streamId: i,
        name: 'Movie ${i.toString().padLeft(5, '0')}',
        categoryId: 'm${i % categories}',
        posterUrl: 'http://example.com/posters/$i.jpg',
      ),
  ],
  fetchedAt: fetchedAt ?? DateTime.utc(2026),
);

/// [count] synthetic series spread over [categories] categories.
VodCatalog<Series> syntheticSeries({
  int count = 1000,
  int categories = 3,
  DateTime? fetchedAt,
}) => VodCatalog.series(
  categories: [
    for (var c = 0; c < categories; c++)
      Category(id: 's$c', name: 'Series category $c'),
  ],
  items: [
    for (var i = 0; i < count; i++)
      Series(
        seriesId: i,
        name: 'Series ${i.toString().padLeft(4, '0')}',
        categoryId: 's${i % categories}',
      ),
  ],
  fetchedAt: fetchedAt ?? DateTime.utc(2026),
);

/// [count] synthetic channels spread over [categories] categories.
LiveCatalog syntheticCatalog({int count = 5000, int categories = 10}) {
  return LiveCatalog(
    categories: [
      for (var c = 0; c < categories; c++)
        Category(id: 'c$c', name: 'Category $c'),
    ],
    channels: [
      for (var i = 0; i < count; i++)
        LiveStream(
          id: '$i',
          name: 'Channel ${i.toString().padLeft(4, '0')}',
          categoryIds: ['c${i % categories}'],
          number: i + 1,
        ),
    ],
  );
}

/// JSON response as UTF-8 bytes.
http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

/// Synthetic Xtream login response for an active account.
const activeAccountJson = {
  'user_info': {
    'auth': 1,
    'status': 'Active',
    'exp_date': '1893456000',
    'max_connections': '1',
    'active_cons': '0',
  },
  'server_info': {'timezone': 'UTC'},
};

/// Wraps [child] in a ProviderScope (no automatic retries) and MaterialApp
/// with the app's [InputModeScope].
///
/// The provider storage (empty unless [providerStorage] is given),
/// settings, the guide and catalogue caches, the watch history, favourites,
/// posters and the device time zone (`Europe/Stockholm`) are always faked;
/// pass [settings], [epg], [vod], [watch], [favourites] or [playlistStatus]
/// to inspect them. [now] fixes the
/// clock. Searches report at once unless [searchDebounce] is given.
Widget testApp({
  required List<Override> overrides,
  required Widget child,
  ProviderStorage? providerStorage,
  SettingsStorage? settings,
  EpgRepository? epg,
  VodRepository? vod,
  WatchStore? watch,
  FavouritesStore? favourites,
  PlaylistStatusStore? playlistStatus,
  DateTime? now,
  Duration searchDebounce = Duration.zero,
}) {
  final watchStore = watch ?? MemoryWatchStore();
  final favouritesStore = favourites ?? MemoryFavouritesStore();
  final statusStore = playlistStatus ?? MemoryPlaylistStatusStore();
  return ProviderScope(
    overrides: [
      providerStorageProvider.overrideWithValue(
        providerStorage ?? FakeProviderStorage(),
      ),
      settingsStorageProvider.overrideWithValue(
        settings ?? FakeSettingsStorage(),
      ),
      epgRepositoryProvider.overrideWithValue(epg ?? FakeEpgRepository()),
      vodRepositoryProvider.overrideWithValue(vod ?? FakeVodRepository()),
      watchStoreProvider.overrideWithValue((_) => watchStore),
      favouritesStoreProvider.overrideWithValue((_) => favouritesStore),
      playlistStatusStoreProvider.overrideWithValue((_) => statusStore),
      posterLoaderProvider.overrideWithValue(FakePosterLoader()),
      // Background isolates don't finish inside fake-async widget tests.
      backgroundRunnerProvider.overrideWithValue(<R>(task) async => task()),
      searchDebounceProvider.overrideWithValue(searchDebounce),
      deviceTimeZoneProvider.overrideWithValue('Europe/Stockholm'),
      if (now != null) clockProvider.overrideWith(() => FixedClock(now)),
      ...overrides,
    ],
    retry: (_, _) => null,
    child: MaterialApp(
      theme: AppTheme.dark(),
      navigatorObservers: [SnackBarDismisser()],
      builder: (context, child) => InputModeScope(child: child!),
      home: child,
    ),
  );
}

/// Shows [child] with automatic playlist refresh running, as in the app
/// shell.
class AutoRefreshHost extends ConsumerWidget {
  const AutoRefreshHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(playlistRefreshProvider, (_, _) {});
    return child;
  }
}

/// Finds the player control whose [PlayerTooltip] says [message].
Finder findPlayerTooltip(Pattern message) => find.byWidgetPredicate(
  (w) =>
      w is PlayerTooltip &&
      (message is RegExp ? message.hasMatch(w.message) : w.message == message),
);
