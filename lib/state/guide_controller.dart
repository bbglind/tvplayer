import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/errors.dart';
import 'playlist_refresh.dart';
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

/// Loads the cached guide, downloads one when there is none, and a fresh
/// one on [refresh] (by hand or by automatic refresh, see
/// `PlaylistRefreshController`). Records each download in
/// [playlistStatusProvider].
class GuideController extends Notifier<GuideState> {
  /// How far back finished programmes are kept: providers' XMLTV guides
  /// reach about a day back. Further back, replay uses the providers'
  /// past listings (see `ArchiveListingsController`).
  static const keepPast = Duration(hours: 24);

  Future<String?>? _refreshing;
  Completer<void> _started = Completer();

  /// Completes once the cache was read (and a download started when there
  /// was none).
  Future<void> get started => _started.future;

  @override
  GuideState build() {
    _started = Completer();
    final source = ref.watch(liveSourceProvider);
    if (source == null || !source.hasGuide) {
      _started.complete();
      return const GuideState(supported: false);
    }
    unawaited(_start());
    return const GuideState(loading: true);
  }

  Future<void> _start() async {
    final started = _started;
    EpgGuide? cached;
    try {
      cached = await ref.read(epgRepositoryProvider).loadCache();
    } catch (e) {
      debugPrint('Could not read the guide cache (${e.runtimeType})');
    }
    if (!ref.mounted) return started.complete();
    if (cached == null) {
      // Through the queue, one part at a time; the download itself waits
      // for the channels.
      final download = ref
          .read(playlistRefreshProvider.notifier)
          .refresh(PlaylistPart.guide);
      started.complete();
      await download;
      return;
    }
    state = GuideState(guide: cached);
    ref
        .read(playlistStatusProvider.notifier)
        .seed(PlaylistPart.guide, cached.fetchedAt);
    started.complete();
  }

  /// Downloads a fresh guide, keeping the current one until it is ready,
  /// or for good when the download fails. Returns why it failed, or null.
  /// Concurrent calls share one download.
  Future<String?> refresh() =>
      _refreshing ??= _download().whenComplete(() => _refreshing = null);

  Future<String?> _download() async {
    final source = ref.read(liveSourceProvider);
    if (source == null || !source.hasGuide) return null;
    final status = ref.read(playlistStatusProvider.notifier);
    final current = state.guide;
    state = GuideState(guide: current, loading: true);
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
            rejectEmpty: (current?.programCount ?? 0) > 0,
          );
      if (!ref.mounted) return null;
      state = GuideState(guide: guide);
      status.recordSuccess(PlaylistPart.guide, guide.fetchedAt);
      return null;
    } catch (e) {
      final message = describeRefreshError(e);
      // Only the plain description: never the URL or credentials.
      debugPrint('Guide download failed: $message');
      if (!ref.mounted) return message;
      state = GuideState(guide: state.guide, error: message);
      status.recordFailure(
        PlaylistPart.guide,
        ref.read(clockProvider),
        message,
      );
      return message;
    }
  }
}
