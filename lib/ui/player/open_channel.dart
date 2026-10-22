import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import 'mpv_player_screen.dart';
import 'player_screen.dart';

/// Opens the player for [channel].
void openChannel(BuildContext context, WidgetRef ref, LiveStream channel) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ref.read(useExternalMpvProvider)
          ? MpvPlayerScreen(channel: channel)
          : PlayerScreen(channel: channel),
    ),
  );
}
