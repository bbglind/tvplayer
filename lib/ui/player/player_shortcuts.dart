import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether keyboard focus is in a text field (e.g. a search box), where
/// keys must type rather than control the player.
bool textInputHasFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Player keyboard shortcuts, needed because mpv gets no keys when it is
/// embedded in the app window:
///
/// - space: pause/resume
/// - left/right: seek 10 s back/forward
/// - up/down: volume up/down
/// - f: fullscreen on/off
/// - Esc: leave fullscreen
/// - s: next subtitle track (or off)
///
/// A null callback leaves its key alone (e.g. no seeking on live TV), and
/// no key is handled while a text field has focus.
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({
    super.key,
    required this.child,
    this.onTogglePause,
    this.onSeek,
    this.onVolume,
    this.onToggleFullscreen,
    this.onExitFullscreen,
    this.onCycleSubtitles,
  });

  static const seekStep = Duration(seconds: 10);
  static const volumeStep = 5;

  final Widget child;
  final VoidCallback? onTogglePause;

  /// Called with [seekStep] forward or back.
  final ValueChanged<Duration>? onSeek;

  /// Called with [volumeStep] up or down, in percent points.
  final ValueChanged<int>? onVolume;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onExitFullscreen;
  final VoidCallback? onCycleSubtitles;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || textInputHasFocus()) {
      return KeyEventResult.ignored;
    }
    final repeat = event is KeyRepeatEvent;
    final VoidCallback? action = switch (event.logicalKey) {
      LogicalKeyboardKey.space when !repeat => onTogglePause,
      LogicalKeyboardKey.arrowLeft => _bind(onSeek, -seekStep),
      LogicalKeyboardKey.arrowRight => _bind(onSeek, seekStep),
      LogicalKeyboardKey.arrowUp => _bind(onVolume, volumeStep),
      LogicalKeyboardKey.arrowDown => _bind(onVolume, -volumeStep),
      LogicalKeyboardKey.keyF when !repeat => onToggleFullscreen,
      LogicalKeyboardKey.escape when !repeat => onExitFullscreen,
      LogicalKeyboardKey.keyS when !repeat => onCycleSubtitles,
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  static VoidCallback? _bind<T>(ValueChanged<T>? f, T value) =>
      f == null ? null : () => f(value);

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, onKeyEvent: _onKey, child: child);
}
