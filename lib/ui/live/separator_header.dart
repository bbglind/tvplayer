import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// A provider's category heading inside a channel list, like
/// `####### SWEDEN HD #######`: its text without the `#`, not playable.
class SeparatorHeader extends StatelessWidget {
  const SeparatorHeader({super.key, required this.channel});

  final LiveStream channel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: Key('separator.${channel.id}'),
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        separatorTitle(channel.name) ?? channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
