import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../video_pointer.dart';

/// Embedding mpv is not possible; [reason] says why (never contains a URL).
class VideoEmbedException implements Exception {
  const VideoEmbedException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoEmbedException: $reason';
}

/// The native X11 child window of the Linux runner (`video_embed.cc`) that
/// mpv draws into via `--wid`.
///
/// Flutter can't draw over it, so it should only cover a black placeholder.
/// It gets the pointer events over the video (mpv leaves them alone) and
/// reports them as [pointerEvents].
class VideoEmbed implements VideoPointerInput {
  VideoEmbed({this._channel = const MethodChannel(channelName)}) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'tvplayer/video_embed';

  final MethodChannel _channel;
  final _pointer = StreamController<VideoPointerEvent>.broadcast();
  final _fullscreen = StreamController<bool>.broadcast();

  /// Clicks, movement and scrolling on the video area.
  @override
  Stream<VideoPointerEvent> get pointerEvents => _pointer.stream;

  /// The app window entered (true) or left (false) fullscreen, including
  /// changes made by the window manager.
  Stream<bool> get fullscreenChanges => _fullscreen.stream;

  /// Returns the X11 window id of the video area. Throws
  /// [VideoEmbedException], e.g. on Wayland.
  Future<int> create() async {
    try {
      final wid = await _channel.invokeMethod<int>('create');
      if (wid == null || wid == 0) {
        throw const VideoEmbedException('No X11 window id returned');
      }
      return wid;
    } on PlatformException catch (e) {
      throw VideoEmbedException(e.message ?? e.code);
    } on MissingPluginException {
      throw const VideoEmbedException('Native video area not available');
    }
  }

  /// Places the video area at [rect], in logical pixels of the app view.
  /// An empty rect hides it.
  Future<void> setRect(Rect rect) => _invoke('setRect', {
    'x': rect.left,
    'y': rect.top,
    'width': rect.width,
    'height': rect.height,
  });

  Future<void> hide() => _invoke('hide');

  /// Shows the normal mouse cursor over the video area, or none.
  Future<void> setCursorVisible(bool visible) =>
      _invoke('setCursorVisible', visible);

  /// Puts the whole app window in or out of fullscreen.
  Future<void> setFullscreen(bool fullscreen) =>
      _invoke('setFullscreen', fullscreen);

  Future<void> _invoke(String method, [Object? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Only reachable after a failed create(); nothing to move.
    } on PlatformException {
      // Ignored: worst case the area is misplaced until the next update.
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'pointer' || 'doubleClick' || 'scroll':
        if (pointerEventFromNative(call.method, call.arguments)
            case final event?) {
          _pointer.add(event);
        }
      case 'fullscreenChanged':
        _fullscreen.add(call.arguments == true);
    }
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _pointer.close();
    _fullscreen.close();
  }
}

/// A [VideoPointerEvent] from a `video_embed.cc` message, or null when it
/// is malformed.
@visibleForTesting
VideoPointerEvent? pointerEventFromNative(String method, Object? args) {
  if (args is! Map) return null;
  final x = args['x'];
  final y = args['y'];
  if (x is! num || y is! num) return null;
  final position = Offset(x.toDouble(), y.toDouble());
  final button = args['button'];
  final b = button is int ? button : VideoMouseButton.primary;
  switch (method) {
    case 'doubleClick':
      return VideoDoubleClick(position);
    case 'scroll':
      final dy = args['dy'];
      return dy is num ? VideoScroll(position, dy.toDouble()) : null;
  }
  return switch (args['kind']) {
    'down' => VideoPointerDown(
      position,
      button: b,
      doubleClickTime: switch (args['doubleClickMs']) {
        final int ms when ms > 0 => Duration(milliseconds: ms),
        _ => VideoPointerDown.defaultDoubleClickTime,
      },
    ),
    'up' => VideoPointerUp(position, button: b),
    'move' => VideoPointerMove(position),
    _ => null,
  };
}
