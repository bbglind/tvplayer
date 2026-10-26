import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/errors.dart';
import '../../player/playback_request.dart';
import '../../state/providers.dart';
import '../../state/variants.dart';
import '../player/open_channel.dart';
import '../vod/provider_title.dart';

/// Plays [movie], from where it was left off if it was started.
void playMovie(BuildContext context, WidgetRef ref, Movie movie) {
  // Where it, or another source of it, was left off.
  final start = resumePosition(
    ref.read(movieProgressProvider(movie.streamId))?.progress,
  );
  openPlayback(context, ref, MoviePlayback(movie, start: start));
}

/// Plays the episode to continue [series] with (in progress, or the next
/// unwatched one), else its first episode. The episode list is fetched
/// first, with [onLoading] told when that starts and ends; failures show in
/// a snack bar.
Future<void> playSeries(
  BuildContext context,
  WidgetRef ref,
  Series series, {
  ValueChanged<bool>? onLoading,
}) async {
  final source = ref.read(vodSourceProvider);
  if (source == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final SeriesInfo info;
  onLoading?.call(true);
  try {
    info = await source.seriesInfo(series.seriesId);
  } catch (e) {
    onLoading?.call(false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not load the episodes: ${describeProviderError(e)}',
        ),
      ),
    );
    return;
  }
  onLoading?.call(false);
  if (!context.mounted) return;
  final watch = ref.read(watchProvider);
  final view = ref.read(episodeViewProvider(series.seriesId));
  final episode =
      upNext(info, watch, group: view) ??
      info.episodes.where((e) => e.season != 0).firstOrNull ??
      info.episodes.firstOrNull;
  if (episode == null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('“${plainTitle(ref, series.name)}” has no episodes.'),
      ),
    );
    return;
  }
  ref.read(watchProvider.notifier).refreshSeriesSummary(info);
  final start = resumePosition(view.progress(episode));
  await openPlayback(
    context,
    ref,
    EpisodePlayback(info, episode, start: start),
  );
}
