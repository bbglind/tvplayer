import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'providers.dart';

/// The automatic refresh choice and the last download of each part of the
/// saved provider's playlist, kept per provider.
final playlistStatusProvider =
    NotifierProvider<PlaylistStatusController, PlaylistStatus>(
      PlaylistStatusController.new,
    );

/// Loads and saves [PlaylistStatus]. Changes wait for the saved status,
/// so they are never replaced by it.
class PlaylistStatusController extends Notifier<PlaylistStatus> {
  PlaylistStatusStore? _store;
  Future<void> _loaded = Future.value();
  Future<void> _saving = Future.value();

  @override
  PlaylistStatus build() {
    final key = ref.watch(providerKeyProvider);
    _store = key == null ? null : ref.read(playlistStatusStoreProvider)(key);
    _loaded = _load();
    return PlaylistStatus.empty;
  }

  Future<void> _load() async {
    final store = _store;
    if (store == null) return;
    try {
      final saved = await store.load();
      if (ref.mounted) state = saved;
    } catch (e) {
      debugPrint('Could not read the playlist status (${e.runtimeType})');
    }
  }

  /// The status once the saved one is loaded.
  Future<PlaylistStatus> get loaded async {
    await _loaded;
    return state;
  }

  Future<void> _change(PlaylistStatus Function(PlaylistStatus) apply) async {
    await _loaded;
    if (!ref.mounted) return;
    final before = state;
    state = apply(before);
    if (identical(state, before)) return;
    final store = _store;
    if (store == null) return;
    final status = state;
    _saving = _saving.then(
      (_) => store.save(status).catchError((Object e) {
        debugPrint('Could not save the playlist status (${e.runtimeType})');
      }),
    );
    await _saving;
  }

  void recordSuccess(PlaylistPart part, DateTime at) =>
      unawaited(_change((s) => s.withPart(part, s.part(part).succeeded(at))));

  void recordFailure(PlaylistPart part, DateTime at, String error) => unawaited(
    _change((s) => s.withPart(part, s.part(part).failedWith(at, error))),
  );

  /// Takes [at] as [part]'s last update when none is known, e.g. from a
  /// cache made before the status was kept.
  void seed(PlaylistPart part, DateTime at) =>
      unawaited(_change((s) => s.seeded(part, at)));

  Future<void> setAutoRefresh(AutoRefresh mode) =>
      _change((s) => s.withAutoRefresh(mode));
}

/// The parts the saved provider has: channels always, movies and series
/// when it has a catalogue of them, the guide when it has one.
final availablePartsProvider = Provider<Set<PlaylistPart>>((ref) {
  final live = ref.watch(liveSourceProvider);
  if (live == null) return const {};
  final vod = ref.watch(vodSourceProvider) != null;
  return {
    PlaylistPart.channels,
    if (vod) ...[PlaylistPart.movies, PlaylistPart.series],
    if (live.hasGuide) PlaylistPart.guide,
  };
});

/// Whether something is playing. Automatic refresh waits until it stops.
final playbackActiveProvider = NotifierProvider<PlaybackActive, bool>(
  PlaybackActive.new,
);

class PlaybackActive extends Notifier<bool> {
  int _players = 0;

  @override
  bool build() => false;

  void begin() => state = ++_players > 0;

  void end() {
    if (_players > 0) _players--;
    state = _players > 0;
  }
}

/// What a playlist refresh is doing: the part being downloaded, the ones
/// waiting, and how far a run of several parts got.
@immutable
final class PlaylistRefreshState {
  const PlaylistRefreshState({
    this.running,
    this.waiting = const [],
    this.done = 0,
  });

  final PlaylistPart? running;
  final List<PlaylistPart> waiting;

  /// Parts finished in this run.
  final int done;

  static const idle = PlaylistRefreshState();

  bool get busy => running != null;

  /// Parts in this run, finished or not.
  int get total => done + waiting.length + (running == null ? 0 : 1);

  bool isWaiting(PlaylistPart part) => waiting.contains(part);
}

/// A failed automatic refresh, for a quiet notice.
@immutable
final class AutoRefreshFailure {
  const AutoRefreshFailure(this.parts);

  final List<PlaylistPart> parts;
}

/// The last automatic refresh that failed, until the next one runs.
final autoRefreshFailureProvider =
    NotifierProvider<AutoRefreshFailureNotifier, AutoRefreshFailure?>(
      AutoRefreshFailureNotifier.new,
    );

class AutoRefreshFailureNotifier extends Notifier<AutoRefreshFailure?> {
  @override
  AutoRefreshFailure? build() {
    ref.watch(providerKeyProvider);
    return null;
  }

  void report(AutoRefreshFailure failure) => state = failure;
}

/// Refreshes the playlist one part at a time, by hand ([refresh],
/// [refreshAll]) or automatically: when the app starts and every
/// [checkInterval] while it is open, the parts [dueParts] picks. Automatic
/// refresh waits while something plays. Kept alive by the app shell.
final playlistRefreshProvider =
    NotifierProvider<PlaylistRefreshController, PlaylistRefreshState>(
      PlaylistRefreshController.new,
    );

class PlaylistRefreshController extends Notifier<PlaylistRefreshState> {
  /// How often automatic refresh looks whether a part is due. Wall-clock
  /// times are compared, so a suspended computer catches up on waking.
  static const checkInterval = Duration(minutes: 15);

  final _pending = <PlaylistPart, Completer<String?>>{};

  /// A check postponed while something played; whether it was the one at
  /// start.
  bool? _postponed;

  bool _checking = false;

