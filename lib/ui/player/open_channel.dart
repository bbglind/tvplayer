import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../player/playback_request.dart';
import '../../state/downloads_controller.dart';
import '../../state/player_stream.dart';
import '../../state/playlist_refresh.dart';
import '../../state/providers.dart';
import 'mpv_player_screen.dart';
import 'touch_player_screen.dart';

/// Opens the player for [channel] and adds it to "Recently viewed
/// channels".
void openChannel(BuildContext context, WidgetRef ref, LiveStream channel) {
  ref.read(watchProvider.notifier).recordChannel(channel);
  openPlayback(context, ref, LivePlayback(channel));
}

/// Opens the player for [request], from the downloaded file when there is
/// one. Automatic playlist refresh waits until it is closed. Movies and
/// series remember it for "Last played".
///
/// The provider allows one stream at a time: while a download has it, this
/// asks "Pause the download?" first, and doesn't play on "Don't play". The
/// download continues when the player closes.
Future<void> openPlayback(
  BuildContext context,
  WidgetRef ref,
  PlaybackRequest request,
) async {
  request = withDownload(ref, request);
  final stream = ref.read(playerStreamProvider);
  if (stream.request(request) == StreamNeed.pauseDownload) {
    if (!await confirmPauseDownload(context, ref) || !context.mounted) return;
    ref.read(downloadsProvider.notifier).pauseForPlayback();
    stream.request(request);
  }
  if (switch (request) {
        MoviePlayback(:final movie) => movieKey(movie.streamId),
        EpisodePlayback(:final info) => seriesKey(info.series.seriesId),
        LivePlayback() || ReplayPlayback() || RecordingPlayback() => null,
      }
      case final key?) {
    ref.read(watchProvider.notifier).recordPlayed(key);
  }
  final playback = ref.read(playbackActiveProvider.notifier)..begin();
  try {
    await Navigator.of(context).push(playbackRoute(ref, request));
  } finally {
    playback.end();
    stream.release();
  }
}

/// [request] playing the downloaded file of its movie or episode, when
/// that is finished and still on disk.
PlaybackRequest withDownload(WidgetRef ref, PlaybackRequest request) {
  final downloads = ref.read(downloadsProvider.notifier);
  return switch (request) {
    MoviePlayback(localFile: null, :final watchKey) => request.withLocalFile(
      downloads.localFile(watchKey),
    ),
    EpisodePlayback(localFile: null, :final watchKey) => request.withLocalFile(
      downloads.localFile(watchKey),
    ),
    _ => request,
  };
}

/// Asks "Pause the download?" before playing from the provider while a
/// download has its one stream; true to pause it and play.
Future<bool> confirmPauseDownload(BuildContext context, WidgetRef ref) async {
  final text = pauseDownloadText(ref.read(downloadsProvider));
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('download.pauseForPlayback'),
      title: const Text('Pause the download?'),
      content: Text(text),
      actions: [
        TextButton(
          key: const Key('download.dontPlay'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Don't play"),
        ),
        FilledButton(
          key: const Key('download.pauseAndPlay'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Pause download'),
        ),
      ],
    ),
  );
  return yes == true;
}

/// The player route for [request]: mpv on Linux, the touch player (media_kit)
/// elsewhere.
Route<void> playbackRoute(WidgetRef ref, PlaybackRequest request) =>
    MaterialPageRoute<void>(
      builder: (_) => ref.read(useExternalMpvProvider)
          ? MpvPlayerScreen(request: request)
          : TouchPlayerScreen(request: request),
    );

/// The playback URL of [request], from the one source it needs. Contains
/// credentials: never log or show it.
Uri? playbackUrl(WidgetRef ref, PlaybackRequest request) => switch (request) {
  LivePlayback() ||
  ReplayPlayback() => request.url(live: ref.read(liveSourceProvider)),
  MoviePlayback() ||
  EpisodePlayback() => request.url(vod: ref.read(vodSourceProvider)),
  RecordingPlayback() => request.url(),
};
