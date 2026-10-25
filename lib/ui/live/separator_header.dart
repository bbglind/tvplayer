import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../theme/app_colors.dart';

/// A provider's category heading inside a channel list, like
/// `####### SWEDEN HD #######`: its text without the `#`, not playable.
class SeparatorHeader extends StatelessWidget {
  const SeparatorHeader({super.key, required this.channel, this.radius = 0});

  final LiveStream channel;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: Key('separator.${channel.id}'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        separatorTitle(channel.name) ?? channel.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium,
      ),
    );
  }
}
