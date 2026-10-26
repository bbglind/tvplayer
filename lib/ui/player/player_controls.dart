import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../format.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'player_hint.dart';

/// A secondary pill icon button of the player (subtitles, favourite,
/// channels).
class PlayerPillButton extends StatelessWidget {
  const PlayerPillButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.selectedIcon,
    this.selected = false,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => PlayerTooltip(
    message: tooltip,
    child: IconButton(
      style: IconButton.styleFrom(
        backgroundColor: AppColors.hover,
        disabledBackgroundColor: AppColors.surface,
        shape: const StadiumBorder(),
      ),
      isSelected: selected,
      icon: Icon(icon),
      selectedIcon: selectedIcon == null ? null : Icon(selectedIcon),
      onPressed: onPressed,
    ),
  );
}

/// Mute toggle and a volume slider (0–100) that can be clicked and
/// dragged. [onDragging] reports drags, so hiding controls can wait.
class VolumeControl extends StatefulWidget {
  const VolumeControl({
    super.key,
    required this.volume,
    required this.muted,
    required this.onChanged,
    required this.onToggleMute,
    this.onDragging,
  });

  final double volume;
  final bool muted;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;
  final ValueChanged<bool>? onDragging;

  static const sliderWidth = 120.0;

  static const tooltip = 'Volume (↑ / ↓, or the mouse wheel on the video)';

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.volume).clamp(0.0, 100.0);
    final silent = widget.muted || value == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerTooltip(
          message: widget.muted ? 'Unmute (m)' : 'Mute (m)',
          child: IconButton(
            key: const Key('player.mute'),
            icon: Icon(silent ? Icons.volume_off : Icons.volume_up),
            onPressed: widget.onToggleMute,
          ),
        ),
        PlayerTooltip(
          message: VolumeControl.tooltip,
          child: SizedBox(
            width: VolumeControl.sliderWidth,
            child: Slider(
              key: const Key('player.volume'),
              value: value,
              max: 100,
              semanticFormatterCallback: (v) => 'Volume ${v.round()}%',
              onChangeStart: (v) {
                widget.onDragging?.call(true);
                setState(() => _drag = v);
              },
              onChanged: (v) {
                setState(() => _drag = v);
                widget.onChanged(v);
              },
              onChangeEnd: (v) {
                widget.onDragging?.call(false);
                widget.onChanged(v);
                setState(() => _drag = null);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Position, seek slider and end time of a movie or episode. The end time
/// shows the duration or, with [showRemaining], the time left (`-12:34`);
/// double-clicking it (or Enter while it has focus) switches.
class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.showRemaining,
    required this.onToggleRemaining,
    required this.onSeek,
    this.onDragging,
  });

  final Duration position;
  final Duration? duration;
  final bool showRemaining;
  final VoidCallback onToggleRemaining;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool>? onDragging;

  static const tooltip = 'Seek (← / →: 10 s)';

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration;
    if (duration == null || duration <= Duration.zero) {
      return Text(
        formatDuration(widget.position),
        key: const Key('mpv.position'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final max = duration.inMilliseconds.toDouble();
    // Whole seconds while playing: the bar then changes once a second,
    // which matters when its image is sent to mpv in fullscreen.
    final playing = widget.position.inSeconds * 1000.0;
    final value = (_drag ?? playing).clamp(0.0, max);
    final shown = Duration(milliseconds: value.round());
    return Row(
      children: [
        Text(formatDuration(shown), key: const Key('mpv.position')),
        Expanded(
          child: PlayerTooltip(
            message: PlayerSeekBar.tooltip,
            child: Slider(
              key: const Key('player.seek'),
              value: value,
              max: max,
              onChangeStart: (v) {
                widget.onDragging?.call(true);
                setState(() => _drag = v);
              },
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                widget.onDragging?.call(false);
                widget.onSeek(Duration(milliseconds: v.round()));
                setState(() => _drag = null);
              },
            ),
          ),
        ),
        EndTime(
          text: widget.showRemaining
              ? formatRemaining(shown, duration)
              : formatDuration(duration),
          showRemaining: widget.showRemaining,
          onToggle: widget.onToggleRemaining,
        ),
      ],
    );
  }
}

/// The end time of the seek bar; a double click, or Enter or Space while
/// it has focus, calls [onToggle].
class EndTime extends StatelessWidget {
  const EndTime({
    super.key,
    required this.text,
    required this.showRemaining,
    required this.onToggle,
  });

  final String text;
  final bool showRemaining;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PlayerTooltip(
      message: showRemaining
          ? 'Show the duration (double-click or Enter)'
          : 'Show the time left (double-click or Enter)',
      child: FocusRing(
        radius: AppRadius.small,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              onToggle();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            key: const Key('player.endTime'),
            behavior: HitTestBehavior.opaque,
            onDoubleTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(text),
            ),
          ),
        ),
      ),
    );
  }
}

/// The current local time as `HH:MM`, updated on the minute.
class PlayerClock extends StatefulWidget {
  const PlayerClock({super.key, this.now = DateTime.now});

  final DateTime Function() now;

  @override
  State<PlayerClock> createState() => _PlayerClockState();
}

class _PlayerClockState extends State<PlayerClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = widget.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _timer = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return Text(
      '${two(now.hour)}:${two(now.minute)}',
      key: const Key('player.clock'),
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: AppColors.textSecondary),
    );
  }
}
