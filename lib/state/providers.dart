import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/app_settings.dart';
import '../data/archive_epg_repository.dart';
import '../data/connection_tester.dart';
import '../data/device_time_zone.dart';
import '../data/epg_repository.dart';
import '../data/errors.dart';
import '../data/poster_cache.dart';
import '../data/provider_storage.dart';
import '../data/vod_repository.dart';
import '../player/mpv/external_mpv_player.dart';
import '../player/mpv/video_embed.dart';
import 'category_selection.dart';
import 'favourites_controller.dart';
import 'guide_controller.dart';
import 'playlist_refresh.dart';
import 'vod_controller.dart';
import 'watch_controller.dart';

/// Runs a task in a background isolate, so heavy work (building search
/// indexes, searching every catalogue) doesn't freeze the UI. The task
/// must not capture widgets, refs or other unsendable objects. Tests
/// replace it with one running the task directly.
typedef BackgroundRunner = Future<R> Function<R>(FutureOr<R> Function() task);

final backgroundRunnerProvider = Provider<BackgroundRunner>(
  (ref) => Isolate.run,
);

/// A [SearchIndex] of [names], built with [run].
Future<SearchIndex> buildSearchIndex(
  BackgroundRunner run,
  List<String> names,
) => run(() => SearchIndex(names));

/// How long search fields wait after the last key press before searching.
/// Zero in tests.
final searchDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 200),
);

/// Shared HTTP client. Overridden with a mock in tests.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Where the provider config is persisted. Overridden in tests.
final providerStorageProvider = Provider<ProviderStorage>(
  (ref) => SecureProviderStorage(),
);

final connectionTesterProvider = Provider<ConnectionTester>(
  (ref) => ConnectionTester(ref.watch(httpClientProvider)),
);

/// The saved provider; null when none is configured. Errors are
/// [ProviderStorageException]s (keyring unavailable).
final savedProviderProvider =
    AsyncNotifierProvider<SavedProviderNotifier, ProviderConfig?>(
      SavedProviderNotifier.new,
    );

class SavedProviderNotifier extends AsyncNotifier<ProviderConfig?> {
  @override
  Future<ProviderConfig?> build() => ref.watch(providerStorageProvider).load();

  /// Persists [config] and makes it the active provider. Throws
  /// [ProviderStorageException] without changing the current state.
  Future<void> save(ProviderConfig config) async {
    await ref.read(providerStorageProvider).save(config);
    final previous = state.value;
    if (previous == null ||
        encodeProviderConfig(previous) != encodeProviderConfig(config)) {
      await _clearCaches(previous);
    }
    state = AsyncData(config);
  }

  /// Forgets the saved provider. Throws [ProviderStorageException].
  Future<void> remove() async {
    await ref.read(providerStorageProvider).delete();
    await _clearCaches(state.value);
    state = const AsyncData(null);
  }

  /// The cached guide and catalogues belong to the old provider. Its watch
  /// history is kept, in case it comes back.
  Future<void> _clearCaches(ProviderConfig? previous) async {
    try {
      await ref.read(epgRepositoryProvider).clear();
    } catch (e) {
      debugPrint('Could not clear the guide cache (${e.runtimeType})');
    }
    if (previous == null) return;
    try {
      await ref.read(vodRepositoryProvider).clear(providerKey(previous));
    } catch (e) {
      debugPrint('Could not clear the catalogue cache (${e.runtimeType})');
    }
    try {
      await ref.read(archiveEpgRepositoryProvider).clear(providerKey(previous));
    } catch (e) {
      debugPrint('Could not clear the past programmes (${e.runtimeType})');
    }
  }
}

/// Live TV source for the saved provider, or null when none is configured.
final liveSourceProvider = Provider<LiveSource?>((ref) {
  final config = ref.watch(savedProviderProvider).value;
  if (config == null) return null;
  final source = LiveSource.forConfig(
    config,
    httpClient: ref.watch(httpClientProvider),
  );
  ref.onDispose(source.close);
  return source;
});

/// Short hash identifying the saved provider ([providerKey]); null when
/// none is configured. Keys per-provider caches and watch history.
final providerKeyProvider = Provider<String?>((ref) {
  final config = ref.watch(savedProviderProvider).value;
  return config == null ? null : providerKey(config);
});

