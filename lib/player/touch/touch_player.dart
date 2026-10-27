import 'package:flutter/widgets.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../player_session.dart';

/// The player behind the touch player screen: what it shows and what it
/// can be asked to do. Track ids are mpv's, as in [MediaTrack].
abstract class TouchPlayer extends ChangeNotifier {
  /// Playing, not paused.
  bool get playing;

  /// Waiting for data.
  bool get buffering;

  /// The media is loaded: its length and tracks are known.
  bool get loaded;

  /// Reached the end of the media.
  bool get completed;
  Duration get position;

  /// Null or zero while unknown.
  Duration? get duration;
  bool get seekable;

  /// Already redacted; never contains the stream URL.
  String? get error;
  List<MediaTrack> get tracks;
  int? get audioId;

  /// Null: subtitles off.
  int? get subtitleId;

  /// The media_kit session for the debug info; null in tests.
  PlayerSession? get session => null;

  /// Opens [url] (contains credentials: never log or show it), from
  /// [start].
  Future<void> open(Uri url, {Duration? start});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setAudioTrack(int id);
  Future<void> setSubtitleTrack(int? id);
  void dismissError();

  /// The video picture.
  Widget buildVideo(BuildContext context);
}

/// Creates the [TouchPlayer] of one player screen, with the hwdec mode.
typedef TouchPlayerFactory = TouchPlayer Function({required String hwdec});
