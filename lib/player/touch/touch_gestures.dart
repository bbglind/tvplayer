import 'dart:async';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import '../playback_request.dart';

/// Which part of the video a touch is on: the left and right halves, less
/// a strip in the [middle] where taps never seek.
enum TapSide { left, middle, right }

/// Share of the width in the middle of the video where a double tap
/// doesn't seek.
const middleShare = 0.2;

TapSide tapSide(double x, double width) {
  if (width <= 0) return TapSide.middle;
  final f = x / width;
  if (f < 0.5 - middleShare / 2) return TapSide.left;
  if (f > 0.5 + middleShare / 2) return TapSide.right;
  return TapSide.middle;
}

/// Whether a double tap can seek in [request]: movies, episodes,
/// recordings and replays, never plain live TV.
bool canSeekByTap(PlaybackRequest request) => request.fixedLength;

/// Turns taps on the video into a single tap (toggle the controls) or
/// seeking: a double tap on the left or right half seeks by [step] back or
/// forward, and each further tap on that side within [streakWindow] seeks
/// another [step], like other video apps.
///
/// Where it [canSeek] says no (live TV) or in the middle, a tap counts at
/// once; elsewhere only once it can't become a double tap.
class TouchTaps {
  TouchTaps({
    required this.onTap,
    required this.onSeek,
    required this.onSeekEnd,
    required this.canSeek,
    this.step = const Duration(seconds: 10),
    this.doubleTapWindow = const Duration(milliseconds: 300),
    this.streakWindow = const Duration(milliseconds: 700),
  });

  final VoidCallback onTap;

  /// Seeks by [by] (negative: back); [total] is how far the taps on this
  /// side have sought so far, for the hint.
  final void Function(Duration by, Duration total, TapSide side) onSeek;

  /// The taps stopped: the hint can go.
  final VoidCallback onSeekEnd;
  final bool Function() canSeek;
  final Duration step;
  final Duration doubleTapWindow;
  final Duration streakWindow;

  Timer? _pending;
  TapSide? _pendingSide;
  Timer? _streak;
  TapSide? _streakSide;
  Duration _total = Duration.zero;

  /// Whether taps are seeking (a hint shows).
  bool get seeking => _streak != null;

  void tap(TapSide side) {
    final seekable = side != TapSide.middle && canSeek();
    if (_streak != null && seekable && side == _streakSide) {
      _seek(side);
      return;
    }
    _endStreak();
    if (!seekable) {
      _cancelPending();
      onTap();
      return;
    }
    if (_pending != null && _pendingSide == side) {
      _cancelPending();
      _total = Duration.zero;
      _streakSide = side;
      _seek(side);
      return;
    }
    // A first tap, or the second on the other side: wait for a double.
    if (_pending != null) {
      _cancelPending();
      onTap();
    }
    _pendingSide = side;
    _pending = Timer(doubleTapWindow, () {
      _pending = null;
      _pendingSide = null;
      onTap();
    });
  }

  void _seek(TapSide side) {
    final by = side == TapSide.left ? -step : step;
    _total += by;
    _streak?.cancel();
    _streak = Timer(streakWindow, _endStreak);
    onSeek(by, _total, side);
  }

  void _endStreak() {
    if (_streak == null) return;
    _streak!.cancel();
    _streak = null;
    _streakSide = null;
    _total = Duration.zero;
    onSeekEnd();
  }

  void _cancelPending() {
    _pending?.cancel();
    _pending = null;
    _pendingSide = null;
  }

  void dispose() {
    _pending?.cancel();
    _streak?.cancel();
  }
}

/// What a vertical swipe on the video changes.
enum SwipeTarget { brightness, volume }

/// Height of the strips at the top and bottom of the video where swipes
/// are left to the system (notification shade, home gesture).
const swipeEdge = 48.0;

/// What a vertical swipe starting at [start] on a video of [size]
/// changes: brightness on the left half, volume on the right; null near the
/// top and bottom edges.
SwipeTarget? swipeTarget(Offset start, Size size, {double edge = swipeEdge}) {
  if (start.dy < edge || start.dy > size.height - edge) return null;
  return start.dx < size.width / 2
      ? SwipeTarget.brightness
      : SwipeTarget.volume;
}

/// The level (0–1) after swiping [dy] (positive: down) from [start] on a
/// video [height] high: the full height is the whole range, up is more.
double levelAfterSwipe(double start, double dy, double height) {
  if (height <= 0) return start.clamp(0.0, 1.0);
  return (start - dy / height).clamp(0.0, 1.0);
}
