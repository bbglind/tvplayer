import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';
import 'player_shortcuts.dart';

/// "Next episode in N s" with the next episode's code and title, and
/// "Play now" / "Cancel". Shown next to or below the video, never on it.
class NextEpisodeCard extends StatelessWidget {
  const NextEpisodeCard({
    super.key,
    required this.next,
    required this.seconds,
    required this.onPlayNow,
    required this.onCancel,
    this.playNowFocus,
  });

  final Episode next;
  final int seconds;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;
  final FocusNode? playNowFocus;

  static const width = 360.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PlayerPanelScope(
      child: SizedBox(
        width: width,
        child: Panel(
          key: const Key('player.nextCard'),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Next episode in $seconds s',
                key: const Key('player.nextCountdown'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${formatEpisodeCode(next.season, next.episodeNumber)} · '
                '${next.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('player.playNow'),
                    focusNode: playNowFocus,
                    onPressed: onPlayNow,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Play now'),
                  ),
                  OutlinedButton(
                    key: const Key('player.cancelNext'),
                    onPressed: onCancel,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
