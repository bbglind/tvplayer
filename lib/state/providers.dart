import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/connection_tester.dart';
import '../data/provider_storage.dart';
import '../player/mpv/external_mpv_player.dart';

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
    state = AsyncData(config);
  }

  /// Forgets the saved provider. Throws [ProviderStorageException].
  Future<void> remove() async {
    await ref.read(providerStorageProvider).delete();
    state = const AsyncData(null);
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
/// (case-insensitive).
final visibleChannelsProvider = Provider<AsyncValue<List<LiveStream>>>((ref) {
  final catalog = ref.watch(liveCatalogProvider);
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(channelQueryProvider).trim().toLowerCase();
  return catalog.whenData((c) {
    final channels = c.channelsIn(category);
    if (query.isEmpty) return channels;
    return [
      for (final ch in channels)
        if (ch.name.toLowerCase().contains(query)) ch,
    ];
  });
});

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
