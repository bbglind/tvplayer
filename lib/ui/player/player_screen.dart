import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../player/tv_player_view.dart';
import '../../state/providers.dart';
import '../epg/now_next.dart';

/// Full-screen playback of one live channel.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key, required this.channel});

  final LiveStream channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(liveSourceProvider);
    final debug = ref.watch(playerDebugProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(channel.name),
        actions: [
          IconButton(
            tooltip: debug ? 'Hide debug info' : 'Show debug info',
            isSelected: debug,
            icon: const Icon(Icons.bug_report_outlined),
            selectedIcon: const Icon(Icons.bug_report),
            onPressed: ref.read(playerDebugProvider.notifier).toggle,
          ),
        ],
      ),
      body: source == null
          ? const Center(child: Text('No provider configured'))
          : Column(
              children: [
                Expanded(
                  child: TvPlayerView(
                    url: source.streamUrl(channel),
                    hwdec: ref.watch(hwdecProvider),
                    hwdecModes: Hwdec.modes,
                    onHwdecChanged: ref.read(hwdecProvider.notifier).set,
                    showDebug: debug,
                  ),
                ),
                NowNextBar(channel: channel),
              ],
            ),
    );
  }
}