/// Movies and series of the saved provider; null when none is configured
/// or it has none (M3U).
final vodSourceProvider = Provider<VodSource?>((ref) {
  final config = ref.watch(savedProviderProvider).value;
  if (config == null) return null;
  final source = VodSource.forConfig(
    config,
    httpClient: ref.watch(httpClientProvider),
  );
  ref.onDispose(() => source?.close());
  return source;
});

/// Where movie and series details come from. Only the provider for now;
/// more sources (e.g. TMDB) can be added with [CombinedMetadataSource].
final metadataSourceProvider = Provider<MetadataSource?>((ref) {
  final source = ref.watch(vodSourceProvider);
  return source == null ? null : ProviderMetadataSource(source);
});

/// Disk cache of the movie and series catalogues. Overridden in tests.
final vodRepositoryProvider = Provider<VodRepository>(
  (ref) => FileVodRepository(),
);

final movieCatalogProvider =
    NotifierProvider<MovieCatalogController, VodState<Movie>>(
      MovieCatalogController.new,
    );

final seriesCatalogProvider =
    NotifierProvider<SeriesCatalogController, VodState<Series>>(
      SeriesCatalogController.new,
    );

/// The provider tags (`NF-DO`, `4K-SC`…) of the movie and series
/// catalogues, for titles with a label. Knows none until a catalogue is
/// loaded, so names show whole until then.
final providerTagsProvider = Provider<ProviderTags>((ref) {
  final movies = ref.watch(movieCatalogProvider.select((s) => s.catalog));
  final series = ref.watch(seriesCatalogProvider.select((s) => s.catalog));
  if (movies == null && series == null) return ProviderTags.empty;
  return ProviderTags.fromNames([
    for (final m in movies?.items ?? const <Movie>[]) m.name,
    for (final s in series?.items ?? const <Series>[]) s.name,
  ]);
});

final movieFilterProvider = NotifierProvider<VodFilterNotifier, VodFilter>(
  VodFilterNotifier.new,
);

final seriesFilterProvider = NotifierProvider<VodFilterNotifier, VodFilter>(
  VodFilterNotifier.new,
);

/// Creates the watch history store of a provider (by [providerKey]).
/// Overridden in tests.
final watchStoreProvider = Provider<WatchStore Function(String key)>(
  (ref) =>
      (key) => _FileWatchStore(key),
);

/// Resume positions and watched marks of the saved provider.
final watchProvider = NotifierProvider<WatchController, WatchData>(
  WatchController.new,
);

/// Creates the favourites store of a provider (by [providerKey]).
/// Overridden in tests.
final favouritesStoreProvider = Provider<FavouritesStore Function(String key)>(
  (ref) =>
      (key) => _FileFavouritesStore(key),
);

/// My categories and hidden provider categories of the saved provider.
final favouritesProvider =
    NotifierProvider<FavouritesController, FavouritesData>(
      FavouritesController.new,
    );

/// The section (`live`, `movies`, `series`) whose category list is in
/// edit mode, if any.
final categoryEditingProvider = NotifierProvider<CategoryEditing, String?>(
  CategoryEditing.new,
);

class CategoryEditing extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String section) => state = state == section ? null : section;
}

/// Creates the playlist status store of a provider (by [providerKey]).
/// Overridden in tests.
final playlistStatusStoreProvider =
    Provider<PlaylistStatusStore Function(String key)>(
      (ref) =>
          (key) => _FilePlaylistStatusStore(key),
    );

/// Poster and logo images, cached on disk. Overridden in tests.
final posterLoaderProvider = Provider<PosterLoader>(
  (ref) => PosterCache(client: ref.watch(httpClientProvider)),
);

/// [JsonFileWatchStore] in the app support directory, resolved lazily.
class _FileWatchStore implements WatchStore {
  _FileWatchStore(this._key);

  final String _key;

  Future<WatchStore> get _store async => JsonFileWatchStore(
    File('${(await getApplicationSupportDirectory()).path}/watch/$_key.json'),
  );

