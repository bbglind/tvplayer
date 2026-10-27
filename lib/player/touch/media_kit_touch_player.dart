import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../player_session.dart';
import 'touch_player.dart';

/// [TouchPlayer] on media_kit (libmpv inside the app), as on Android.
///
/// Tracks come from mpv's `track-list`, so their ids and flags are the same
/// as with the desktop's mpv and the track choice works the same.
class MediaKitTouchPlayer extends TouchPlayer {
  MediaKitTouchPlayer({required String hwdec})
    : _session = PlayerSession(hwdec: hwdec) {
    final stream = _session.player.stream;
    _subscriptions.addAll([
      stream.playing.listen((_) => notifyListeners()),
      stream.buffering.listen((_) => notifyListeners()),
      stream.completed.listen((_) => notifyListeners()),
      stream.position.listen((_) => notifyListeners()),
      stream.duration.listen((d) {
        if (d > Duration.zero) _loaded = true;
        notifyListeners();
      }),
      stream.tracks.listen((_) => unawaited(_readTracks())),
      stream.track.listen((_) => unawaited(_readTracks())),
    ]);
    _session.addListener(notifyListeners);
  }

  final PlayerSession _session;
  final _subscriptions = <StreamSubscription<Object?>>[];
  List<MediaTrack> _tracks = const [];
  bool _loaded = false;
  bool _disposed = false;

  Player get _player => _session.player;

  @override
  PlayerSession get session => _session;

  @override
  bool get playing => _player.state.playing;

  @override
  bool get buffering => _player.state.buffering;

  @override
  bool get loaded => _loaded;

  @override
  bool get completed => _player.state.completed;

  @override
  Duration get position => _player.state.position;

  @override
  Duration? get duration => _player.state.duration;

  @override
  bool get seekable => _session.seekable;

  @override
  String? get error => _session.lastError;

  @override
  List<MediaTrack> get tracks => _tracks;

  @override
  int? get audioId => _selected(TrackType.audio);

  @override
  int? get subtitleId => _selected(TrackType.subtitle);

  int? _selected(TrackType type) =>
      _tracks.where((t) => t.type == type && t.selected).firstOrNull?.id;

  /// Reads mpv's track list, which also says which tracks are on.
  Future<void> _readTracks() async {
    final platform = _player.platform;
    if (platform is! NativePlayer || _disposed) return;
    List<MediaTrack> tracks;
    try {
      final list = jsonDecode(await platform.getProperty('track-list'));
      tracks = [
        if (list is List)
          for (final entry in list)
            if (entry is Map<String, Object?>) ?MediaTrack.fromMpvJson(entry),
      ];
    } catch (_) {
      // Disposed mid-read, or no list yet.
      return;
    }
    if (_disposed) return;
    _tracks = tracks;
    if (tracks.isNotEmpty) _loaded = true;
    notifyListeners();
  }

  @override
  Future<void> open(Uri url, {Duration? start}) {
    _tracks = const [];
    _loaded = false;
    return _session.open(url, start: start);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setAudioTrack(int id) => _setTrack('aid', '$id');

  @override
  Future<void> setSubtitleTrack(int? id) =>
      _setTrack('sid', id?.toString() ?? 'no');

  Future<void> _setTrack(String property, String value) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(property, value);
    } catch (_) {
      // Disposed meanwhile.
    }
    await _readTracks();
  }

  @override
  void dismissError() => _session.dismissError();

  @override
  Widget buildVideo(BuildContext context) => Video(
    controller: _session.videoController,
    controls: NoVideoControls,
    // Keeps the screen on while playing.
    wakelock: true,
  );

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _session.removeListener(notifyListeners);
    _session.dispose();
    super.dispose();
  }
}
