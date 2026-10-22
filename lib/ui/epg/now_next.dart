import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';

/// Now and next programme of [channel] at the current time, or null when
/// the guide has nothing for it.
NowNext? watchNowNext(WidgetRef ref, LiveStream channel) {
  final guide = ref.watch(guideProvider.select((s) => s.guide));
  if (guide == null) return null;
  final time = ref.watch(guideTimeProvider);
  final now = ref.watch(clockProvider);
  final result = guide.nowAndNext(channel, time.unadjust(now));
  return result.now == null && result.next == null ? null : result;
}

/// One line for a channel list: `20:00–21:00 News · 21:00 Film`.
class NowNextLine extends ConsumerWidget {
  const NowNextLine({super.key, required this.channel});

  final LiveStream channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowNext = watchNowNext(ref, channel);
    if (nowNext == null) return const SizedBox.shrink();
    final time = ref.watch(guideTimeProvider);
    final (:now, :next) = nowNext;
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          if (now != null) ...[
            TextSpan(
              text: '${time.formatRange(now.start, now.stop)} ',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
            TextSpan(text: now.title),
          ],
          if (now != null && next != null) const TextSpan(text: '  ·  '),
          if (next != null)
            TextSpan(
              text: '${time.formatHm(next.start)} ${next.title}',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      key: Key('nowNext.${channel.id}'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Now (with progress) and next programme, for under the video.
class NowNextBar extends ConsumerWidget {
  const NowNextBar({super.key, required this.channel});

  final LiveStream channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowNext = watchNowNext(ref, channel);
    if (nowNext == null) return const SizedBox.shrink();
    final time = ref.watch(guideTimeProvider);
    final clock = time.unadjust(ref.watch(clockProvider));
    final (:now, :next) = nowNext;
    final theme = Theme.of(context);

    Widget row(String label, EpgProgram p) => Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: theme.textTheme.labelMedium),
        ),
        SizedBox(
          width: 104,
          child: Text(
            time.formatRange(p.start, p.stop),
            style: theme.textTheme.bodyMedium,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (now != null) ...[
              row('Now', now),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: now.duration.inSeconds == 0
                    ? 0
                    : clock.difference(now.start).inSeconds /
                          now.duration.inSeconds,
              ),
              const SizedBox(height: 4),
            ],
            if (next != null) row('Next', next),
          ],
        ),
      ),
    );
  }
}
