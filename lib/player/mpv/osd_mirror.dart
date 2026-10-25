import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'external_mpv_player.dart';

/// Shows [child] on top of the embedded mpv video, where Flutter can't
/// draw: [child] is laid out and painted as usual (under mpv's window,
/// so unseen), and each new image of it is sent to mpv as overlay [id].
///
/// Pointer events reach [child] through a `PointerForwarder`, so it works
/// like any widget. Images are sent at most [maxRate] times a second, and
/// only when they changed.
class OsdMirror extends StatefulWidget {
  const OsdMirror({
    super.key,
    required this.id,
    required this.player,
    required this.child,
    this.videoOrigin = Offset.zero,
  });

  /// The mpv overlay id; one per mirror.
  final int id;
  final ExternalMpvPlayer player;
  final Widget child;

  /// Top left of the video area in the app view, logical pixels.
  final Offset videoOrigin;

  static const maxRate = 30;

  @override
  State<OsdMirror> createState() => _OsdMirrorState();
}

class _OsdMirrorState extends State<OsdMirror> {
  static const _minInterval = Duration(
    microseconds: Duration.microsecondsPerSecond ~/ OsdMirror.maxRate,
  );

  /// How often to look for changes that didn't repaint the mirror itself
  /// (descendants with their own repaint boundary, e.g. a text field).
  static const _checkInterval = Duration(milliseconds: 250);

  final _key = GlobalKey();
  final _clock = Stopwatch()..start();
  Duration? _lastCapture;
  Timer? _timer;
  bool _capturing = false;
  bool _dirty = false;
  bool _disposed = false;
  Uint8List? _lastImage;
  (int, int, int, int)? _lastPlace;

  @override
  void initState() {
    super.initState();
    _watchFrames();
  }

  @override
  void didUpdateWidget(OsdMirror oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.player != widget.player) {
      oldWidget.player.hideOverlay(oldWidget.id);
      _lastImage = null;
      _request();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    widget.player.hideOverlay(widget.id);
    super.dispose();
  }

  /// After each frame, checks now and then for unnoticed changes.
  void _watchFrames() {
    if (_disposed) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final last = _lastCapture;
      if (last == null || _clock.elapsed - last >= _checkInterval) _request();
      _watchFrames();
    });
  }

  void _onPainted() {
    if (_disposed) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => _request());
  }

  void _request() {
    if (_disposed) return;
    if (_capturing) {
      _dirty = true;
      return;
    }
    final last = _lastCapture;
    final wait = last == null
        ? Duration.zero
        : _minInterval - (_clock.elapsed - last);
    if (wait > Duration.zero) {
      _timer ??= Timer(wait, () {
        _timer = null;
        _request();
      });
      return;
    }
    unawaited(_capture());
  }

  Future<void> _capture() async {
    final boundary = _key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        !boundary.attached ||
        !boundary.hasSize ||
        boundary.size.isEmpty) {
      return;
    }
    _capturing = true;
    _lastCapture = _clock.elapsed;
    try {
      final ratio = View.of(context).devicePixelRatio;
      final origin =
          (boundary.localToGlobal(Offset.zero) - widget.videoOrigin) * ratio;
      final image = await boundary.toImage(pixelRatio: ratio);
      final ByteData? data;
      try {
        data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      } finally {
        image.dispose();
      }
      if (_disposed || data == null) return;
      final bgra = rgbaToBgra(data.buffer.asUint8List());
      final place = (
        origin.dx.round(),
        origin.dy.round(),
        image.width,
        image.height,
      );
      if (place == _lastPlace && _sameBytes(bgra, _lastImage)) return;
      _lastImage = bgra;
      _lastPlace = place;
      widget.player.showOverlay(
        widget.id,
        x: place.$1,
        y: place.$2,
        width: place.$3,
        height: place.$4,
        bgra: bgra,
      );
    } finally {
      _capturing = false;
      if (_dirty) {
        _dirty = false;
        _request();
      }
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List? b) {
    if (b == null || a.length != b.length) return false;
    final x = a.buffer.asUint64List(a.offsetInBytes, a.length ~/ 8);
    final y = b.buffer.asUint64List(b.offsetInBytes, b.length ~/ 8);
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    for (var i = x.length * 8; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) =>
      _MirrorBoundary(key: _key, onPainted: _onPainted, child: widget.child);
}

/// Premultiplied RGBA (Flutter's raw image bytes) as premultiplied BGRA
/// (mpv's overlay format), converted in place.
@visibleForTesting
Uint8List rgbaToBgra(Uint8List rgba) {
  final pixels = rgba.buffer.asUint32List(rgba.offsetInBytes, rgba.length ~/ 4);
  for (var i = 0; i < pixels.length; i++) {
    final v = pixels[i];
    // Little endian: swap the bytes of red and blue.
    pixels[i] = (v & 0xff00ff00) | ((v & 0xff) << 16) | ((v >> 16) & 0xff);
  }
  return rgba;
}

class _MirrorBoundary extends SingleChildRenderObjectWidget {
  const _MirrorBoundary({super.key, required this.onPainted, super.child});

  final VoidCallback onPainted;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMirrorBoundary(onPainted);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMirrorBoundary renderObject,
  ) => renderObject.onPainted = onPainted;
}

/// A repaint boundary that reports each repaint.
class _RenderMirrorBoundary extends RenderRepaintBoundary {
  _RenderMirrorBoundary(this.onPainted);

  VoidCallback onPainted;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPainted();
  }
}
