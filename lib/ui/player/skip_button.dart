import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'player_hint.dart';

/// "Skip intro" / "Skip recap": jumps to the end of the part. [prominent]
/// (right after the part starts) it is the filled main action, otherwise
/// outlined. The desktop names the key in its hint ("Skip intro (i)");
/// [touch] uses an ordinary tooltip without it.
class SkipButton extends StatelessWidget {
  const SkipButton({
    super.key,
    required this.type,
    required this.prominent,
    required this.onPressed,
    this.touch = false,
  });

  final SkipType type;
  final bool prominent;
  final VoidCallback onPressed;
  final bool touch;

  static String label(SkipType type) => switch (type) {
    SkipType.recap => 'Skip recap',
    _ => 'Skip intro',
  };

  @override
  Widget build(BuildContext context) {
    final text = label(type);
    const icon = Icon(Icons.fast_forward);
    final button = prominent
        ? FilledButton.icon(
            key: const Key('player.skip'),
            onPressed: onPressed,
            icon: icon,
            label: Text(text),
          )
        : OutlinedButton.icon(
            key: const Key('player.skip'),
            onPressed: onPressed,
            icon: icon,
            label: Text(text),
          );
    return touch
        ? Tooltip(message: text, child: button)
        : PlayerTooltip(message: '$text (i)', child: button);
  }
}
