import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/downloads_controller.dart';
import '../../state/providers.dart';
import '../../state/recording_controller.dart';
import '../epg/guide_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../vod/poster.dart';
import '../vod/provider_title.dart';
import 'download_actions.dart';

/// The Downloads page: the queue with progress ("In progress"), then the
/// recordings and programmes saved from the archive ("Recordings"), then
/// downloaded movies and episodes ("Downloaded"). Finished items play
/// offline.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(downloadsProvider);
    final pending = [
      for (final i in state.items)
        if (!i.isDone) i,
    ];
    final recordings = [
      for (final i in state.items.reversed)
        if (i.isDone &&
            (i.kind == DownloadKind.replay || i.kind == DownloadKind.recording))
          i,
    ];
    final downloaded = [
      for (final i in state.items.reversed)
        if (i.isDone &&
            (i.kind == DownloadKind.movie || i.kind == DownloadKind.episode))
          i,
    ];
    final folder = ref.watch(downloadFolderProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Downloads',
          actions: [
            Tooltip(
              message: folder,
              child: OutlinedButton.icon(
                key: const Key('downloads.openFolder'),
                onPressed: () => unawaited(_openFolder(folder)),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open folder'),
              ),
            ),
          ],
        ),
        Expanded(
          child: !state.loaded
              ? const Center(child: CircularProgressIndicator())
              : state.items.isEmpty
              ? const _Empty()
              : ListView(
                  key: const Key('downloads.list'),
                  padding: const EdgeInsets.fromLTRB(40, 0, 40, 28),
                  children: [
                    if (pending.isNotEmpty)
                      _Section(
                        title: 'In progress',
                        items: pending,
                        state: state,
                      ),
                    if (recordings.isNotEmpty)
                      _Section(
                        title: 'Recordings',
                        items: recordings,
                        state: state,
                      ),
                    if (downloaded.isNotEmpty)
                      _Section(
                        title: 'Downloaded',
                        items: downloaded,
                        state: state,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Opens [folder] in the file manager (created first, so there is
  /// something to open).
  static Future<void> _openFolder(String folder) async {
    try {
      await Directory(folder).create(recursive: true);
      await Process.start('xdg-open', [
        folder,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('Could not open the downloads folder (${e.runtimeType})');
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.download_outlined,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            Text('Nothing downloaded yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Use Download on a movie or an episode, or on a past programme '
              'in the TV guide. Record live TV from the player.',
              key: const Key('downloads.empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.state,
  });

  final String title;
  final List<DownloadItem> items;
  final DownloadsState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DownloadRow(item: item, state: state),
            ),
        ],
      ),
    );
  }
}

/// One entry: a poster or channel logo, the title, what it is, a progress
/// bar while it downloads, its status and the actions for it.
class DownloadRow extends ConsumerWidget {
  const DownloadRow({super.key, required this.item, required this.state});

  final DownloadItem item;
  final DownloadsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final time = ref.watch(guideTimeProvider);
    final recording = ref.watch(recordingProvider);
    final live =
        item.status == DownloadStatus.recording && recording?.id == item.id;
    final channel =
        item.kind == DownloadKind.replay || item.kind == DownloadKind.recording;
    final status = downloadStatusText(
      item,
      state,
      time,
      recording: live ? recording : null,
    );
    final failed = item.status == DownloadStatus.failed;
    final fraction = item.fraction;
    final showBar =
        !item.isDone &&
        item.status != DownloadStatus.recording &&
        (fraction != null || item.status == DownloadStatus.running);
    return AppTile(
      key: ValueKey('download.${item.id}'),
      onTap: item.isDone
          ? () => startDownloadPlayback(context, ref, item)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: SizedBox(
              width: channel ? 64 : 44,
              height: 64,
              child: Poster(
                url: item.posterUrl,
                decodeWidth: 128,
                fit: channel ? BoxFit.contain : BoxFit.cover,
                background: channel ? AppColors.background : AppColors.hover,
                placeholder: switch (item.kind) {
                  DownloadKind.movie => Icons.movie_outlined,
                  DownloadKind.episode => Icons.video_library_outlined,
                  DownloadKind.replay ||
                  DownloadKind.recording => Icons.live_tv_outlined,
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (item.label case final label?) ...[
                      ProviderLabel(label),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        _title(item),
                        key: const Key('download.title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (item.isDone) ...[
                      const SizedBox(width: 6),
                      const DownloadedBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _meta(item, time),
                  key: const Key('download.meta'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                if (showBar) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      key: const Key('download.progress'),
                      value: fraction,
                      minHeight: 4,
                      color: AppColors.accent,
                      backgroundColor: AppColors.hover,
                    ),
                  ),
                ],
                if (status != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (failed) ...[
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                      ] else if (live) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.live,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          status,
                          key: const Key('download.status'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ..._actions(context, ref),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final downloads = ref.read(downloadsProvider.notifier);
    Widget action(String key, String tooltip, IconData icon, VoidCallback? f) =>
        Tooltip(
          message: tooltip,
          child: IconButton(
            key: Key('download.$key'),
            icon: Icon(icon),
            onPressed: f,
          ),
        );
    void remove() => unawaited(removeDownloadFlow(context, ref, item));
    return switch (item.status) {
      DownloadStatus.running ||
      DownloadStatus.queued ||
      DownloadStatus.waiting => [
        action('pause', 'Pause', Icons.pause, () => downloads.pause(item.id)),
        action('cancel', 'Cancel download', Icons.close, remove),
      ],
      DownloadStatus.paused => [
        action(
          'resume',
          'Resume',
          Icons.play_arrow,
          () => downloads.resume(item.id),
        ),
        action('cancel', 'Cancel download', Icons.close, remove),
      ],
      DownloadStatus.failed => [
        action(
          'resume',
          'Try again',
          Icons.refresh,
          () => downloads.resume(item.id),
        ),
        action('cancel', 'Cancel download', Icons.close, remove),
      ],
      DownloadStatus.done => [
        action(
          'play',
          'Play',
          Icons.play_arrow,
          () => startDownloadPlayback(context, ref, item),
        ),
        action(
          'remove',
          'Remove (deletes the file)',
          Icons.delete_outline,
          remove,
        ),
      ],
      // Stopped in the player.
      DownloadStatus.recording => const [],
    };
  }

  static String _title(DownloadItem item) => switch (item.kind) {
    DownloadKind.movie => item.title,
    DownloadKind.episode => item.title,
    DownloadKind.replay ||
    DownloadKind.recording => item.programme ?? item.title,
  };

  static String _meta(DownloadItem item, GuideTime time) {
    final parts = <String>[];
    switch (item.kind) {
      case DownloadKind.movie:
        parts.add('Movie');
        if (item.year case final year?) parts.add('$year');
      case DownloadKind.episode:
        parts.add(formatEpisodeCode(item.season ?? 0, item.episode ?? 0));
        if (item.episodeTitle case final name?) parts.add(name);
      case DownloadKind.replay || DownloadKind.recording:
        parts.add(
          item.kind == DownloadKind.replay ? 'From the archive' : 'Recording',
        );
        if (item.programme != null) parts.add(item.title);
        if ((item.from, item.to) case (final from?, final to?)) {
          parts.add(
            '${formatGuideDate(time, from)} '
            '${time.formatLocalHm(from)}–${time.formatLocalHm(to)}',
          );
        }
    }
    if (item.isDone && item.bytes > 0) parts.add(formatBytes(item.bytes));
    return parts.join(' · ');
  }
}

/// The status line of [item]: progress, why it waits or stopped; null
/// when there is nothing to add.
String? downloadStatusText(
  DownloadItem item,
  DownloadsState state,
  GuideTime time, {
  ActiveRecording? recording,
}) {
  String sizes() {
    final total = item.totalBytes;
    return total == null
        ? formatBytes(item.bytes)
        : '${formatBytes(item.bytes)} of ${formatBytes(total)}';
  }

  String? percent() => switch (item.fraction) {
    final f? => '${(f * 100).floor()} %',
    null => null,
  };
  final note = item.message;
  switch (item.status) {
    case DownloadStatus.running:
      return [
        ?percent(),
        if (item.bytes > 0) sizes(),
        if (state.speed case final speed? when speed > 0) formatSpeed(speed),
        if (state.timeLeft case final left?) formatTimeLeft(left),
        ?note,
      ].join(' · ').ifEmpty('Starting…');
    case DownloadStatus.queued:
      return [
        'Waiting for its turn',
        if (item.bytes > 0) sizes(),
        ?note,
      ].join(' · ');
    case DownloadStatus.waiting:
      final to = item.to;
      return to == null
          ? 'Waiting for the programme to end'
          : 'Waiting: starts at ${time.formatLocalHm(to)}';
    case DownloadStatus.paused:
      return switch (item.pauseReason) {
        PauseReason.playback => 'Paused while playing',
        PauseReason.lowSpace => note ?? 'Paused: the disk is almost full',
        PauseReason.user ||
        null => ['Paused', ?percent(), if (item.bytes > 0) sizes()].join(' · '),
      };
    case DownloadStatus.failed:
      return 'Failed: ${note ?? 'unknown error'}';
    case DownloadStatus.recording:
      return [
        'Recording',
        if (recording != null) formatElapsed(recording.elapsed),
        if (item.bytes > 0) formatBytes(item.bytes),
      ].join(' · ');
    case DownloadStatus.done:
      return note;
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
