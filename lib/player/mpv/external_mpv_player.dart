import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

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
    this.tracks = const [],
    this.audioId,
    this.subtitleId,
    this.volume,
    this.muted = false,
    this.fileLoaded = false,
    this.endedAtEof = false,
    this.eofReached = false,
    this.seekable,
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

  /// mpv `track-list`: video, audio and subtitle tracks.
  final List<MediaTrack> tracks;

  /// Selected audio track (mpv `aid`); null for none or unknown.
  final int? audioId;

  /// Selected subtitle track (mpv `sid`); null when subtitles are off.
  final int? subtitleId;

  /// mpv `volume` in percent; null until known.
  final double? volume;

  /// mpv `mute`.
  final bool muted;

  /// Whether mpv has opened the media, so [tracks] is filled in.
  final bool fileLoaded;

  /// Whether playback ran to the end of the media (rather than being
  /// stopped or failing).
  final bool endedAtEof;

  /// Whether a file opened with `keepOpen` reached its end: mpv then holds
  /// the last frame instead of ending (mpv `eof-reached`).
  final bool eofReached;

  /// Whether mpv can seek in the media (mpv `seekable`); null until known.
  final bool? seekable;

  List<MediaTrack> get audioTracks => [
    for (final t in tracks)
      if (t.type == TrackType.audio) t,
  ];

  List<MediaTrack> get subtitleTracks => [
    for (final t in tracks)
      if (t.type == TrackType.subtitle) t,
  ];

  ExternalPlaybackState copyWith({
    ExternalPlayerStatus? status,
    Duration? Function()? position,
    Duration? Function()? duration,
    bool? paused,
    String? error,
    int? Function()? voDrops,
    int? Function()? decoderDrops,
    List<MediaTrack>? tracks,
    int? Function()? audioId,
    int? Function()? subtitleId,
    double? volume,
    bool? muted,
    bool? fileLoaded,
    bool? endedAtEof,
    bool? eofReached,
    bool? Function()? seekable,
  }) => ExternalPlaybackState(
    session: session,
    status: status ?? this.status,
    position: position == null ? this.position : position(),
    duration: duration == null ? this.duration : duration(),
    paused: paused ?? this.paused,
    error: error ?? this.error,
    voDrops: voDrops == null ? this.voDrops : voDrops(),
    decoderDrops: decoderDrops == null ? this.decoderDrops : decoderDrops(),
    tracks: tracks ?? this.tracks,
    audioId: audioId == null ? this.audioId : audioId(),
    subtitleId: subtitleId == null ? this.subtitleId : subtitleId(),
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    fileLoaded: fileLoaded ?? this.fileLoaded,
    endedAtEof: endedAtEof ?? this.endedAtEof,
    eofReached: eofReached ?? this.eofReached,
    seekable: seekable == null ? this.seekable : seekable(),
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

  /// The latest image of each shown overlay, sent again to a new mpv.
  final _overlays = <int, _Overlay>{};
  bool _disposed = false;

  ExternalPlaybackState get state => _state;

  @protected
  set state(ExternalPlaybackState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  /// Closes any running mpv, then plays [url] in a new one titled [title],
  /// embedded into X11 window [wid] if given (see [MpvLaunchConfig.wid]),
  /// from [start] if given, at [volume] percent if given. With [keepOpen]
  /// mpv holds the last frame at the end (see
  /// [ExternalPlaybackState.eofReached]). Returns the new session id;
  /// progress is reported through [state].
  int open(
    Uri url, {
    required String title,
    int? wid,
    Duration? start,
    int? volume,
    bool keepOpen = false,
  }) {
    final session = _state.session + 1;
    final previous = _run;
    final run = _run = _MpvRun(_quitTimeout);
    state = ExternalPlaybackState(
      session: session,
      status: ExternalPlayerStatus.starting,
    );
    unawaited(_play(run, previous, url, title, wid, start, volume, keepOpen));
    return session;
  }

  /// Plays [url] in the running mpv instead of the media it plays (mpv
  /// `loadfile … replace`), which closes the old stream before opening the
  /// new one and keeps the window, volume and overlays. Starts a new mpv
  /// with [open] when none runs. Returns the new session id.
  int reload(
    Uri url, {
    required String title,
    int? wid,
    Duration? start,
    bool keepOpen = false,
  }) {
    final run = _run;
    if (run == null || run.closed || run.exited || run.ipc == null) {
      return open(
        url,
        title: title,
        wid: wid,
        start: start,
        volume: _state.volume?.round(),
        keepOpen: keepOpen,
      );
    }
    final session = _state.session + 1;
    state = ExternalPlaybackState(
      session: session,
      status: ExternalPlayerStatus.starting,
      volume: _state.volume,
      muted: _state.muted,
    );
    unawaited(_load(run, session, url, title, start, keepOpen));
    return session;
  }

  Future<void> _load(
    _MpvRun run,
    int session,
    Uri url,
    String title,
    Duration? start,
    bool keepOpen,
  ) async {
    final ipc = run.ipc!;
    run.redactor = UrlRedactor(url);
    try {
      await _setLoadOptions(ipc, start, keepOpen);
      await ipc.command([
        'set_property',
        'title',
        MpvLaunchConfig.escapePropertyExpansion(title),
      ]);
      await ipc.command(['loadfile', url.toString(), 'replace']);
      if (_isCurrent(run) &&
          _state.session == session &&
          _state.status == ExternalPlayerStatus.starting) {
        state = _state.copyWith(status: ExternalPlayerStatus.playing);
      }
    } on MpvIpcException {
      // If mpv died on its own, the exit handler reports it.
      if (!run.exited && _state.session == session) {
        _fail(run, 'Lost connection to mpv.');
      }
    }
  }

  /// Options for the next file loaded: where to start, and whether to hold
  /// the last frame at its end.
  static Future<void> _setLoadOptions(
    MpvIpc ipc,
    Duration? start,
    bool keepOpen,
  ) async {
    await ipc.command([
      'set_property',
      'start',
      start != null && start > Duration.zero ? _secondsText(start) : 'none',
    ]);
    await ipc.command(['set_property', 'keep-open', keepOpen ? 'yes' : 'no']);
  }

  Future<void> _play(
    _MpvRun run,
    _MpvRun? previous,
    Uri url,
    String title,
    int? wid,
    Duration? start,
    int? volume,
    bool keepOpen,
  ) async {
    await previous?.close();
    run.redactor = UrlRedactor(url);
    try {
      if (run.closed) return;
      final dir = run.socketDir = await _createSocketDir();
      if (run.closed) return await run.close();
      final ipcPath = '${dir.path}/mpv.sock';
      final process = run.process = await launchMpv(
        MpvLaunchConfig(
          title: title,
          ipcPath: ipcPath,
          hwdec: hwdec,
          wid: wid,
          volume: volume,
        ),
        start: _start,
      );
      unawaited(process.exitCode.then((_) => _onExit(run)));
      if (run.closed) return await run.close();

      final ipc = run.ipc = await _connectIpc(ipcPath, abort: process.exitCode);
      if (run.closed) return await run.close();
      ipc.events.listen((e) => _onEvent(run, e));
      await ipc.observeProperty(1, 'time-pos');
      await ipc.observeProperty(2, 'duration');
      await ipc.observeProperty(3, 'pause');
      await ipc.observeProperty(4, 'track-list');
      await ipc.observeProperty(5, 'aid');
      await ipc.observeProperty(6, 'sid');
      await ipc.observeProperty(7, 'volume');
      await ipc.observeProperty(8, 'mute');
      await ipc.observeProperty(9, 'eof-reached');
      await ipc.observeProperty(10, 'seekable');
      if (start != null && start > Duration.zero) {
        // Applies to the next file loaded.
        await ipc.command(['set_property', 'start', _secondsText(start)]);
      }
      if (keepOpen) await ipc.command(['set_property', 'keep-open', 'yes']);
      await ipc.command(['loadfile', url.toString()]);
      run.statsTimer = Timer.periodic(_statsInterval, (_) => _pollDrops(run));
      for (final id in _overlays.keys.toList()) {
        unawaited(_sendOverlay(run, id));
      }
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

  void _onEvent(_MpvRun run, MpvEvent event) {
    if (!_isCurrent(run)) return;
    switch (event.name) {
      case 'property-change':
        final data = event.data;
        state = switch (event.property) {
          'time-pos' => _state.copyWith(position: () => _seconds(data)),
          'duration' => _state.copyWith(duration: () => _seconds(data)),
          'pause' => _state.copyWith(paused: data == true),
          'track-list' => _state.copyWith(tracks: parseMpvTrackList(data)),
          'aid' => _state.copyWith(audioId: () => _trackId(data)),
          'sid' => _state.copyWith(subtitleId: () => _trackId(data)),
          'volume' when data is num => _state.copyWith(volume: data.toDouble()),
          'mute' => _state.copyWith(muted: data == true),
          'eof-reached' => _state.copyWith(eofReached: data == true),
          'seekable' => _state.copyWith(
            seekable: () => data is bool ? data : null,
          ),
          _ => _state,
        };
      case 'start-file':
        // A new file (after a reload): what was known of the old one goes.
        state = _state.copyWith(
          position: () => null,
          duration: () => null,
          fileLoaded: false,
          endedAtEof: false,
          eofReached: false,
          seekable: () => null,
        );
      case 'file-loaded':
        state = _state.copyWith(fileLoaded: true);
      case 'end-file' when event.fields['reason'] == 'eof':
        state = _state.copyWith(endedAtEof: true);
      case 'end-file' when event.fields['reason'] == 'error':
        final detail = event.fields['file_error'];
        state = _state.copyWith(
          error: run.redactor.redact(
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

  /// An `aid`/`sid` value: a track id, or `false`/`"no"` for none.
  static int? _trackId(Object? value) => value is num ? value.toInt() : null;

  static String _secondsText(Duration d) =>
      (d.inMilliseconds / 1000).toStringAsFixed(3);

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

  /// Seeks the current mpv by [offset] (negative: back).
  Future<void> seekBy(Duration offset) =>
      _command(['seek', offset.inMilliseconds / 1000, 'relative']);

  /// Changes the volume by [percent] points (mpv clamps it).
  Future<void> changeVolume(int percent) =>
      _command(['add', 'volume', percent]);

  /// Sets the volume to [percent], 0–[MpvLaunchConfig.maxVolume].
  Future<void> setVolume(double percent) => _command([
    'set_property',
    'volume',
    percent.clamp(0, MpvLaunchConfig.maxVolume.toDouble()),
  ]);

  /// Mutes or unmutes the current mpv.
  Future<void> toggleMute() => _command(['cycle', 'mute']);

  /// Shows [bgra] (premultiplied BGRA, [width] × [height]) over the video
  /// as overlay [id], at [x], [y] in physical pixels of the video area.
  /// Replaces the previous image of [id]; kept across sessions until
  /// [hideOverlay].
  void showOverlay(
    int id, {
    required int x,
    required int y,
    required int width,
    required int height,
    required Uint8List bgra,
  }) {
    _overlays[id] = _Overlay(x, y, width, height, bgra);
    if (_run case final run?) unawaited(_sendOverlay(run, id));
  }

  /// Removes overlay [id].
  void hideOverlay(int id) {
    if (_overlays.remove(id) == null) return;
    unawaited(_command(['overlay-remove', id]));
  }

  /// Sends the latest image of overlay [id] to [run]'s mpv, one at a time.
  ///
  /// mpv maps the file and reads it whenever it draws, so a new image is
  /// written to a temporary file and renamed over the old one: a file mpv
  /// still maps is never truncated (that would crash it).
  Future<void> _sendOverlay(_MpvRun run, int id) async {
    if (!run.overlaysSending.add(id)) {
      run.overlaysPending.add(id);
      return;
    }
    try {
      do {
        run.overlaysPending.remove(id);
        final overlay = _overlays[id];
        final dir = run.socketDir;
        final ipc = run.ipc;
        if (overlay == null || dir == null || ipc == null) return;
        final path = '${dir.path}/osd-$id.bgra';
        final tmp = File('$path.tmp');
        await tmp.writeAsBytes(overlay.bgra);
        await tmp.rename(path);
        await ipc.command([
          'overlay-add',
          id,
          overlay.x,
          overlay.y,
          path,
          0,
          'bgra',
          overlay.width,
          overlay.height,
          overlay.width * 4,
        ]);
        // Hidden meanwhile: don't leave the image up.
        if (!_overlays.containsKey(id)) {
          await ipc.command(['overlay-remove', id]);
        }
      } while (run.overlaysPending.contains(id));
    } on MpvIpcException {
      // mpv is gone; a new one gets the overlay after it starts.
    } on FileSystemException {
      // The socket directory is gone with its mpv.
    } finally {
      run.overlaysSending.remove(id);
    }
  }

  /// Selects audio track [id].
  Future<void> setAudioTrack(int id) => _command(['set_property', 'aid', id]);

  /// Selects subtitle track [id]; null turns subtitles off.
  Future<void> setSubtitleTrack(int? id) =>
      _command(['set_property', 'sid', id ?? 'no']);

  /// Loads a subtitle file (a local path or URL) into the current mpv and
  /// selects it. [path] may be secret (e.g. a download URL), so it is
  /// never logged. Returns false when mpv couldn't load it.
  Future<bool> addSubtitleFile(
    String path, {
    String? title,
    String? lang,
  }) async {
    final ipc = _run?.ipc;
    if (ipc == null) return false;
    try {
      await ipc.command([
        'sub-add',
        path,
        'select',
        if (title != null || lang != null) title ?? '',
        ?lang,
      ]);
      return true;
    } on MpvIpcException {
      return false;
    }
  }

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

/// An overlay image, see [ExternalMpvPlayer.showOverlay].
class _Overlay {
  const _Overlay(this.x, this.y, this.width, this.height, this.bgra);

  final int x;
  final int y;
  final int width;
  final int height;
  final Uint8List bgra;
}

/// The process, socket and socket directory of one session.
class _MpvRun {
  _MpvRun(this._quitTimeout);

  final Duration _quitTimeout;
  Process? process;
  MpvIpc? ipc;
  Directory? socketDir;

  /// Redacts the URL of the media playing now from mpv's messages.
  UrlRedactor redactor = UrlRedactor();

  /// Set once [close] was requested; resources acquired later are released
  /// by calling [close] again.
  bool closed = false;
  bool exited = false;
  Timer? statsTimer;
  bool polling = false;

  /// Overlay ids being sent, and those with a newer image waiting.
  final overlaysSending = <int>{};
  final overlaysPending = <int>{};

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
