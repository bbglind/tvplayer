import 'dart:async';

import 'package:flutter/foundation.dart';

import 'video_pointer.dart';

/// Turns pointer input on the video into gestures: a single click (only
/// once it can't become a double click), a double click (never also a
/// single click) and volume steps from the wheel.
class VideoGestures {
  VideoGestures({
    required this.onClick,
    required this.onDoubleClick,
    required this.onWheelSteps,
  });

  final VoidCallback onClick;
  final VoidCallback onDoubleClick;

  /// Called with whole wheel notches: negative up, positive down.
  final ValueChanged<int> onWheelSteps;

  Timer? _pending;

  /// Running after a double click, so its trailing press (e.g. of a
  /// triple click) isn't taken as a new click.
  Timer? _settle;
  double _scroll = 0;

  void handle(VideoPointerEvent event) {
    switch (event) {
      case VideoPointerDown(button: VideoMouseButton.primary):
        _press(event.doubleClickTime);
      case VideoDoubleClick():
        _doubleClick();
      case VideoScroll(:final dy):
        _wheel(dy);
      default:
    }
  }

  void _press(Duration doubleClickTime) {
    if (_pending != null || _settle != null) return;
    _pending = Timer(doubleClickTime, () {
      _pending = null;
      onClick();
    });
  }

  void _doubleClick() {
    _pending?.cancel();
    _pending = null;
    _settle?.cancel();
    _settle = Timer(VideoPointerDown.defaultDoubleClickTime, () {
      _settle = null;
    });
    onDoubleClick();
  }

  /// Adds up touchpad fractions to whole notches.
  void _wheel(double dy) {
    // A change of direction starts over.
    if (_scroll != 0 && dy.sign != _scroll.sign) _scroll = 0;
    _scroll += dy;
    final steps = _scroll.truncate();
    if (steps == 0) return;
    _scroll -= steps;
    onWheelSteps(steps);
  }

  void dispose() {
    _pending?.cancel();
    _settle?.cancel();
  }
}
