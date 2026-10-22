import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/mpv/video_embed.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/player/mpv_player_screen.dart';

import 'helpers.dart';

/// Records calls instead of starting mpv; tests drive [state] directly.
class FakeExternalPlayer extends ExternalMpvPlayer {
  final opened = <({Uri url, String title, int? wid})>[];
  final stopped = <int?>[];
  var pauseToggles = 0;

  @override
  int open(Uri url, {required String title, int? wid}) {
    opened.add((url: url, title: title, wid: wid));
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

void main() {
  late FakeExternalPlayer player;
  late FakeVideoEmbed embed;

  Future<void> pumpAndOpenChannel(
    WidgetTester tester, {
    FakeVideoEmbed? videoEmbed,
    bool embedding = true,
  }) async {
    player = FakeExternalPlayer();
    embed = videoEmbed ?? FakeVideoEmbed();
    addTearDown(player.dispose);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(syntheticCatalog(count: 3)),
          ),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(embedding),
          videoEmbedProvider.overrideWithValue(embed),
        ],
        child: const Scaffold(body: LiveTvScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Channel 0001'));
    // Not pumpAndSettle: the progress bar animates while mpv starts.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  void play() => player.emit(
    player.state.copyWith(
      status: ExternalPlayerStatus.playing,
      position: () => const Duration(seconds: 75),
    ),
  );

  group('embedded', () {
    testWidgets('passes the native window id to mpv and tracks the video '
        'rect', (tester) async {
      await pumpAndOpenChannel(tester);
      expect(player.opened.single.wid, 0x3a00007);
      expect(player.opened.single.title, 'Channel 0001');

      final video = tester.getRect(find.byKey(const Key('mpv.video')));
      expect(embed.rects.last, video);
      // Controls sit below the video, not on it.
      final controls = tester.getRect(find.byTooltip('Stop'));
      expect(controls.top, greaterThanOrEqualTo(video.bottom));

      play();
      await tester.pump();
      expect(find.byKey(const Key('mpv.position')), findsOneWidget);
      expect(find.text('dropped (vo/dec): - / -'), findsOneWidget);
      player.emit(
        player.state.copyWith(voDrops: () => 3, decoderDrops: () => 0),
      );
      await tester.pump();
      expect(find.text('dropped (vo/dec): 3 / 0'), findsOneWidget);
      // In the controls bar, below the video.
      expect(
        tester.getRect(find.byKey(const Key('mpv.drops'))).top,
        greaterThanOrEqualTo(video.bottom),
      );
      await tester.tap(find.byTooltip('Pause'));
      expect(player.pauseToggles, 1);

      // Window resize moves the native area along.
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(
        embed.rects.last,
        tester.getRect(find.byKey(const Key('mpv.video'))),
      );
      expect(embed.rects.last, isNot(video));
    });

    testWidgets('fullscreen via button, double-click and Esc', (tester) async {
      await pumpAndOpenChannel(tester);
      play();
      await tester.pump();

      await tester.tap(find.byTooltip(RegExp('^Fullscreen')));
      await tester.pumpAndSettle();
      expect(embed.fullscreenCalls, [true]);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('Stop'), findsNothing);
      final screen =
          Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(embed.rects.last, screen);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(embed.fullscreenCalls, [true, false]);
      expect(find.byType(AppBar), findsOneWidget);

      embed.doubleClick();
      await tester.pumpAndSettle();
      expect(embed.fullscreenCalls, [true, false, true]);

      // The window manager leaving fullscreen brings the controls back.
      embed.windowManagerFullscreen(false);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Stop'), findsOneWidget);
    });

    testWidgets('leaving stops mpv, hides the area and ends fullscreen', (
      tester,
    ) async {
      await pumpAndOpenChannel(tester);
      play();
      await tester.pump();
      embed.doubleClick();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stop'));
      await tester.pumpAndSettle();
      expect(find.byType(MpvPlayerScreen), findsNothing);
      expect(player.stopped, [player.state.session]);
      expect(embed.hides, greaterThan(0));
    });

    testWidgets('mpv exiting returns to the channel list', (tester) async {
      await pumpAndOpenChannel(tester);
      play();
      await tester.pump();
      player.emit(player.state.copyWith(status: ExternalPlayerStatus.exited));
      await tester.pumpAndSettle();
      expect(find.byType(MpvPlayerScreen), findsNothing);
      expect(find.text('Channel 0001'), findsOneWidget);
    });

    testWidgets('errors replace the video and stay until dismissed', (
      tester,
    ) async {
      await pumpAndOpenChannel(tester);
      player.emit(
        player.state.copyWith(
          status: ExternalPlayerStatus.failed,
          error: 'mpv is not installed.',
        ),
      );
      await tester.pumpAndSettle();
      expect(embed.hides, greaterThan(0));
      expect(find.byKey(const Key('mpv.video')), findsNothing);
      expect(find.text('mpv is not installed.'), findsOneWidget);

      await tester.tap(find.text('Back to channels'));
      await tester.pumpAndSettle();
      expect(find.byType(MpvPlayerScreen), findsNothing);
    });
  });

  group('separate window', () {
    testWidgets('falls back when embedding is impossible', (tester) async {
      final logs = <String?>[];
      final oldDebugPrint = debugPrint;
      debugPrint = (m, {wrapWidth}) => logs.add(m);
      try {
        await pumpAndOpenChannel(
          tester,
          videoEmbed: FakeVideoEmbed(failure: 'Not running on X11'),
        );
      } finally {
        debugPrint = oldDebugPrint;
      }
      expect(player.opened.single.wid, isNull);
      expect(find.byKey(const Key('mpv.video')), findsNothing);
      expect(find.text('Starting mpv…'), findsOneWidget);
      expect(logs.single, contains('Not running on X11'));
      expect(logs.single, isNot(contains('192.0.2.1')));

      play();
      await tester.pump();
      expect(find.text('Playing in the mpv window'), findsOneWidget);
      player.emit(
        player.state.copyWith(voDrops: () => 0, decoderDrops: () => 0),
      );
      await tester.pump();
      expect(find.text('dropped (vo/dec): 0 / 0'), findsOneWidget);
      player.emit(player.state.copyWith(status: ExternalPlayerStatus.exited));
      await tester.pumpAndSettle();
      expect(find.byType(MpvPlayerScreen), findsNothing);
    });

    testWidgets('embedding can be turned off', (tester) async {
      await pumpAndOpenChannel(tester, embedding: false);
      expect(player.opened.single.wid, isNull);
      expect(embed.rects, isEmpty);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(player.stopped, [player.state.session]);
    });
  });
}
