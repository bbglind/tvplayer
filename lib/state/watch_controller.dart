import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';
import 'package:tvplayer_core/tvplayer_core.dart'
    as core
    show forgetChannel, recordChannel;

import 'providers.dart';

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
    var data = state.withItems({
      key: updatedProgress(
        state.items[key],
        position: position,
        duration: duration,
        now: _now,
        seriesId: info?.series.seriesId,
      ),
    });
    if (info != null) data = refreshSeries(data, info);
    _update(data);
  }

  /// Marks [movie] as watched or unwatched.
  void markMovie(Movie movie, {required bool watched}) => _update(
    markWatched(
      state,
      [movieTarget(movie.streamId)],
      watched: watched,
      now: _now,
    ),
  );

  /// Marks [episodes] of [info] as watched or unwatched.
  void markEpisodes(
    SeriesInfo info,
    Iterable<Episode> episodes, {
    required bool watched,
  }) => _update(
    refreshSeries(
      markWatched(
        state,
        episodeTargets(info, episodes),
        watched: watched,
        now: _now,
      ),
      info,
    ),
  );

  /// Brings the stored summary of [info] up to date (e.g. new episodes).
  void refreshSeriesSummary(SeriesInfo info) =>
      _update(refreshSeries(state, info));

  /// Adds [channel] to "Recently viewed channels".
  void recordChannel(LiveStream channel) =>
      _update(core.recordChannel(state, channel.stableId, _now));

  /// Removes channel [stableId] from "Recently viewed channels".
  void forgetChannel(String stableId) =>
      _update(core.forgetChannel(state, stableId, _now));

  /// Removes movie [streamId] from "Continue watching" by clearing its
  /// resume position. Returns its progress before, for [restoreMovie].
  WatchProgress? removeMovieFromContinue(int streamId) {
    final previous = state.movie(streamId);
    _update(removeContinueMovie(state, streamId, _now));
    return previous;
  }

  /// Puts back the [previous] progress of movie [streamId] (Undo).
  void restoreMovie(int streamId, WatchProgress previous) =>
      _update(restoreContinueMovie(state, streamId, previous, _now));

  /// Removes series [seriesId] from "Continue watching" until one of its
  /// episodes is played or marked again.
  void removeSeriesFromContinue(int seriesId) =>
      _update(removeContinueSeries(state, seriesId, _now));

  /// Undoes [removeSeriesFromContinue].
  void restoreSeries(int seriesId) =>
      _update(restoreContinueSeries(state, seriesId, _now));

  /// Remembers a manual track choice for the rest of a series.
  void rememberTracks(int seriesId, TrackMemory memory) {
    if (state.seriesTracks[seriesId]?.memory == memory) return;
    _update(state.withTracks(seriesId, SeriesTracks(memory, _now)));
  }
}
