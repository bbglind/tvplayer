import 'dart:async';

import 'package:flutter/services.dart';

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
class VideoEmbed {
  VideoEmbed({this._channel = const MethodChannel(channelName)}) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'tvplayer/video_embed';

  final MethodChannel _channel;
  final _doubleClicks = StreamController<void>.broadcast();
  final _fullscreen = StreamController<bool>.broadcast();

  /// Double-clicks on the video area.
  Stream<void> get doubleClicks => _doubleClicks.stream;

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
      case 'doubleClick':
        _doubleClicks.add(null);
      case 'fullscreenChanged':
        _fullscreen.add(call.arguments == true);
    }
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _doubleClicks.close();
    _fullscreen.close();
  }
}
