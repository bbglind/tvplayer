import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';
import 'package:tvplayer_core/tvplayer_core.dart'
    as core
    show forgetChannel, recordChannel, recordPlayed;

import 'providers.dart';
import 'variants.dart';

/// Resume positions, watched marks and remembered track choices of the
/// active provider. Changes apply at once and are saved in the background.
class WatchController extends Notifier<WatchData> {
  WatchStore? _store;
  Future<void> _saving = Future.value();

  @override
  WatchData build() {
    final key = ref.watch(providerKeyProvider);
    if (key == null) return WatchData.empty;
    final store = _store = ref.watch(watchStoreProvider)(key);
    unawaited(_load(store));
    return WatchData.empty;
  }

  Future<void> _load(WatchStore store) async {
    WatchData saved;
    try {
      saved = await store.load();
    } catch (e) {
      debugPrint('Could not read the watch history (${e.runtimeType})');
      return;
    }
    if (!ref.mounted || !identical(store, _store)) return;
    // Keep anything recorded while loading.
    state = saved.merge(state);
  }

  /// Completes when everything changed so far is saved.
  @visibleForTesting
  Future<void> get saved => _saving;

  void _update(WatchData data) {
    if (!ref.mounted || identical(data, state)) return;
    state = data;
    final store = _store;
    if (store == null) return;
    _saving = _saving.then((_) async {
      try {
        await store.save(data);
      } catch (e) {
        debugPrint('Could not save the watch history (${e.runtimeType})');
      }
    });
  }

  DateTime get _now => DateTime.now().toUtc();

  /// The other sources of series [seriesId].
  List<int> _seriesVariants(int seriesId) =>
      ref.read(seriesVariantsProvider).variantsOf(seriesId);

  /// Records playback of [key] ([movieKey]/[episodeKey]) at [position].
  /// For an episode pass its series' [info], which updates the series'
  /// "Continue watching" entry.
  void recordProgress(
    String key, {
    required Duration position,
    required Duration? duration,
    SeriesInfo? info,
  }) {
    // May come in late from a closing player, e.g. when the app quits.
    if (!ref.mounted) return;
    final episode = info?.episodes
        .where((e) => episodeKey(e.id) == key)
        .firstOrNull;
    var data = state.withItems({
      key: updatedProgress(
        state.items[key],
        position: position,
        duration: duration,
        now: _now,
        seriesId: info?.series.seriesId,
        season: episode?.season,
        episode: episode?.episodeNumber,
      ),
    });
    if (info != null) {
      data = refreshSeries(
        data,
        info,
        variants: _seriesVariants(info.series.seriesId),
      );
    }
    _update(data);
  }

  /// Remembers that playback of [key] ([movieKey] / [seriesKey]) started,
  /// for "Last played".
  void recordPlayed(String key) => _update(core.recordPlayed(state, key, _now));

  /// Marks [movie] and its other sources as watched or unwatched.
  void markMovie(Movie movie, {required bool watched}) => _update(
    markWatched(
      state,
      [
        for (final id
            in ref.read(movieVariantsProvider).groupOf(movie.streamId))
          movieTarget(id),
      ],
      watched: watched,
      now: _now,
    ),
  );

  /// Marks [episodes] of [info] as watched or unwatched, in the other
  /// sources of the series too.
  void markEpisodes(
    SeriesInfo info,
    Iterable<Episode> episodes, {
    required bool watched,
  }) {
    final variants = _seriesVariants(info.series.seriesId);
    final group = EpisodeGroupView(state, info.series.seriesId, variants);
    _update(
      refreshSeries(
        markWatched(
          state,
          groupEpisodeTargets(info, episodes, group),
          watched: watched,
          now: _now,
        ),
        info,
        variants: variants,
      ),
    );
  }

  /// Brings the stored summary of [info] up to date (e.g. new episodes, or
  /// episodes watched in another source).
  void refreshSeriesSummary(SeriesInfo info) => _update(
    refreshSeries(state, info, variants: _seriesVariants(info.series.seriesId)),
  );

  /// Adds [channel] to "Recently viewed channels".
  void recordChannel(LiveStream channel) =>
      _update(core.recordChannel(state, channel.stableId, _now));

  /// Removes channel [stableId] from "Recently viewed channels".
  void forgetChannel(String stableId) =>
      _update(core.forgetChannel(state, stableId, _now));

  /// Removes movie [streamId] and its other sources from "Continue
  /// watching" by clearing their resume positions. Returns their progress
  /// before, for [restoreMovies].
  Map<int, WatchProgress> removeMovieFromContinue(int streamId) {
    final previous = <int, WatchProgress>{};
    var data = state;
    for (final id in ref.read(movieVariantsProvider).groupOf(streamId)) {
      if (data.movie(id) case final p?) previous[id] = p;
      data = removeContinueMovie(data, id, _now);
    }
    _update(data);
    return previous;
  }

  /// Puts back the [previous] progress of movies (Undo).
  void restoreMovies(Map<int, WatchProgress> previous) {
    var data = state;
    for (final MapEntry(:key, :value) in previous.entries) {
      data = restoreContinueMovie(data, key, value, _now);
    }
    _update(data);
  }

  /// Removes series [seriesId] and its other sources from "Continue
  /// watching" until one of their episodes is played or marked again.
  void removeSeriesFromContinue(int seriesId) {
    var data = state;
    for (final id in ref.read(seriesVariantsProvider).groupOf(seriesId)) {
      data = removeContinueSeries(data, id, _now);
    }
    _update(data);
  }

  /// Undoes [removeSeriesFromContinue].
  void restoreSeries(int seriesId) {
    var data = state;
    for (final id in ref.read(seriesVariantsProvider).groupOf(seriesId)) {
      data = restoreContinueSeries(data, id, _now);
    }
    _update(data);
  }

  /// Remembers a manual track choice for the rest of a series.
  void rememberTracks(int seriesId, TrackMemory memory) {
    if (state.seriesTracks[seriesId]?.memory == memory) return;
    _update(state.withTracks(seriesId, SeriesTracks(memory, _now)));
  }
}
