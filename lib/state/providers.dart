import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/app_settings.dart';
import '../data/connection_tester.dart';
import '../data/device_time_zone.dart';
import '../data/epg_repository.dart';
import '../data/poster_cache.dart';
import '../data/provider_storage.dart';
import '../data/vod_repository.dart';
import '../player/mpv/external_mpv_player.dart';
import '../player/mpv/video_embed.dart';
import 'guide_controller.dart';
import 'vod_controller.dart';
import 'watch_controller.dart';

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

/// Categories and channels of the active provider.
///
/// This is the session cache: the catalog is fetched once and kept in memory
/// until the provider changes or [WidgetRef.invalidate] is called (retry or
/// refresh). It is never written to disk.
final liveCatalogProvider = FutureProvider<LiveCatalog>((ref) async {
  final source = ref.watch(liveSourceProvider);
  if (source == null) throw StateError('No provider configured');
  return source.load();
});

/// Selected category id; null means all channels. Resets when the provider
/// changes.
final selectedCategoryProvider = NotifierProvider<SelectedCategory, String?>(
  SelectedCategory.new,
);

class SelectedCategory extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(liveSourceProvider);
    return null;
  }

  void select(String? categoryId) => state = categoryId;
}

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

/// Channels of the selected category whose name contains the search text
/// (case-insensitive). Separators are kept, except while searching.
final visibleChannelsProvider = Provider<AsyncValue<List<LiveStream>>>((ref) {
  final catalog = ref.watch(liveCatalogProvider);
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(channelQueryProvider).trim().toLowerCase();
  return catalog.whenData((c) {
    final channels = c.channelsIn(category);
    if (query.isEmpty) return channels;
    return [
      for (final ch in channels)
        if (!ch.isSeparator && ch.name.toLowerCase().contains(query)) ch,
    ];
  });
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
