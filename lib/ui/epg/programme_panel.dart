import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../player/playback_request.dart';
import '../../state/providers.dart';
import '../live/replay_mark.dart';
import '../player/open_channel.dart';
import '../theme/app_colors.dart';
import 'guide_screen.dart';

/// Whether [program] of [channel] can be replayed at [now]: null when it
/// can, else why not. Uses the programme's real times (with the guide's
/// shift).
ReplayBlock? replayBlock(
  LiveStream channel,
  EpgProgram program,
  GuideTime time,
  DateTime now,
) => ReplayWindow(channel.archiveDays).check(
  start: time.adjust(program.start),
  now: now,
  archived: program.archived,
);

/// The line shown instead of "Play" when a programme can't be replayed.
String replayBlockText(ReplayBlock block, int days) => switch (block) {
  ReplayBlock.noArchive => 'No replay: this channel has no archive',
  ReplayBlock.tooOld =>
    'No replay: older than ${days == 1 ? '1 day' : '$days days'}',
  ReplayBlock.notArchived => "No replay: not in the provider's archive",
  ReplayBlock.future => 'Not started yet',
};

/// Plays [channel] from the archive from the real moment [from].
Future<void> playReplay(
  BuildContext context,
  WidgetRef ref,
  LiveStream channel,
  DateTime from,
) async {
  final zone = await ref.read(serverTimeZoneProvider.future);
  if (!context.mounted) return;
  await openPlayback(
    context,
    ref,
    ReplayPlayback(
      channel,
      from: from,
      serverZone: zone,
      requestedAt: ref.read(clockProvider),
    ),
  );
}

/// Shows [program] of [channel] in a panel: title, time, channel and
/// description, with "Play" for a past programme that can be replayed,
/// "Watch live" and "Play from start" for one that is on, or why it
/// can't be replayed.
Future<void> showProgrammePanel(
  BuildContext context, {
  required LiveStream channel,
  required EpgProgram program,
}) => showDialog<void>(
  context: context,
  builder: (_) => ProgrammePanel(channel: channel, program: program),
);

class ProgrammePanel extends ConsumerWidget {
  const ProgrammePanel({
    super.key,
    required this.channel,
    required this.program,
  });

  final LiveStream channel;
  final EpgProgram program;

  static const maxWidth = 560.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final time = ref.watch(guideTimeProvider);
    final now = ref.watch(clockProvider);
    final start = time.adjust(program.start);
    final stop = time.adjust(program.stop);
    final running = !start.isAfter(now) && stop.isAfter(now);
    final block = replayBlock(channel, program, time, now);
    // The caller's context: this one goes with the dialog.
    final navigator = Navigator.of(context);
    final outer = navigator.context;

    void close() => navigator.pop();
    void watchLive() {
      close();
      openChannel(outer, ref, channel);
    }

    void play() {
      close();
      playReplay(outer, ref, channel, start);
    }

    final List<Widget> actions;
    if (running) {
      actions = [
        FilledButton.icon(
          key: const Key('programme.watchLive'),
          autofocus: true,
          onPressed: watchLive,
          icon: const Icon(Icons.live_tv_outlined),
          label: const Text('Watch live'),
        ),
        if (block == null)
          OutlinedButton.icon(
            key: const Key('programme.playFromStart'),
            onPressed: play,
            icon: const Icon(Icons.replay),
            label: const Text('Play from start'),
          ),
      ];
    } else if (block == null) {
      actions = [
        FilledButton.icon(
          key: const Key('programme.play'),
          autofocus: true,
          onPressed: play,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play'),
        ),
        OutlinedButton(onPressed: close, child: const Text('Close')),
      ];
    } else {
      actions = [
        OutlinedButton(
          key: const Key('programme.close'),
          autofocus: true,
          onPressed: close,
          child: const Text('Close'),
        ),
      ];
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                program.title,
                key: const Key('programme.title'),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${channelDisplayName(channel)} · '
                '${formatGuideDate(time, start)} '
                '${time.formatRange(program.start, program.stop)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (program.category case final category?) ...[
                const SizedBox(height: 4),
                Text(category, style: theme.textTheme.bodySmall),
              ],
              if (program.description case final description?) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
              if (block != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.history_toggle_off,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        replayBlockText(block, channel.archiveDays),
                        key: const Key('programme.noReplay'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
