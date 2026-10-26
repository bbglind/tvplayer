import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../player/playback_request.dart';
import '../../player/tv_player_view.dart';
import '../../state/providers.dart';
import '../epg/now_next.dart';
import '../theme/app_colors.dart';
import '../favourites/favourite_menu.dart';
import 'open_channel.dart';

/// Full-screen playback with the embedded media_kit player (platforms
/// without the external mpv).
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.request});

  final PlaybackRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = playbackUrl(ref, request);
    final debug = ref.watch(playerDebugProvider);
    return Scaffold(
      backgroundColor: AppColors.scrim,
      appBar: AppBar(
        title: Text(request.title(ref.watch(providerTagsProvider))),
        actions: [
          if (request case LivePlayback(:final channel))
            FavouriteButton(item: liveItemRef(channel), name: channel.name),
          IconButton(
            tooltip: debug ? 'Hide debug info' : 'Show debug info',
            isSelected: debug,
            icon: const Icon(Icons.bug_report_outlined),
            selectedIcon: const Icon(Icons.bug_report),
            onPressed: ref.read(playerDebugProvider.notifier).toggle,
          ),
        ],
      ),
      body: url == null
          ? const Center(child: Text('No provider configured'))
          : Column(
              children: [
                Expanded(
                  child: TvPlayerView(
                    url: url,
                    hwdec: ref.watch(hwdecProvider),
                    hwdecModes: Hwdec.modes,
                    onHwdecChanged: ref.read(hwdecProvider.notifier).set,
                    showDebug: debug,
                    fixedLength: request.fixedLength,
                  ),
                ),
                if (request case LivePlayback(:final channel))
                  NowNextBar(channel: channel),
              ],
            ),
    );
  }
}
