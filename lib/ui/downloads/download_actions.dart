import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../player/playback_request.dart';
import '../../state/downloads_controller.dart';
import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../player/open_channel.dart';
import '../shell/app_messages.dart';

/// "Added “X” to Downloads" (with [episodes]: "Added 3 episodes of “X”
/// …") and "Show", which opens the Downloads page. Like every snack bar
/// with an action it closes by itself after 6 s and when another page
/// opens.
void showAddedToDownloads(
  BuildContext context,
  WidgetRef ref,
  String name, {
  int? episodes,
}) {
  final navigator = Navigator.of(context);
  showAppMessage(
    ScaffoldMessenger.of(context),
    switch (episodes) {
      null => 'Added “$name” to Downloads',
      final n =>
        'Added ${formatCountOf(n, 'episode', 'episodes')} of “$name” '
            'to Downloads',
    },
    key: const Key('downloads.added'),
    level: NoticeLevel.success,
    action: SnackBarAction(
      label: 'Show',
      onPressed: () {
        navigator.popUntil((route) => route.isFirst);
        ref.read(appSectionProvider.notifier).select(AppSection.downloads);
      },
    ),
  );
}

/// Asks before deleting [item]'s file (or partial file); true to delete.
Future<bool> confirmRemoveDownload(
  BuildContext context,
  DownloadItem item,
) async {
  final name = downloadName(item);
  final finished = item.isDone;
  final size = item.bytes > 0 ? ' (${formatBytes(item.bytes)})' : '';
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('download.remove.dialog'),
      title: Text(finished ? 'Remove “$name”?' : 'Cancel “$name”?'),
      content: Text(
        finished
            ? 'The file$size is deleted.'
            : 'The download stops and what was saved$size is deleted.',
      ),
      actions: [
        TextButton(
          key: const Key('download.remove.cancel'),
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: Text(finished ? 'Cancel' : 'Keep downloading'),
        ),
        FilledButton(
          key: const Key('download.remove.confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(finished ? 'Remove' : 'Cancel download'),
        ),
      ],
    ),
  );
  return yes == true;
}

/// Removes [item] and its file, after asking when there is something to
/// lose (a finished file or a partial one).
Future<void> removeDownloadFlow(
  BuildContext context,
  WidgetRef ref,
  DownloadItem item,
) async {
  if (item.isDone || item.bytes > 0) {
    if (!await confirmRemoveDownload(context, item)) return;
  }
  await ref.read(downloadsProvider.notifier).remove(item.id);
}

/// Plays the finished file of [item], offline. Movies and episodes share
/// their position and watched mark with the streamed item.
Future<void> playDownload(
  BuildContext context,
  WidgetRef ref,
  DownloadItem item,
) async {
  final watch = ref.read(watchProvider);
  switch (item.kind) {
    case DownloadKind.movie:
      final id = int.tryParse(item.sourceId);
      if (id == null) return;
      final progress = watch.items[movieKey(id)];
      await openPlayback(
        context,
        ref,
        MoviePlayback(
          Movie(
            streamId: id,
            name: item.title,
            containerExtension: item.extension,
          ),
          start: resumePosition(progress),
          localFile: item.path,
        ),
      );
    case DownloadKind.episode:
      final episode = Episode(
        id: item.sourceId,
        season: item.season ?? 1,
        episodeNumber: item.episode ?? 1,
        title: item.episodeTitle ?? 'Episode ${item.episode ?? 1}',
        containerExtension: item.extension,
      );
      final info = await _seriesInfo(ref, item, episode);
      if (!context.mounted) return;
      final match =
          info.episodes.where((e) => e.id == episode.id).firstOrNull ?? episode;
      await openPlayback(
        context,
        ref,
        EpisodePlayback(
          info,
          match,
          start: resumePosition(watch.items[episodeKey(episode.id)]),
          localFile: item.path,
        ),
      );
    case DownloadKind.replay || DownloadKind.recording:
      await openPlayback(
        context,
        ref,
        RecordingPlayback(item.path, name: downloadName(item)),
      );
  }
}

/// The series of [item] with all its episodes, for the next episode and
/// the series' progress; offline only [episode].
Future<SeriesInfo> _seriesInfo(
  WidgetRef ref,
  DownloadItem item,
  Episode episode,
) async {
  final source = ref.read(vodSourceProvider);
  final id = item.seriesId;
  if (source != null && id != null) {
    try {
      return await source.seriesInfo(id).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline: play it on its own.
    }
  }
  final series = Series(seriesId: id ?? 0, name: item.title);
  return SeriesInfo(
    series: series,
    seasons: [
      Season(seasonNumber: episode.season, name: 'Season ${episode.season}'),
    ],
    episodes: [episode],
  );
}

/// Unawaited [playDownload], for buttons.
void startDownloadPlayback(
  BuildContext context,
  WidgetRef ref,
  DownloadItem item,
) => unawaited(playDownload(context, ref, item));
