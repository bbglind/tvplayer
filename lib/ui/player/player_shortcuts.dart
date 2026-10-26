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

/// Marks a player side panel or card: while keyboard focus is inside it,
/// arrows, space and Enter move and press there instead of controlling
/// playback.
class PlayerPanelScope extends StatelessWidget {
  const PlayerPanelScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

bool _focusInPanel() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      (context.widget is PlayerPanelScope ||
          context.findAncestorWidgetOfExactType<PlayerPanelScope>() != null);
}

/// Player keyboard shortcuts, needed because mpv gets no keys when it is
/// embedded in the app window:
///
/// - space: pause/resume
/// - left/right: seek 10 s back/forward
/// - up/down: volume up/down
/// - f: fullscreen on/off
/// - Esc: [onEscape] (cancel, close a panel, leave fullscreen)
/// - s: next subtitle track (or off)
/// - m: mute on/off
/// - c: the channel list (live TV)
/// - n: the next episode
///
/// A null callback leaves its key alone (e.g. no seeking on live TV), and
/// no key is handled while a text field has focus; arrows and space are
/// left alone inside a [PlayerPanelScope]. Every key press is reported to
/// [onActivity] (it shows hidden controls).
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({
    super.key,
    required this.child,
    this.onTogglePause,
    this.onSeek,
    this.onVolume,
    this.onToggleFullscreen,
    this.onEscape,
    this.onCycleSubtitles,
    this.onToggleMute,
    this.onZap,
    this.onNextEpisode,
    this.onActivity,
    this.focusNode,
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
  final VoidCallback? onEscape;
  final VoidCallback? onCycleSubtitles;
  final VoidCallback? onToggleMute;
  final VoidCallback? onZap;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onActivity;

  /// The node that has focus while no control has it.
  final FocusNode? focusNode;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    onActivity?.call();
    if (textInputHasFocus()) return KeyEventResult.ignored;
    final repeat = event is KeyRepeatEvent;
    final key = event.logicalKey;
    if (_focusInPanel() && _panelKeys.contains(key)) {
      return KeyEventResult.ignored;
    }
    final VoidCallback? action = switch (key) {
      LogicalKeyboardKey.space when !repeat => onTogglePause,
      LogicalKeyboardKey.arrowLeft => _bind(onSeek, -seekStep),
      LogicalKeyboardKey.arrowRight => _bind(onSeek, seekStep),
      LogicalKeyboardKey.arrowUp => _bind(onVolume, volumeStep),
      LogicalKeyboardKey.arrowDown => _bind(onVolume, -volumeStep),
      LogicalKeyboardKey.keyF when !repeat => onToggleFullscreen,
      LogicalKeyboardKey.escape when !repeat => onEscape,
      LogicalKeyboardKey.keyS when !repeat => onCycleSubtitles,
      LogicalKeyboardKey.keyM when !repeat => onToggleMute,
      LogicalKeyboardKey.keyC when !repeat => onZap,
      LogicalKeyboardKey.keyN when !repeat => onNextEpisode,
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  /// Keys that move and press inside a panel.
  static final _panelKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  static VoidCallback? _bind<T>(ValueChanged<T>? f, T value) =>
      f == null ? null : () => f(value);

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focusNode,
    autofocus: true,
    onKeyEvent: _onKey,
    child: child,
  );
}