  @override
  Future<WatchData> load() async => (await _store).load();

  @override
  Future<void> save(WatchData data) async => (await _store).save(data);
}

/// [JsonFileFavouritesStore] in the app support directory, resolved
/// lazily.
class _FileFavouritesStore implements FavouritesStore {
  _FileFavouritesStore(this._key);

  final String _key;

  Future<FavouritesStore> get _store async => JsonFileFavouritesStore(
    File(
      '${(await getApplicationSupportDirectory()).path}/favourites/$_key.json',
    ),
  );

  @override
  Future<FavouritesData> load() async => (await _store).load();

  @override
  Future<void> save(FavouritesData data) async => (await _store).save(data);
}

/// [JsonFilePlaylistStatusStore] in the app support directory, resolved
/// lazily.
class _FilePlaylistStatusStore implements PlaylistStatusStore {
  _FilePlaylistStatusStore(this._key);

  final String _key;

  Future<PlaylistStatusStore> get _store async => JsonFilePlaylistStatusStore(
    File(
      '${(await getApplicationSupportDirectory()).path}/playlist/$_key.json',
    ),
  );

  @override
  Future<PlaylistStatus> load() async => (await _store).load();

  @override
  Future<void> save(PlaylistStatus status) async => (await _store).save(status);
}

/// Categories and channels of the active provider.
///
/// This is the session cache: the catalog is fetched once and kept in memory
/// until the provider changes or it is refreshed. It is never written to
/// disk.
final liveCatalogProvider =
    AsyncNotifierProvider<LiveCatalogController, LiveCatalog>(
      LiveCatalogController.new,
    );

/// Loads the channels, and on [refresh] downloads them again, keeping the
/// current ones until the new ones are ready (or for good, when that
/// fails). Records each download in [playlistStatusProvider].
class LiveCatalogController extends AsyncNotifier<LiveCatalog> {
  Future<String?>? _refreshing;

  @override
  Future<LiveCatalog> build() async {
    final source = ref.watch(liveSourceProvider);
    if (source == null) throw StateError('No provider configured');
    try {
      final catalog = await _download(source);
      _record(null);
      return catalog;
    } catch (e) {
      _record(describeRefreshError(e));
      rethrow;
    }
  }

  /// Records a download in [playlistStatusProvider]: a success, or the
  /// failure [error].
  void _record(String? error) {
    if (!ref.mounted) return;
    final status = ref.read(playlistStatusProvider.notifier);
    final now = ref.read(clockProvider);
    if (error == null) {
      status.recordSuccess(PlaylistPart.channels, now);
    } else {
      status.recordFailure(PlaylistPart.channels, now, error);
    }
  }

  Future<LiveCatalog> _download(LiveSource source) async {
    final catalog = await source.load();
    catalog.attachSearchIndex(
      await buildSearchIndex(ref.read(backgroundRunnerProvider), catalog.names),
    );
    return catalog;
  }

  /// Downloads the channels again; the error description when that fails.
  /// Concurrent calls share one download.
  Future<String?> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<String?> _refresh() async {
    final source = ref.read(liveSourceProvider);
    if (source == null) return null;
    final current = state.value;
    // With nothing loaded yet (it failed) the page shows loading again.
    if (current == null) state = const AsyncLoading();
    try {
      final catalog = await _download(source);
      checkNotEmptied(
        before: current?.channelCount ?? 0,
        after: catalog.channelCount,
      );
      if (!ref.mounted) return null;
      state = AsyncData(catalog);
      _record(null);
      return null;
    } catch (e, stack) {
      final message = describeRefreshError(e);
      // Only the plain description: never the URL or credentials.
      debugPrint('Loading channels failed: $message');
      if (!ref.mounted) return message;
      // The current channels stay; without any, the page shows the error.
      if (current == null) state = AsyncError(e, stack);
      _record(message);
      return message;
    }
  }
}

/// Selected live category, shared by Live TV and the TV guide. Resets when
/// the provider changes. Read [liveSelectionProvider] for what to show.
final selectedCategoryProvider =
    NotifierProvider<SelectedCategory, CategorySelection>(SelectedCategory.new);

