import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../player/playback_request.dart';
import '../../state/providers.dart';
import 'mpv_player_screen.dart';
import 'player_screen.dart';

/// Opens the player for [channel] and adds it to "Recently viewed
/// channels".
void openChannel(BuildContext context, WidgetRef ref, LiveStream channel) {
  ref.read(watchProvider.notifier).recordChannel(channel);
  openPlayback(context, ref, LivePlayback(channel));
}

/// Opens the player for [request].
Future<void> openPlayback(
  BuildContext context,
  WidgetRef ref,
  PlaybackRequest request,
) => Navigator.of(context).push(playbackRoute(ref, request));

/// The player route for [request]: mpv on Linux, media_kit elsewhere.
Route<void> playbackRoute(WidgetRef ref, PlaybackRequest request) =>
    MaterialPageRoute<void>(
      builder: (_) => ref.read(useExternalMpvProvider)
          ? MpvPlayerScreen(request: request)
          : PlayerScreen(request: request),
    );

/// The playback URL of [request], from the one source it needs. Contains
/// credentials: never log or show it.
Uri? playbackUrl(WidgetRef ref, PlaybackRequest request) => switch (request) {
  LivePlayback() => request.url(live: ref.read(liveSourceProvider)),
  MoviePlayback() ||
  EpisodePlayback() => request.url(vod: ref.read(vodSourceProvider)),
};
