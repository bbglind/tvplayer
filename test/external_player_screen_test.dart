import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/player/external_player_screen.dart';

import 'helpers.dart';

/// Records calls instead of starting mpv; tests drive [state] directly.
class FakeExternalPlayer extends ExternalMpvPlayer {
  final opened = <(Uri, String)>[];
  final stopped = <int?>[];

  @override
  int open(Uri url, {required String title}) {
    opened.add((url, title));
    final session = state.session + 1;
    state = ExternalPlaybackState(
      session: session,
      status: ExternalPlayerStatus.starting,
    );
    return session;
  }

  @override
  Future<void> stop({int? session}) async => stopped.add(session);

  void emit(ExternalPlaybackState s) => state = s;
}

void main() {
  late FakeExternalPlayer player;

  Future<void> pumpAndOpenChannel(WidgetTester tester) async {
    player = FakeExternalPlayer();
    addTearDown(player.dispose);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(syntheticCatalog(count: 3)),
          ),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
        ],
        child: const Scaffold(body: LiveTvScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Channel 0001'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the channel in mpv and returns when mpv exits', (
    tester,
  ) async {
    await pumpAndOpenChannel(tester);
    expect(find.byType(ExternalPlayerScreen), findsOneWidget);
    expect(player.opened.single.$2, 'Channel 0001');
    expect(find.text('Starting mpv…'), findsOneWidget);

    player.emit(
      player.state.copyWith(
        status: ExternalPlayerStatus.playing,
        position: () => const Duration(seconds: 75),
      ),
    );
    await tester.pump();
    expect(find.text('Playing in the mpv window'), findsOneWidget);
    expect(find.byKey(const Key('external.position')), findsOneWidget);

    player.emit(player.state.copyWith(status: ExternalPlayerStatus.exited));
    await tester.pumpAndSettle();
    expect(find.byType(ExternalPlayerScreen), findsNothing);
    expect(find.text('Channel 0001'), findsOneWidget);
  });

  testWidgets('leaving the screen stops mpv', (tester) async {
    await pumpAndOpenChannel(tester);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.byType(ExternalPlayerScreen), findsNothing);
    expect(player.stopped, [player.state.session]);
  });

  testWidgets('shows launch errors and stays until dismissed', (tester) async {
    await pumpAndOpenChannel(tester);
    player.emit(
      player.state.copyWith(
        status: ExternalPlayerStatus.failed,
        error: 'mpv is not installed.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Playback failed'), findsOneWidget);
    expect(find.text('mpv is not installed.'), findsOneWidget);

    await tester.tap(find.text('Back to channels'));
    await tester.pumpAndSettle();
    expect(find.byType(ExternalPlayerScreen), findsNothing);
  });
}