class SelectedCategory extends Notifier<CategorySelection> {
  @override
  CategorySelection build() {
    ref.watch(liveSourceProvider);
    return const AllCategories();
  }

  void select(CategorySelection selection) => state = selection;
}

/// [selectedCategoryProvider], falling back to all channels when the
/// selected category was deleted or hidden.
final liveSelectionProvider = Provider<CategorySelection>(
  (ref) => ref
      .watch(selectedCategoryProvider)
      .resolve(ref.watch(favouritesProvider), ContentKind.live),
);

/// Channels of the selected category: for all channels without hidden
/// categories, for one of my categories the ones the provider still has, in
/// the order they were added.
final categoryChannelsProvider = Provider<AsyncValue<List<LiveStream>>>((ref) {
  final catalog = ref.watch(liveCatalogProvider);
  final selection = ref.watch(liveSelectionProvider);
  final favourites = ref.watch(favouritesProvider);
  return catalog.whenData(
    (c) => switch (selection) {
      AllCategories() => c.channelsExcluding(
        favourites.hiddenIds(ContentKind.live),
      ),
      ProviderCategory(:final id) => c.channelsIn(id),
      MyCategory(:final id) => myCategoryChannels(c, favourites, id),
    },
  );
});

/// The channels of my category [id] that [catalog] still lists, in the
/// order they were added.
List<LiveStream> myCategoryChannels(
  LiveCatalog catalog,
  FavouritesData favourites,
  String id,
) => [for (final m in favourites.itemsIn(id)) ?catalog.byStableId(m.item.id)];

/// Channel search text. Resets when the provider changes.
final channelQueryProvider = NotifierProvider<ChannelQuery, String>(
  ChannelQuery.new,
);

class ChannelQuery extends Notifier<String> {
  @override
  String build() {
    ref.watch(liveSourceProvider);
    return '';
  }

  void set(String query) => state = query;
}

/// Whether the channel search is limited to the selected category ("Only
/// in …"); otherwise it searches all channels. Resets when the provider
/// changes.
final channelSearchInCategoryProvider =
    NotifierProvider<ChannelSearchInCategory, bool>(
      ChannelSearchInCategory.new,
    );

class ChannelSearchInCategory extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(liveSourceProvider);
    return false;
  }

  void set(bool value) => state = value;
}

/// What the channel list shows: the selected category's channels (with
/// separators), or while searching the matching channels (without
/// separators) of all channels except hidden categories, or only of the
/// selected category with [channelSearchInCategoryProvider].
final visibleChannelsProvider = Provider<AsyncValue<List<LiveStream>>>((ref) {
  final query = ref.watch(channelQueryProvider);
  final inCategory =
      ref.watch(channelSearchInCategoryProvider) ||
      ref.watch(liveSelectionProvider) is AllCategories;
  final channels = ref.watch(categoryChannelsProvider);
  if (SearchQuery(query).isEmpty) return channels;
  final catalog = ref.watch(liveCatalogProvider);
  final hidden = ref.watch(
    favouritesProvider.select((f) => f.hiddenIds(ContentKind.live)),
  );
  return catalog.whenData(
    (c) => c.search(
      query,
      within: inCategory ? channels.value : c.channelsExcluding(hidden),
    ),
  );
});

/// Where non-secret settings are persisted. Overridden in tests.
final settingsStorageProvider = Provider<SettingsStorage>(
  (ref) => FileSettingsStorage(),
);

/// User settings; defaults until loaded.
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
      AppSettingsNotifier.new,
    );

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsStorageProvider).load();

  /// Applies [settings] at once and saves them. Throws if saving fails.
  Future<void> set(AppSettings settings) async {
    state = AsyncData(settings);
    await ref.read(settingsStorageProvider).save(settings);
  }

  /// Applies [apply] to the loaded settings and saves them. Waits for the
  /// saved settings first, so they are never replaced by defaults.
  Future<void> change(AppSettings Function(AppSettings) apply) async =>
      set(apply(await future));

  /// [change] for layout preferences (sidebar, category lists): a failed
  /// save is ignored, since the layout still applies for this session.
  void remember(AppSettings Function(AppSettings) apply) =>
      unawaited(change(apply).catchError((Object _) {}));
}

