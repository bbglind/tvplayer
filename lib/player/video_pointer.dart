import 'dart:ui' show Offset;

/// Mouse button numbers of [VideoPointerDown] and [VideoPointerUp], as on
/// X11.
abstract final class VideoMouseButton {
  static const primary = 1;
  static const middle = 2;
  static const secondary = 3;
}

/// Pointer input from the video area, for players whose video surface
/// takes the pointer away from Flutter (the embedded mpv on Linux).
/// Positions are in logical pixels of the app view.
sealed class VideoPointerEvent {
  const VideoPointerEvent(this.position);

  final Offset position;
}

final class VideoPointerMove extends VideoPointerEvent {
  const VideoPointerMove(super.position);
}

final class VideoPointerDown extends VideoPointerEvent {
  const VideoPointerDown(
    super.position, {
    this.button = VideoMouseButton.primary,
    this.doubleClickTime = defaultDoubleClickTime,
  });

  /// See [VideoMouseButton].
  final int button;

  /// The longest gap between the clicks of a double click.
  final Duration doubleClickTime;

  static const defaultDoubleClickTime = Duration(milliseconds: 400);
}

final class VideoPointerUp extends VideoPointerEvent {
  const VideoPointerUp(
    super.position, {
    this.button = VideoMouseButton.primary,
  });

  final int button;
}

/// The second press of a double click; its presses came as
/// [VideoPointerDown] too.
final class VideoDoubleClick extends VideoPointerEvent {
  const VideoDoubleClick(super.position);
}

/// Wheel or touchpad scrolling: [dy] in wheel notches, positive is down.
/// Touchpads send fractions.
final class VideoScroll extends VideoPointerEvent {
  const VideoScroll(super.position, this.dy);

  final double dy;
}

/// A source of [VideoPointerEvent]s.
abstract interface class VideoPointerInput {
  Stream<VideoPointerEvent> get pointerEvents;
}