  @override
  PlaylistRefreshState build() {
    ref.watch(providerKeyProvider);
    ref.watch(liveSourceProvider);
    // A new provider: nothing of the old one's run is waiting any more.
    for (final c in _pending.values) {
      c.complete(null);
    }
    _pending.clear();
    _postponed = null;
    _checking = false;
    final timer = Timer.periodic(checkInterval, (_) => unawaited(_check()));
    ref.onDispose(timer.cancel);
    ref.listen(playbackActiveProvider, (_, playing) {
      final atStart = _postponed;
      if (playing || atStart == null) return;
      _postponed = null;
      unawaited(_check(atStart: atStart));
    });
    final started = ref.read(clockProvider);
    unawaited(_check(atStart: true, freshSince: started));
    return PlaylistRefreshState.idle;
  }

  /// Refreshes every part the provider has, one after another.
  Future<void> refreshAll() async {
    await Future.wait([
      for (final p in PlaylistPart.values)
        if (ref.read(availablePartsProvider).contains(p)) refresh(p),
    ]);
  }

  /// Refreshes [part] after the parts already waiting; joins a refresh of
  /// it that is waiting or running. Returns why it failed, or null.
  Future<String?> refresh(PlaylistPart part) {
    if (_pending[part] case final c?) return c.future;
    final completer = Completer<String?>();
    _pending[part] = completer;
    state = PlaylistRefreshState(
      running: state.running,
      waiting: [...state.waiting, part],
      done: state.done,
    );
    unawaited(_next());
    return completer.future;
  }

  Future<void> _next() async {
    if (state.running != null || state.waiting.isEmpty) return;
    final part = state.waiting.first;
    state = PlaylistRefreshState(
      running: part,
      waiting: state.waiting.sublist(1),
      done: state.done,
    );
    String? error;
    try {
      error = await _download(part);
    } catch (e) {
      error = 'Something went wrong (${e.runtimeType}).';
    }
    _pending.remove(part)?.complete(error);
    if (!ref.mounted) return;
    state = state.waiting.isEmpty
        ? PlaylistRefreshState.idle
        : PlaylistRefreshState(waiting: state.waiting, done: state.done + 1);
    unawaited(_next());
  }

  Future<String?> _download(PlaylistPart part) => switch (part) {
    PlaylistPart.channels => ref.read(liveCatalogProvider.notifier).refresh(),
    PlaylistPart.movies => ref.read(movieCatalogProvider.notifier).refresh(),
    PlaylistPart.series => ref.read(seriesCatalogProvider.notifier).refresh(),
    PlaylistPart.guide => ref.read(guideProvider.notifier).refresh(),
  };

  /// Waits until each available part has read its cache (and started a
  /// download when it had none), so a fresh cache isn't taken for a
  /// missing one.
  Future<void> _partsStarted(Set<PlaylistPart> parts) async {
    Future<void> quietly(Future<Object?> f) =>
        f.then((_) {}, onError: (Object _) {});
    await Future.wait([
      if (parts.contains(PlaylistPart.channels))
        quietly(ref.read(liveCatalogProvider.future)),
      if (parts.contains(PlaylistPart.movies))
        ref.read(movieCatalogProvider.notifier).started,
      if (parts.contains(PlaylistPart.series))
        ref.read(seriesCatalogProvider.notifier).started,
      if (parts.contains(PlaylistPart.guide))
        ref.read(guideProvider.notifier).started,
    ]);
  }

  /// Runs automatic refresh for the parts due now. [freshSince]: parts
  /// downloaded since then (while starting) are left alone.
  Future<void> _check({bool atStart = false, DateTime? freshSince}) async {
    if (_checking) return;
    _checking = true;
    try {
      final available = ref.read(availablePartsProvider);
      if (available.isEmpty) return;
      if (atStart) await _partsStarted(available);
      if (!ref.mounted) return;
      final status = await ref.read(playlistStatusProvider.notifier).loaded;
      if (!ref.mounted) return;
      if (ref.read(playbackActiveProvider)) {
        _postponed = (_postponed ?? false) || atStart;
        return;
      }
      final due = dueParts(
        mode: status.autoRefresh,
        status: status,
        available: available,
        now: ref.read(clockProvider),
        atStart: atStart,
        freshSince: freshSince,
      );
      if (due.isEmpty) return;
      final results = await Future.wait([for (final p in due) refresh(p)]);
      if (!ref.mounted) return;
      // Only news: a part that keeps failing isn't reported every time.
      final failed = [
        for (final (i, error) in results.indexed)
          if (error != null && !status.part(due[i]).failed) due[i],
      ];
      // No notice over the player: Settings still shows what failed.
      if (failed.isNotEmpty && !ref.read(playbackActiveProvider)) {
        ref
            .read(autoRefreshFailureProvider.notifier)
            .report(AutoRefreshFailure(failed));
      }
    } finally {
      _checking = false;
    }
  }
}

/// Refreshes [part] through [playlistRefreshProvider], for buttons.
void refreshPlaylistPart(WidgetRef ref, PlaylistPart part) =>
    unawaited(ref.read(playlistRefreshProvider.notifier).refresh(part));

/// The user's items the loaded catalogues no longer list.
final missingItemsProvider = Provider<MissingItems>((ref) {
  final movies = ref.watch(movieCatalogProvider);
  final series = ref.watch(seriesCatalogProvider);
  return missingItems(
    favourites: ref.watch(favouritesProvider),
    watch: ref.watch(watchProvider),
    live: ref.watch(liveCatalogProvider).value,
    movies: movies.loading ? null : movies.catalog,
    series: series.loading ? null : series.catalog,
  );
});

/// Converts to the device's local time, for "last updated" times.
final deviceTimeProvider = Provider<GuideTime>(
  (ref) => GuideTime.named(ref.watch(deviceTimeZoneProvider)),
);