/// IANA name of the device's time zone. Overridden in tests.
final deviceTimeZoneProvider = Provider<String>((ref) => deviceTimeZone());

/// Converts guide times for display, from the time zone and shift settings.
final guideTimeProvider = Provider<GuideTime>((ref) {
  final settings = ref.watch(appSettingsProvider).value ?? const AppSettings();
  return GuideTime.named(
    settings.guideTimeZone ?? ref.watch(deviceTimeZoneProvider),
    shiftHours: settings.guideShiftHours,
  );
});

/// The current time in UTC, updated every 30 seconds for now/next and the
/// guide's time line. Overridden in tests.
final clockProvider = NotifierProvider<Clock, DateTime>(Clock.new);

class Clock extends Notifier<DateTime> {
  static const interval = Duration(seconds: 30);

  @override
  DateTime build() {
    final timer = Timer.periodic(interval, (_) => state = _now());
    ref.onDispose(timer.cancel);
    return _now();
  }

  static DateTime _now() => DateTime.now().toUtc();
}

/// Downloads and caches the TV guide. Overridden in tests.
final epgRepositoryProvider = Provider<EpgRepository>(
  (ref) => FileEpgRepository(),
);

/// Caches past programmes from the providers' archives. Overridden in
/// tests.
final archiveEpgRepositoryProvider = Provider<ArchiveEpgRepository>(
  (ref) => FileArchiveEpgRepository(),
);

/// The IANA zone the provider reads replay start times in: its own
/// (`server_info.timezone`) when it says, else the guide's time zone.
/// After a failure the guide's zone is used for a minute, then the
/// provider is asked again.
final serverTimeZoneProvider = FutureProvider<String>((ref) async {
  final source = ref.watch(liveSourceProvider);
  try {
    final zone = await source?.serverTimeZone();
    if (zone != null && GuideTime.findZone(zone) != null) return zone;
  } catch (e) {
    // Only the plain description: never the URL or credentials.
    debugPrint(
      "Could not read the provider's time zone: "
      '${describeRefreshError(e)}',
    );
    final retry = Timer(const Duration(minutes: 1), ref.invalidateSelf);
    ref.onDispose(retry.cancel);
  }
  return ref.read(guideTimeProvider).zoneName;
});

/// The TV guide of the active provider.
final guideProvider = NotifierProvider<GuideController, GuideState>(
  GuideController.new,
);

/// Whether the player shows its debug overlay, hwdec selector and log.
final playerDebugProvider = NotifierProvider<PlayerDebug, bool>(
  PlayerDebug.new,
);

class PlayerDebug extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void set(bool value) => state = value;
}

/// mpv hwdec mode used for playback, kept for the session.
final hwdecProvider = NotifierProvider<Hwdec, String>(Hwdec.new);

class Hwdec extends Notifier<String> {
  /// Offered in the debug UI. `vaapi-copy` works even when media_kit falls
  /// back to software rendering.
  static const modes = ['auto-safe', 'vaapi', 'vaapi-copy', 'no'];
  static const defaultMode = 'auto-safe';

  @override
  String build() => defaultMode;

  void set(String mode) => state = mode;
}

/// Whether channels play in an external mpv window instead of the embedded
/// media_kit player. On Linux the embedded player drops frames where plain
/// `mpv --hwdec=vaapi` doesn't.
final useExternalMpvProvider = Provider<bool>((ref) => Platform.isLinux);

/// The single external mpv; closed with the app.
final externalMpvProvider = Provider<ExternalMpvPlayer>((ref) {
  final player = ExternalMpvPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// Whether the external mpv should try to embed into the app window (X11
/// only; falls back to a separate window). `TVPLAYER_EMBED_MPV=0` turns it
/// off, e.g. to compare against the separate window.
final embedMpvProvider = Provider<bool>(
  (ref) => Platform.environment['TVPLAYER_EMBED_MPV'] != '0',
);

/// The native video area of the Linux runner.
final videoEmbedProvider = Provider<VideoEmbed>((ref) {
  final embed = VideoEmbed();
  ref.onDispose(embed.dispose);
  return embed;
});
