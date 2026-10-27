import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../player/playback_request.dart';
import 'downloads_controller.dart';

/// What it takes for the player to play a request.
enum StreamNeed {
  /// It can play: it has the stream, or needs none.
  ready,

  /// A download has the stream; it plays once that is paused.
  pauseDownload,
}

/// The provider stream held by the player, from [streamGuardProvider].
/// One player is open at a time; switches inside it keep the stream, and
/// a downloaded file gives it back so downloads go on.
final playerStreamProvider = Provider<PlayerStream>(
  (ref) => PlayerStream(ref.watch(streamGuardProvider)),
);

class PlayerStream {
  PlayerStream(this._guard);

  final StreamGuard _guard;
  StreamLease? _lease;

  bool get holds => _lease != null && !_lease!.released;

  /// Takes the stream for [request] when it needs one and it is free (or
  /// held already); gives it back when [request] doesn't need it.
  StreamNeed request(PlaybackRequest request) {
    if (!request.usesProviderStream) {
      release();
      return StreamNeed.ready;
    }
    if (holds) return StreamNeed.ready;
    _lease = _guard.tryAcquire(StreamUse.playback);
    if (_lease != null) return StreamNeed.ready;
    // Only a download can hold it while the player asks.
    return _guard.holds(StreamUse.download)
        ? StreamNeed.pauseDownload
        : StreamNeed.ready;
  }

  void release() {
    _lease?.release();
    _lease = null;
  }
}

/// The question before playing while a download runs: its body text.
String pauseDownloadText(DownloadsState downloads) {
  final item = downloads.running;
  final name = item == null ? 'A download' : '“${downloadName(item)}”';
  final percent = switch (item?.fraction) {
    final f? => ' (${(f * 100).floor()} %)',
    null => '',
  };
  return 'Your provider allows one stream at a time. $name is '
      'downloading$percent. It continues when playback stops.';
}
