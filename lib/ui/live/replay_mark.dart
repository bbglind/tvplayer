import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../theme/app_colors.dart';
import '../theme/widgets.dart';

/// The name of [channel] as the app shows it: without the provider's own
/// replay mark (`◉`) when the app shows its [ReplayMark] instead.
String channelDisplayName(LiveStream channel) =>
    channel.hasReplay ? withoutReplayMark(channel.name) : channel.name;

/// "Replay: 3 days back".
String replayDescription(int days) =>
    'Replay: ${days == 1 ? '1 day' : '$days days'} back';

/// The app's sign that a channel's past programmes can be replayed.
class ReplayMark extends StatelessWidget {
  const ReplayMark({
    super.key,
    required this.days,
    this.size = 16,
    this.tooltip = true,
  });

  final int days;
  final double size;

  /// Off where the tooltip can't be shown (over the video): the row around
  /// it says it instead.
  final bool tooltip;

  @override
  Widget build(BuildContext context) {
    final description = replayDescription(days);
    final icon = Icon(
      Icons.history,
      key: const Key('replay.mark'),
      size: size,
      color: AppColors.textSecondary,
      semanticLabel: description,
    );
    if (!tooltip) return icon;
    return Tooltip(
      message: description,
      waitDuration: const Duration(milliseconds: 500),
      child: icon,
    );
  }
}

/// A channel's name ([channelDisplayName]) followed by its [ReplayMark]
/// when it has replay. The mark stays next to the name when the name is
/// cut short.
class ChannelName extends StatelessWidget {
  const ChannelName(
    this.channel, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.markTooltip = true,
    this.format,
  });

  final LiveStream channel;
  final TextStyle? style;
  final int maxLines;

  /// See [ReplayMark.tooltip].
  final bool markTooltip;

  /// Changes the shown name, e.g. how it wraps.
  final String Function(String name)? format;

  @override
  Widget build(BuildContext context) {
    final name = channelDisplayName(channel);
    final text = TruncatedText(
      format?.call(name) ?? name,
      style: style,
      maxLines: maxLines,
    );
    if (!channel.hasReplay) return text;
    return Row(
      children: [
        Flexible(child: text),
        const SizedBox(width: 6),
        ReplayMark(days: channel.archiveDays, tooltip: markTooltip),
      ],
    );
  }
}
