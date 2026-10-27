import 'package:flutter/material.dart';
import 'package:tvplayer/player/touch/device_controls.dart';
import 'package:tvplayer/player/touch/touch_player.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// Records calls instead of playing; tests set the state and [emit].
class FakeTouchPlayer extends TouchPlayer {
  final opened = <({Uri url, Duration? start})>[];
  final seeks = <Duration>[];
  final audioSelections = <int>[];
  final subtitleSelections = <int?>[];
  var pauses = 0;
  var plays = 0;
  var disposed = false;

  @override
  bool playing = false;
  @override
  bool buffering = false;
  @override
  bool loaded = false;
  @override
  bool completed = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration;
  @override
  bool seekable = false;
  @override
  String? error;
  @override
  List<MediaTrack> tracks = const [];
  @override
  int? audioId;
  @override
  int? subtitleId;

  void emit() => notifyListeners();

  /// Loaded and playing at [at] of [length].
  void start({
    Duration at = Duration.zero,
    Duration? length,
    List<MediaTrack> tracks = const [],
  }) {
    loaded = true;
    playing = true;
    seekable = length != null;
    position = at;
    duration = length;
    this.tracks = tracks;
    emit();
  }

  @override
  Future<void> open(Uri url, {Duration? start}) async {
    opened.add((url: url, start: start));
    loaded = false;
    completed = false;
    playing = false;
    position = Duration.zero;
    duration = null;
    tracks = const [];
  }

  @override
  Future<void> play() async {
    plays++;
    playing = true;
    emit();
  }

  @override
  Future<void> pause() async {
    pauses++;
    playing = false;
    emit();
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  @override
  Future<void> setAudioTrack(int id) async {
    audioSelections.add(id);
    audioId = id;
    emit();
  }

  @override
  Future<void> setSubtitleTrack(int? id) async {
    subtitleSelections.add(id);
    subtitleId = id;
    emit();
  }

  @override
  void dismissError() {
    error = null;
    emit();
  }

  @override
  Widget buildVideo(BuildContext context) =>
      const ColoredBox(color: Color(0xFF000000));

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// Records what the player asks of the phone.
class FakeDeviceControls implements DeviceControls {
  final calls = <String>[];
  double volume = 0.5;
  double systemBrightness = 0.4;

  /// The window's own brightness; null: the phone's.
  double? windowBrightness;

  @override
  Future<void> enterPlayer() async => calls.add('enter');

  @override
  Future<void> leavePlayer() async {
    calls.add('leave');
    windowBrightness = null;
  }

  @override
  Future<double?> mediaVolume() async => volume;

  @override
  Future<void> setMediaVolume(double level) async => volume = level;

  @override
  Future<double?> brightness() async => windowBrightness ?? systemBrightness;

  @override
  Future<void> setBrightness(double level) async => windowBrightness = level;
}
