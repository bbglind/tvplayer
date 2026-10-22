import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/errors.dart';
import 'providers.dart';

/// The TV guide as shown by the UI.
@immutable
final class GuideState {
  const GuideState({
    this.supported = true,
    this.guide,
    this.loading = false,
    this.error,
  });

  /// False when the provider has no guide (e.g. M3U playlists).
  final bool supported;

  /// The current guide; null until one is cached or downloaded.
  final EpgGuide? guide;

  /// Whether the cache is being read or the guide downloaded.
  final bool loading;

  /// Why the last download failed, if it did. Never contains URLs or
  /// credentials.
  final String? error;
}

/// Loads the cached guide, then refreshes it in the background when it is
/// older than [maxAge] (checked every [checkInterval]) or on [refresh].
class GuideController extends Notifier<GuideState> {
  static const maxAge = Duration(hours: 12);
  static const checkInterval = Duration(hours: 1);

  /// How far back finished programmes are kept.
  static const keepPast = Duration(hours: 6);

  Future<void>? _refreshing;

  @override
  GuideState build() {
    final source = ref.watch(liveSourceProvider);
    if (source == null || !source.hasGuide) {
      return const GuideState(supported: false);
    }
    final timer = Timer.periodic(checkInterval, (_) => _refreshIfStale());
    ref.onDispose(timer.cancel);
    unawaited(_start());
    return const GuideState(loading: true);
  }

  Future<void> _start() async {
    EpgGuide? cached;
    try {
      cached = await ref.read(epgRepositoryProvider).loadCache();
    } catch (e) {
      debugPrint('Could not read the guide cache (${e.runtimeType})');
    }
    if (!ref.mounted) return;
    if (cached != null) state = GuideState(guide: cached);
    await _refreshIfStale();
  }

  Future<void> _refreshIfStale() async {
    final guide = state.guide;
    final now = ref.read(clockProvider);
    if (guide != null && now.difference(guide.fetchedAt) < maxAge) return;
    await refresh();
  }

  /// Downloads a fresh guide, keeping the current one until it is ready.
  /// Concurrent calls share one download.
  Future<void> refresh() =>
      _refreshing ??= _download().whenComplete(() => _refreshing = null);

  Future<void> _download() async {
    final source = ref.read(liveSourceProvider);
    if (source == null || !source.hasGuide) return;
    state = GuideState(guide: state.guide, loading: true);
    try {
      final catalog = await ref.read(liveCatalogProvider.future);
      final now = ref.read(clockProvider);
      final guide = await ref
          .read(epgRepositoryProvider)
          .refresh(
            source,
            catalog.channels,
            now: now,
            keepFrom: now.subtract(keepPast),
          );
      if (!ref.mounted) return;
      state = GuideState(guide: guide);
    } catch (e) {
      if (!ref.mounted) return;
      final message = describeProviderError(e);
      // Only the redacted description: never the URL or credentials.
      debugPrint('Guide download failed: $message');
      state = GuideState(guide: state.guide, error: message);
    }
  }
}
