import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/mpv/video_embed.dart';

/// Records calls instead of starting mpv; tests drive [state] directly.
class FakeExternalPlayer extends ExternalMpvPlayer {
  final opened = <({Uri url, String title, int? wid, Duration? start})>[];
  final stopped = <int?>[];
  var pauseToggles = 0;
  final seeks = <Duration>[];
  final volumeChanges = <int>[];
  final audioSelections = <int>[];
  final subtitleSelections = <int?>[];

  @override
  int open(Uri url, {required String title, int? wid, Duration? start}) {
    opened.add((url: url, title: title, wid: wid, start: start));
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
  final _doubleClicks = StreamController<void>.broadcast();
  final _fullscreen = StreamController<bool>.broadcast();

  void doubleClick() => _doubleClicks.add(null);
  void windowManagerFullscreen(bool v) => _fullscreen.add(v);

  @override
  Stream<void> get doubleClicks => _doubleClicks.stream;

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
