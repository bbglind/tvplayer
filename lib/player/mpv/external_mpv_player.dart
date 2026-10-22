import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../url_redactor.dart';
import 'mpv_ipc.dart';
import 'mpv_launcher.dart';

enum ExternalPlayerStatus { idle, starting, playing, exited, failed }

/// What the app knows about the external mpv of one [session].
@immutable
class ExternalPlaybackState {
  const ExternalPlaybackState({
    this.session = 0,
    this.status = ExternalPlayerStatus.idle,
    this.position,
    this.duration,
    this.paused = false,
    this.error,
    this.voDrops,
    this.decoderDrops,
  });

  /// Increases with every [ExternalMpvPlayer.open].
  final int session;
  final ExternalPlayerStatus status;

  /// mpv `time-pos`; null until known.
  final Duration? position;

  /// mpv `duration`; null for live streams and until known.
  final Duration? duration;
  final bool paused;

  /// User-facing error; never contains the stream URL.
  final String? error;

  /// mpv `frame-drop-count` (frames dropped at output); null until known.
  final int? voDrops;

  /// mpv `decoder-frame-drop-count`; null until known.
  final int? decoderDrops;

  ExternalPlaybackState copyWith({
    ExternalPlayerStatus? status,
    Duration? Function()? position,
    Duration? Function()? duration,
    bool? paused,
    String? error,
    int? Function()? voDrops,
    int? Function()? decoderDrops,
  }) => ExternalPlaybackState(
    session: session,
    status: status ?? this.status,
    position: position == null ? this.position : position(),
    duration: duration == null ? this.duration : duration(),
    paused: paused ?? this.paused,
    error: error ?? this.error,
    voDrops: voDrops == null ? this.voDrops : voDrops(),
    decoderDrops: decoderDrops == null ? this.decoderDrops : decoderDrops(),
  );
}

/// Connects to mpv's IPC socket; [MpvIpc.connect] in production.
typedef MpvIpcConnector = Future<MpvIpc> Function(
  String path, {
  Future<void>? abort,
});

/// Plays streams in a separate mpv process, one at a time.
///
/// mpv is started idle and given the URL over IPC, so the URL never appears
/// in a command line, log line or error message.
class ExternalMpvPlayer extends ChangeNotifier {
  ExternalMpvPlayer({
    this._start = Process.start,
    MpvIpcConnector connect = _connect,
    this.hwdec = 'vaapi',
    this._quitTimeout = const Duration(seconds: 2),
    this._statsInterval = const Duration(seconds: 1),
  }) : _connectIpc = connect;

  static Future<MpvIpc> _connect(String path, {Future<void>? abort}) =>
      MpvIpc.connect(path, abort: abort);

  final ProcessStarter _start;
  final MpvIpcConnector _connectIpc;
  final Duration _quitTimeout;

  /// How often the dropped-frame counters are polled.
  final Duration _statsInterval;
  final String hwdec;

  ExternalPlaybackState _state = const ExternalPlaybackState();
  _MpvRun? _run;
  bool _disposed = false;

  ExternalPlaybackState get state => _state;

