import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/mpv/video_embed.dart';
import 'package:tvplayer/player/video_pointer.dart';

/// Records calls instead of starting mpv; tests drive [state] directly.
class FakeExternalPlayer extends ExternalMpvPlayer {
  final opened =
      <({Uri url, String title, int? wid, Duration? start, int? volume})>[];
  final stopped = <int?>[];
  var pauseToggles = 0;
  final seeks = <Duration>[];
  final volumeChanges = <int>[];
  final audioSelections = <int>[];
  final subtitleSelections = <int?>[];
  final volumeSets = <double>[];
  var muteToggles = 0;

  /// Overlays shown over the video, by id: the latest size and position.
  final overlays = <int, ({int x, int y, int width, int height})>{};

  @override
  int open(
    Uri url, {
    required String title,
    int? wid,
    Duration? start,
    int? volume,
  }) {
    opened.add((
      url: url,
      title: title,
      wid: wid,
      start: start,
      volume: volume,
    ));
    final session = state.session + 1;
    state = ExternalPlaybackState(
      session: session,
      status: ExternalPlayerStatus.starting,
    );
    return session;
  }

  @override
  Future<void> stop({int? session}) async => stopped.add(session);

  @override
  Future<void> togglePause() async => pauseToggles++;

  @override
  Future<void> seekBy(Duration offset) async => seeks.add(offset);

  @override
  Future<void> changeVolume(int percent) async => volumeChanges.add(percent);

  @override
  Future<void> setVolume(double percent) async {
    volumeSets.add(percent);
    state = state.copyWith(volume: percent);
  }

  @override
  Future<void> toggleMute() async {
    muteToggles++;
    state = state.copyWith(muted: !state.muted);
  }

  @override
  void showOverlay(
    int id, {
    required int x,
    required int y,
    required int width,
    required int height,
    required Uint8List bgra,
  }) => overlays[id] = (x: x, y: y, width: width, height: height);

  @override
  void hideOverlay(int id) => overlays.remove(id);

  @override
  Future<void> setAudioTrack(int id) async {
    audioSelections.add(id);
    state = state.copyWith(audioId: () => id);
  }

  @override
  Future<void> setSubtitleTrack(int? id) async {
    subtitleSelections.add(id);
    state = state.copyWith(subtitleId: () => id);
  }

  void emit(ExternalPlaybackState s) => state = s;
}

/// Native video area stand-in. With [failure], embedding is impossible.
class FakeVideoEmbed implements VideoEmbed {
  FakeVideoEmbed({this.failure});

  final String? failure;
  final rects = <Rect>[];
  final fullscreenCalls = <bool>[];
  var hides = 0;
  final cursorCalls = <bool>[];
  final _pointer = StreamController<VideoPointerEvent>.broadcast();
  final _fullscreen = StreamController<bool>.broadcast();

  /// A double click on the video at [at]: its two presses, then the double
  /// click, as the native side reports them.
  void doubleClick([Offset at = const Offset(100, 100)]) {
    _pointer
      ..add(VideoPointerDown(at))
      ..add(VideoPointerUp(at))
      ..add(VideoPointerDown(at))
      ..add(VideoDoubleClick(at))
      ..add(VideoPointerUp(at));
  }

  /// A single click on the video at [at].
  void click([Offset at = const Offset(100, 100)]) => _pointer
    ..add(VideoPointerDown(at))
    ..add(VideoPointerUp(at));

  void pointer(VideoPointerEvent event) => _pointer.add(event);

  void windowManagerFullscreen(bool v) => _fullscreen.add(v);

  @override
  Stream<VideoPointerEvent> get pointerEvents => _pointer.stream;

  @override
  Future<void> setCursorVisible(bool visible) async => cursorCalls.add(visible);

  @override
  Stream<bool> get fullscreenChanges => _fullscreen.stream;

  @override
  Future<int> create() async {
    if (failure case final f?) throw VideoEmbedException(f);
    return 0x3a00007;
  }

  @override
  Future<void> setRect(Rect rect) async => rects.add(rect);

  @override
  Future<void> hide() async => hides++;

  @override
  Future<void> setFullscreen(bool fullscreen) async =>
      fullscreenCalls.add(fullscreen);

  @override
  void dispose() {}
}
