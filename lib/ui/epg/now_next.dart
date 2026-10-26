import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/archive_listings.dart';
import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';

/// Now and next programme of [channel] at the current time, or at the
/// real moment [at] (a replay's position, past listings included); null
/// when the guide has nothing for it.
NowNext? watchNowNext(WidgetRef ref, LiveStream channel, {DateTime? at}) {
  final time = ref.watch(guideTimeProvider);
  final NowNext result;
  if (at != null) {
    final lookup = ref.watch(guideLookupProvider);
    if (lookup == null) return null;
    result = lookup.nowAndNext(channel, time.unadjust(at));
  } else {
    final guide = ref.watch(guideProvider.select((s) => s.guide));
    if (guide == null) return null;
    final now = ref.watch(clockProvider);
    result = guide.nowAndNext(channel, time.unadjust(now));
  }
  return result.now == null && result.next == null ? null : result;
}

/// How far [program] has run at [clock] (both real UTC instants), 0–1.
double airedFraction(EpgProgram program, DateTime clock) =>
    program.duration.inSeconds == 0
    ? 0
    : (clock.difference(program.start).inSeconds / program.duration.inSeconds)
          .clamp(0.0, 1.0);

/// For a channel list: `News · until 21:00` with a progress bar, or
/// `Next: 21:00 Film` when nothing is on.
class NowNextLine extends ConsumerWidget {
  const NowNextLine({super.key, required this.channel});

  final LiveStream channel;

  /// Space above the progress bar, and its height.
  static const progressGap = 6.0;
  static const progressHeight = 3.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowNext = watchNowNext(ref, channel);
    if (nowNext == null) return const SizedBox.shrink();
    final time = ref.watch(guideTimeProvider);
    final (:now, :next) = nowNext;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.textSecondary);
    final text = Text(
      now != null
          ? '${now.title} · until ${time.formatHm(now.stop)}'
          : 'Next: ${time.formatHm(next!.start)} ${next.title}',
      key: Key('nowNext.${channel.id}'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (now == null) return text;
    final clock = time.unadjust(ref.watch(clockProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        const SizedBox(height: progressGap),
        ProgressStrip(airedFraction(now, clock), height: progressHeight),
      ],
    );
  }
}

/// Now (with progress) and next programme with their short descriptions,
/// for under the video: two lines for now, one for next where there is
/// room (a player at least [nextDescriptionMinHeight] high). In a replay
/// "now" is the programme at the playing position [at].
class NowNextBar extends ConsumerWidget {
  const NowNextBar({
    super.key,
    required this.channel,
    this.at,
    this.color = AppColors.surface,
  });

  final LiveStream channel;

  /// The real moment playing in a replay; null for live TV.
  final DateTime? at;
  final Color color;

  static const nextDescriptionMinHeight = 600.0;

  /// Width of the label and time columns; descriptions line up after them.
  static const _labelWidth = 60.0;
  static const _timeWidth = 104.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowNext = watchNowNext(ref, channel, at: at);
    if (nowNext == null) return const SizedBox.shrink();
    final time = ref.watch(guideTimeProvider);
    final clock = time.unadjust(at ?? ref.watch(clockProvider));
    final (:now, :next) = nowNext;
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final timeWidth = scaler.scale(_timeWidth);
    final roomy = MediaQuery.sizeOf(context).height >= nextDescriptionMinHeight;

    Widget description(EpgProgram p, int lines) {
      final text = p.description?.trim() ?? '';
      if (text.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(left: _labelWidth + timeWidth, top: 2),
        child: Text(
          text,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    Widget row(String label, EpgProgram p) => Row(
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(label.toUpperCase(), style: theme.textTheme.labelMedium),
        ),
        SizedBox(
          width: timeWidth,
          child: Text(
            time.formatRange(p.start, p.stop),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            p.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );

    return Material(
      key: const Key('player.nowNext'),
      color: color,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (now != null) ...[
              row('Now', now),
              description(now, 2),
              const SizedBox(height: 4),
              ProgressStrip(airedFraction(now, clock), height: 4),
              const SizedBox(height: 4),
            ],
            if (next != null) ...[
              row('Next', next),
              if (roomy) description(next, 1),
            ],
          ],
        ),
      ),
    );
  }
}