  @protected
  set state(ExternalPlaybackState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  /// Closes any running mpv, then plays [url] in a new one titled [title],
  /// embedded into X11 window [wid] if given (see [MpvLaunchConfig.wid]).
  /// Returns the new session id; progress is reported through [state].
  int open(Uri url, {required String title, int? wid}) {
    final session = _state.session + 1;
    final previous = _run;
    final run = _run = _MpvRun(_quitTimeout);
    state = ExternalPlaybackState(
      session: session,
      status: ExternalPlayerStatus.starting,
    );
    unawaited(_play(run, previous, url, title, wid));
    return session;
  }

  Future<void> _play(
    _MpvRun run,
    _MpvRun? previous,
    Uri url,
    String title,
    int? wid,
  ) async {
    await previous?.close();
    final redactor = UrlRedactor(url);
    try {
      if (run.closed) return;
      final dir = run.socketDir = await _createSocketDir();
      if (run.closed) return await run.close();
      final ipcPath = '${dir.path}/mpv.sock';
      final process = run.process = await launchMpv(
        MpvLaunchConfig(title: title, ipcPath: ipcPath, hwdec: hwdec, wid: wid),
        start: _start,
      );
      unawaited(process.exitCode.then((_) => _onExit(run)));
      if (run.closed) return await run.close();

      final ipc = run.ipc = await _connectIpc(ipcPath, abort: process.exitCode);
      if (run.closed) return await run.close();
      ipc.events.listen((e) => _onEvent(run, e, redactor));
      await ipc.observeProperty(1, 'time-pos');
      await ipc.observeProperty(2, 'duration');
      await ipc.observeProperty(3, 'pause');
      await ipc.command(['loadfile', url.toString()]);
      run.statsTimer = Timer.periodic(_statsInterval, (_) => _pollDrops(run));
      if (_isCurrent(run) && _state.status == ExternalPlayerStatus.starting) {
        state = _state.copyWith(status: ExternalPlayerStatus.playing);
      }
    } on MpvLaunchException catch (e) {
      _fail(run, e.message);
      await run.close();
    } on MpvIpcException {
      // If mpv died on its own, the exit handler reports it.
      if (!run.exited) {
        _fail(run, 'Lost connection to mpv.');
        await run.close();
      }
    } on FileSystemException {
      _fail(run, 'Could not create the mpv control socket.');
      await run.close();
    }
  }

  void _onEvent(_MpvRun run, MpvEvent event, UrlRedactor redactor) {
    if (!_isCurrent(run)) return;
    switch (event.name) {
      case 'property-change':
        final data = event.data;
        state = switch (event.property) {
          'time-pos' => _state.copyWith(position: () => _seconds(data)),
          'duration' => _state.copyWith(duration: () => _seconds(data)),
          'pause' => _state.copyWith(paused: data == true),
          _ => _state,
        };
      case 'end-file' when event.fields['reason'] == 'error':
        final detail = event.fields['file_error'];
        state = _state.copyWith(
          error: redactor.redact(
            'mpv could not play the stream'
            '${detail is String ? ' ($detail)' : ''}.',
          ),
        );
    }
  }

  /// Reads the dropped-frame counters (not observed: they can change every
  /// frame, a once-a-second poll is enough for a readout).
  Future<void> _pollDrops(_MpvRun run) async {
    final ipc = run.ipc;
    if (ipc == null || run.polling || !_isCurrent(run)) return;
    run.polling = true;
    try {
      final vo = await _intProperty(ipc, 'frame-drop-count');
      final dec = await _intProperty(ipc, 'decoder-frame-drop-count');
      if (_isCurrent(run) &&
          (vo != _state.voDrops || dec != _state.decoderDrops)) {
        state = _state.copyWith(voDrops: () => vo, decoderDrops: () => dec);
      }
    } finally {
      run.polling = false;
    }
  }

  /// [name] as an int, or null while mpv has no value (e.g. no video yet).
  static Future<int?> _intProperty(MpvIpc ipc, String name) async {
    try {
      final value = await ipc.command(['get_property', name]);
      return value is num ? value.toInt() : null;
    } on MpvIpcException {
      return null;
    }
  }

  static Duration? _seconds(Object? value) => value is num
      ? Duration(microseconds: (value * Duration.microsecondsPerSecond).round())
      : null;

  Future<void> _onExit(_MpvRun run) async {
    run.exited = true;
    run.statsTimer?.cancel();
    // mpv's last events (e.g. an end-file error) may still be in flight.
    await run.ipc?.done.timeout(_quitTimeout, onTimeout: () {});
    unawaited(run.close());
    if (!_isCurrent(run)) return;
    final failed =
        _state.error != null || _state.status == ExternalPlayerStatus.failed;
    state = _state.copyWith(
      status: failed
          ? ExternalPlayerStatus.failed
          : ExternalPlayerStatus.exited,
    );
  }

  void _fail(_MpvRun run, String message) {
    if (!_isCurrent(run)) return;
    state = _state.copyWith(
      status: ExternalPlayerStatus.failed,
      error: message,
    );
  }

  bool _isCurrent(_MpvRun run) => !_disposed && identical(run, _run);

  /// Toggles pause of the current mpv.
  Future<void> togglePause() => _command(['cycle', 'pause']);

  /// Seeks the current mpv to [position].
  Future<void> seek(Duration position) =>
      _command(['seek', position.inMilliseconds / 1000, 'absolute']);

  Future<void> _command(List<Object?> args) async {
    try {
      await _run?.ipc?.command(args);
    } on MpvIpcException {
      // mpv is gone or refused; its state updates tell the rest.
    }
  }

  /// Closes mpv, if running. With [session], only if that session is still
  /// the current one.
  Future<void> stop({int? session}) async {
    if (session != null && session != _state.session) return;
    await _run?.close();
  }

  /// A private (0700) directory for the socket, under XDG_RUNTIME_DIR when
  /// available.
  static Future<Directory> _createSocketDir() {
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final base = runtime != null && Directory(runtime).existsSync()
        ? Directory(runtime)
        : Directory.systemTemp;
    return base.createTemp('tvplayer-mpv-');
  }

  /// Kills mpv immediately; for app shutdown paths that can't await [stop].
  @override
  void dispose() {
    _disposed = true;
    _run?.killNow();
    super.dispose();
  }
}

/// The process, socket and socket directory of one session.
class _MpvRun {
  _MpvRun(this._quitTimeout);

  final Duration _quitTimeout;
  Process? process;
  MpvIpc? ipc;
  Directory? socketDir;

  /// Set once [close] was requested; resources acquired later are released
  /// by calling [close] again.
  bool closed = false;
  bool exited = false;
  Timer? statsTimer;
  bool polling = false;

  /// Asks mpv to quit, then escalates to SIGTERM and SIGKILL, and removes
  /// the socket directory. Safe to call repeatedly.
  Future<void> close() async {
    closed = true;
    statsTimer?.cancel();
    final p = process;
    if (p != null && !exited) {
      try {
        await ipc?.command(['quit']).timeout(_quitTimeout);
      } on Object {
        // Fall through to signals.
      }
      if (!await _exits(p)) {
        p.kill();
        if (!await _exits(p)) p.kill(ProcessSignal.sigkill);
      }
    }
    await ipc?.close();
    ipc = null;
    final dir = socketDir;
    socketDir = null;
    try {
      await dir?.delete(recursive: true);
    } on FileSystemException {
      // Already gone.
    }
  }

  Future<bool> _exits(Process p) => p.exitCode
      .then((_) => true)
      .timeout(_quitTimeout, onTimeout: () => false);

  void killNow() {
    closed = true;
    statsTimer?.cancel();
    if (!exited) process?.kill();
    ipc?.close();
    try {
      socketDir?.deleteSync(recursive: true);
    } on FileSystemException {
      // Already gone.
    }
  }
}
