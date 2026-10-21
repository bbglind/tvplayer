import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'url_redactor.dart';

/// mpv properties polled for the debug overlay.
const debugProperties = [
  'hwdec',
  'hwdec-current',
  'video-codec',
  'audio-codec',
  'video-params/w',
  'video-params/h',
  'video-params/pixelformat',
  'video-params/hw-pixelformat',
  'container-fps',
  'estimated-vf-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
];

/// Maximum number of log lines kept in memory.
const _maxLogLines = 500;

class PlayerLogEntry {
  PlayerLogEntry(this.level, this.text);

  final String level;
  final String text;
  final DateTime time = DateTime.now();

  bool get isError => level == 'error' || level == 'fatal';
}

/// One media_kit player plus the state the player UI shows: live mpv
/// properties, errors and log lines.
///
/// The stream URL is treated as secret: it is never logged, and log/error
/// text from mpv is redacted before it is stored.
class PlayerSession extends ChangeNotifier {
  PlayerSession({required String hwdec}) : _hwdec = hwdec {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'tvplayer',
        logLevel: MPVLogLevel.warn,
      ),
    );
    videoController = VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: hwdec),
    );
    _subscriptions.addAll([
      player.stream.log.listen(
        (log) => _addLog(log.level, '[${log.prefix}] ${log.text.trim()}'),
      ),
      player.stream.error.listen((error) {
        _lastError = _redact(error);
        _addLog('error', error);
      }),
      player.stream.playing.listen(_onPlaying),
      player.stream.completed.listen((completed) {
        if (completed) _addLog('info', 'Playback ended');
      }),
    ]);
  }

  late final Player player;
  late final VideoController videoController;

  final _subscriptions = <StreamSubscription<Object?>>[];
  final _logs = <PlayerLogEntry>[];
  UrlRedactor _redactor = UrlRedactor();
  String _hwdec;
  String? _lastError;
  bool _seekable = false;
  bool _polling = false;
  Map<String, String> _props = const {};
  Timer? _pollTimer;
  bool _disposed = false;

  List<PlayerLogEntry> get logs => List.unmodifiable(_logs);
  String? get lastError => _lastError;
  bool get seekable => _seekable;
  String get hwdec => _hwdec;

  /// Latest values of [debugProperties]; empty strings when unavailable.
  /// Polled once per second while playing and [debugPolling] is on.
  Map<String, String> get properties => _props;

  /// Whether to poll [debugProperties]. `seekable` is polled regardless.
  bool get debugPolling => _polling;
  set debugPolling(bool value) {
    _polling = value;
    if (value) unawaited(refreshProperties());
  }

  NativePlayer? get _native {
    final platform = player.platform;
    return platform is NativePlayer ? platform : null;
  }

  Future<void> open(Uri url) async {
    _redactor = UrlRedactor(url);
    _lastError = null;
    _props = const {};
    _seekable = false;
    _addLog('info', 'Opening stream');
    try {
      await player.open(Media(url.toString()));
    } catch (e) {
      // The exception may echo the URL; keep only its type.
      _lastError = 'Could not open stream (${e.runtimeType})';
      _addLog('error', _lastError!);
    }
  }

  Future<void> setHwdec(String value) async {
    if (value == _hwdec) return;
    _hwdec = value;
    notifyListeners();
    final native = _native;
    if (native == null) {
      _addLog('error', 'hwdec: native player not available');
      return;
    }
    try {
      await native.setProperty('hwdec', value);
      _addLog('info', 'hwdec set to $value');
    } catch (e) {
      _addLog('error', 'Setting hwdec failed (${e.runtimeType})');
    }
    await refreshProperties();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void dismissError() {
    _lastError = null;
    notifyListeners();
  }

  void _onPlaying(bool playing) {
    if (playing) {
      _pollTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => refreshProperties(),
      );
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    unawaited(refreshProperties());
  }

  Future<void> refreshProperties() async {
    final native = _native;
    if (native == null || _disposed) return;
    final values = <String, String>{};
    try {
      for (final name in [if (_polling) ...debugProperties, 'seekable']) {
        values[name] = await native.getProperty(name);
      }
    } catch (_) {
      // Player may be disposed mid-poll; nothing to show then.
      return;
    }
    if (_disposed) return;
    _seekable = values.remove('seekable') == 'yes';
    if (_polling) _props = values;
    notifyListeners();
  }

  void _addLog(String level, String text) {
    if (_disposed) return;
    _logs.add(PlayerLogEntry(level, _redact(text)));
    if (_logs.length > _maxLogLines) {
      _logs.removeRange(0, _logs.length - _maxLogLines);
    }
    notifyListeners();
  }

  String _redact(String text) => _redactor.redact(text);

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }
}
