import 'package:flutter/gestures.dart';

import 'video_pointer.dart';

/// Feeds pointer input from the video area into Flutter as mouse events,
/// for widgets whose image is shown over the video (see `OsdMirror`):
/// they are hit-tested where they are laid out, under the video, so
/// hover, clicks, drags and scrolling work as if they were on top.
class PointerForwarder {
  PointerForwarder({required this.viewId, GestureBinding? binding})
    : _binding = binding ?? GestureBinding.instance;

  final int viewId;
  final GestureBinding _binding;
  final _clock = Stopwatch()..start();

  /// A device id of its own, so the real mouse's state is left alone.
  static const device = 0x7e000000;

  int _pointer = device;
  bool _added = false;
  int _buttons = 0;
  Offset _position = Offset.zero;

  /// Whether a button press is being forwarded (a click or drag that
  /// started on a forwarded widget).
  bool get pressed => _buttons != 0;

  Duration get _now => _clock.elapsed;

  void _dispatch(PointerEvent event) => _binding.handlePointerEvent(event);

  void _ensureAdded(Offset position) {
    if (_added) return;
    _added = true;
    _dispatch(
      PointerAddedEvent(
        timeStamp: _now,
        viewId: viewId,
        kind: PointerDeviceKind.mouse,
        device: device,
        position: position,
      ),
    );
  }

  void move(Offset position) {
    _ensureAdded(position);
    final delta = position - _position;
    _position = position;
    _dispatch(
      pressed
          ? PointerMoveEvent(
              timeStamp: _now,
              viewId: viewId,
              pointer: _pointer,
              kind: PointerDeviceKind.mouse,
              device: device,
              position: position,
              delta: delta,
              buttons: _buttons,
            )
          : PointerHoverEvent(
              timeStamp: _now,
              viewId: viewId,
              kind: PointerDeviceKind.mouse,
              device: device,
              position: position,
              delta: delta,
            ),
    );
  }

  void down(Offset position, int button) {
    if (pressed) return;
    move(position);
    _buttons = _flutterButton(button);
    _pointer++;
    _dispatch(
      PointerDownEvent(
        timeStamp: _now,
        viewId: viewId,
        pointer: _pointer,
        kind: PointerDeviceKind.mouse,
        device: device,
        position: position,
        buttons: _buttons,
      ),
    );
  }

  void up(Offset position) {
    if (!pressed) return;
    move(position);
    _buttons = 0;
    _dispatch(
      PointerUpEvent(
        timeStamp: _now,
        viewId: viewId,
        pointer: _pointer,
        kind: PointerDeviceKind.mouse,
        device: device,
        position: position,
      ),
    );
  }

  /// [dy] in wheel notches, as [VideoScroll.dy].
  void scroll(Offset position, double dy) {
    move(position);
    _dispatch(
      PointerScrollEvent(
        timeStamp: _now,
        viewId: viewId,
        kind: PointerDeviceKind.mouse,
        device: device,
        position: position,
        scrollDelta: Offset(0, dy * notchPixels),
      ),
    );
  }

  /// How far one wheel notch scrolls, like a mouse wheel on the app.
  static const notchPixels = 53.0;

  /// Ends any press and takes the pointer away, e.g. when leaving
  /// fullscreen, so hover highlights end.
  void remove() {
    if (!_added) return;
    if (pressed) {
      _buttons = 0;
      _dispatch(
        PointerCancelEvent(
          timeStamp: _now,
          viewId: viewId,
          pointer: _pointer,
          kind: PointerDeviceKind.mouse,
          device: device,
          position: _position,
        ),
      );
    }
    _added = false;
    _dispatch(
      PointerRemovedEvent(
        timeStamp: _now,
        viewId: viewId,
        kind: PointerDeviceKind.mouse,
        device: device,
        position: _position,
      ),
    );
  }

  static int _flutterButton(int button) => switch (button) {
    VideoMouseButton.secondary => kSecondaryMouseButton,
    VideoMouseButton.middle => kMiddleMouseButton,
    _ => kPrimaryMouseButton,
  };
}
