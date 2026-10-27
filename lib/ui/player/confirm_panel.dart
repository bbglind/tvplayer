import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/widgets.dart';
import 'player_hint.dart';
import 'player_shortcuts.dart';

/// A question asked in the player, as a side panel (dialogs can't be drawn
/// over the video): [title], [text], then [confirmLabel] (primary) and
/// [cancelLabel] (focused, also Esc).
class PlayerConfirmPanel extends StatelessWidget {
  const PlayerConfirmPanel({
    super.key,
    required this.title,
    required this.text,
    required this.confirmLabel,
    required this.confirmHint,
    required this.cancelLabel,
    required this.cancelHint,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String text;
  final String confirmLabel;
  final String confirmHint;
  final String cancelLabel;
  final String cancelHint;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PlayerPanelScope(
      child: Panel(
        key: const Key('player.confirm'),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PlayerTooltip(
                    message: confirmHint,
                    side: true,
                    child: FilledButton(
                      key: const Key('player.confirm.yes'),
                      onPressed: onConfirm,
                      child: Text(confirmLabel),
                    ),
                  ),
                  PlayerTooltip(
                    message: cancelHint,
                    side: true,
                    child: OutlinedButton(
                      key: const Key('player.confirm.no'),
                      autofocus: true,
                      onPressed: onCancel,
                      child: Text(cancelLabel),
                    ),
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
