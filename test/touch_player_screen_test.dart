import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
import 'package:tvplayer/ui/player/player_controls.dart';
import 'package:tvplayer/ui/player/touch_player_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_touch_player.dart';
import 'helpers.dart';

/// 19:00 CET on Monday 26 October 2026.
final _now = DateTime.utc(2026, 10, 26, 18);

/// A phone in landscape, in logical pixels.
const _phone = Size(892, 412);

final _catalog = LiveCatalog(
  categories: const [Category(id: 'c', name: 'Sweden')],
  channels: const [
    LiveStream(
      id: '1',
      name: 'SE: Kanal 1 HD ◉',
      categoryIds: ['c'],
      archiveDays: 3,
    ),
    LiveStream(id: '2', name: 'Kanal 2', categoryIds: ['c']),
  ],
);

const _film = Movie(streamId: 7, name: 'A Film');

/// Opens [request] from a button, like the app's screens do.
class _Launcher extends ConsumerWidget {
  const _Launcher(this.request);

  final PlaybackRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      onPressed: () => openPlayback(context, ref, request),
      child: const Text('open'),
    ),
  );
}

void main() {
  late FakeTouchPlayer player;
  late FakeDeviceControls device;

  Future<void> open(
    WidgetTester tester,
    PlaybackRequest request, {
    double scale = 1.0,
    AppSettings settings = const AppSettings(),
  }) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    player = FakeTouchPlayer();
    device = FakeDeviceControls();
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(FakeLiveSource(_catalog)),
          vodSourceProvider.overrideWithValue(
            FakeVodSource(
              movies: syntheticMovies(count: 1),
              series: syntheticSeries(count: 1),
            ),
          ),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(false),
          touchPlayerFactoryProvider.overrideWithValue(
            ({required hwdec}) => player,
          ),
          deviceControlsProvider.overrideWithValue(device),
        ],
        settings: FakeSettingsStorage(settings),
        now: _now,
        child: _Launcher(request),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(_Launcher, skipOffstage: false)),
  );

  double controlsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('player.controls')))
      .opacity;

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player.back')));
    await tester.pumpAndSettle();
  }

  /// A double tap at [x] on the video's middle line.
  Future<void> doubleTap(WidgetTester tester, double x) async {
    final at = Offset(x, _phone.height / 2);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(at);
    await tester.pump();
  }

  group('around the player', () {
    testWidgets('landscape fullscreen on open, portrait after Back', (
      tester,
    ) async {
      await open(tester, LivePlayback(_catalog.channels[1]));
      expect(find.byType(TouchPlayerScreen), findsOneWidget);
      expect(device.calls, ['enter']);
      expect(player.opened.single.url.path, '/live/user/pass/2.ts');
      await back(tester);
      expect(find.byType(TouchPlayerScreen), findsNothing);
      expect(device.calls, ['enter', 'leave']);
      expect(player.disposed, isTrue);
    });

    testWidgets('the title has no provider ◉; the replay mark shows', (
      tester,
    ) async {
      await open(tester, LivePlayback(_catalog.channels[0]));
      expect(find.textContaining('◉'), findsNothing);
      expect(find.text('SE: Kanal 1 HD'), findsOneWidget);
      expect(find.byKey(const Key('replay.mark')), findsOneWidget);
    });

    testWidgets('the debug button only with "Player debug info" on', (
      tester,
    ) async {
      await open(tester, LivePlayback(_catalog.channels[1]));
      expect(find.byKey(const Key('player.debugInfo')), findsNothing);
      container(tester).read(playerDebugProvider.notifier).set(true);
      await tester.pump();
      expect(find.byTooltip('Debug info'), findsOneWidget);
    });
  });

  group('controls', () {
    testWidgets('show on open, hide after 3 s; a tap shows and hides them', (
      tester,
    ) async {
      await open(tester, LivePlayback(_catalog.channels[1]));
      player.start();
      await tester.pump();
      expect(controlsOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 3));
      expect(controlsOpacity(tester), 0);

      await tester.tapAt(const Offset(446, 206));
      await tester.pump();
      expect(controlsOpacity(tester), 1);
      await tester.tapAt(const Offset(446, 206));
      await tester.pump();
      expect(controlsOpacity(tester), 0);
    });

    testWidgets('a seekable tap waits for a possible double tap', (
      tester,
    ) async {
      await open(tester, const MoviePlayback(_film));
      player.start(length: const Duration(minutes: 90));
      await tester.pump(const Duration(seconds: 3));
      expect(controlsOpacity(tester), 0);
      await tester.tapAt(const Offset(800, 206));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controlsOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controlsOpacity(tester), 1);
    });

    testWidgets('Subtitles and audio: preferred subtitles, then a choice; '
        'the controls stay while the panel is open', (tester) async {
      await open(tester, const MoviePlayback(_film));
      expect(find.byTooltip('No subtitles or other audio'), findsOneWidget);
      player.start(
        length: const Duration(minutes: 90),
        tracks: const [
          MediaTrack(id: 1, type: TrackType.audio, lang: 'eng'),
          MediaTrack(id: 1, type: TrackType.subtitle, lang: 'eng'),
          MediaTrack(id: 2, type: TrackType.subtitle, lang: 'swe'),
        ],
      );
      await tester.pump();
      // Swedish first in the default settings.
      expect(player.subtitleSelections, [2]);

      await tester.tap(find.byTooltip('Subtitles and audio'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player.sub.off')));
      await tester.pump();
      expect(player.subtitleSelections, [2, null]);
      await tester.pump(const Duration(seconds: 5));
      expect(controlsOpacity(tester), 1);

      // Closed by a tap beside the panel.
      await tester.tapAt(const Offset(20, 206));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player.sub.off')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(controlsOpacity(tester), 0);
      // A manual choice isn't overridden when tracks change.
      player.tracks = [
        ...player.tracks,
        const MediaTrack(id: 3, type: TrackType.subtitle, lang: 'swe'),
      ];
      player.emit();
      await tester.pump();
      expect(player.subtitleSelections, [2, null]);
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('the controls fit a phone at text scale $scale', (
        tester,
      ) async {
        await open(
          tester,
          const MoviePlayback(
            Movie(
              streamId: 7,
              name: 'A Film With A Very Long Title That Goes On And On',
            ),
          ),
          scale: scale,
        );
        player.start(length: const Duration(hours: 2, minutes: 5));
        await tester.pump();
        // Layout errors fail the test.
        expect(find.byKey(const Key('player.seek')), findsOneWidget);
        expect(find.byTooltip(PlayerSeekBar.touchTooltip), findsOneWidget);

        await back(tester);
        await open(
          tester,
          ReplayPlayback(
            _catalog.channels[0],
            from: _now.subtract(const Duration(minutes: 20)),
            serverZone: 'Europe/Stockholm',
            requestedAt: _now,
          ),
          scale: scale,
        );
        player.start(length: const Duration(minutes: 20));
        await tester.pump();
        expect(find.byKey(const Key('replay.behind')), findsOneWidget);
        expect(find.byKey(const Key('player.goLive')), findsOneWidget);
      });
    }
  });

  group('live TV', () {
    testWidgets('without archive: no pause, a double tap does not seek', (
      tester,
    ) async {
      await open(tester, LivePlayback(_catalog.channels[1]));
      player.start();
      await tester.pump();
      expect(find.byKey(const Key('player.livePause')), findsNothing);
      expect(find.byKey(const Key('player.pause')), findsNothing);
      await doubleTap(tester, 800);
      expect(player.seeks, isEmpty);
      expect(find.byKey(const Key('player.seekHint')), findsNothing);
    });

    testWidgets('with archive: pause, then resume from the archive 15 s '
        'before the pause; LIVE goes back', (tester) async {
      await open(tester, LivePlayback(_catalog.channels[0]));
      player.start();
      await tester.pump();
      await tester.tap(find.byTooltip('Pause live TV'));
      await tester.pump();
      expect(player.pauses, 1);
      expect(find.text('Paused · Behind live 0:15'), findsOneWidget);

      (container(tester).read(clockProvider.notifier) as FixedClock).set(
        _now.add(const Duration(seconds: 30)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Paused · Behind live 0:45'), findsOneWidget);

      await tester.tap(find.byTooltip('Resume'));
      await tester.pump();
      await tester.pump();
      final resume = player.opened.last;
      // Paused at 17:59:45 UTC: from 18:59 in the provider's zone, +45 s.
      expect(resume.url.path, '/timeshift/user/pass/3/2026-10-26:18-59/1.ts');
      expect(resume.start, const Duration(seconds: 45));
      expect(find.byKey(const Key('replay.badge')), findsOneWidget);
      // A replay seeks by double tap.
      player.start(
        at: const Duration(seconds: 45),
        length: const Duration(minutes: 2),
      );
      await tester.pump();
      await doubleTap(tester, 800);
      expect(player.seeks, [const Duration(seconds: 55)]);

      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('player.goLive')));
      await tester.pump();
      expect(player.opened.last.url.path, '/live/user/pass/1.ts');
      expect(find.byKey(const Key('live.paused')), findsNothing);
    });
  });

  group('movies', () {
    testWidgets('start at the saved position, save it on Back', (tester) async {
      await open(
        tester,
        const MoviePlayback(_film, start: Duration(minutes: 5)),
      );
      expect(player.opened.single.start, const Duration(minutes: 5));
      player.start(
        at: const Duration(minutes: 7),
        length: const Duration(minutes: 90),
      );
      await tester.pump();
      await back(tester);
      final saved = container(tester).read(watchProvider).items[movieKey(7)];
      expect(saved?.position, const Duration(minutes: 7));
      expect(saved?.duration, const Duration(minutes: 90));
    });

    testWidgets('double taps seek 10 s, more taps add up, with a hint', (
      tester,
    ) async {
      await open(tester, const MoviePlayback(_film));
      player.start(
        at: const Duration(minutes: 5),
        length: const Duration(minutes: 90),
      );
      await tester.pump();
      await doubleTap(tester, 800);
      await tester.tapAt(const Offset(800, 206));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(800, 206));
      await tester.pump();
      expect(player.seeks, const [
        Duration(minutes: 5, seconds: 10),
        Duration(minutes: 5, seconds: 20),
        Duration(minutes: 5, seconds: 30),
      ]);
      expect(find.text('+30 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('player.seekHint')), findsNothing);

      await doubleTap(tester, 100);
      expect(player.seeks.last, const Duration(minutes: 4, seconds: 50));
      expect(find.text('−10 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('at the end the player closes and the movie is watched', (
      tester,
    ) async {
      await open(tester, const MoviePlayback(_film));
      player.start(
        at: const Duration(minutes: 89),
        length: const Duration(minutes: 90),
      );
      await tester.pump();
      player
        ..completed = true
        ..playing = false
        ..emit();
      await tester.pumpAndSettle();
      expect(find.byType(TouchPlayerScreen), findsNothing);
      final saved = container(tester).read(watchProvider).items[movieKey(7)];
      expect(saved?.watched, isTrue);
    });
  });

  group('swipes', () {
    testWidgets('right half: media volume; left half: brightness of the '
        'window, back to the phone\'s on leaving', (tester) async {
      await open(tester, const MoviePlayback(_film));
      player.start(length: const Duration(minutes: 90));
      await tester.pump();

      await tester.dragFrom(const Offset(800, 300), const Offset(0, -150));
      await tester.pump();
      expect(device.volume, greaterThan(0.7));
      expect(device.volume, lessThan(0.9));
      expect(find.byKey(const Key('player.levelHint')), findsOneWidget);
      expect(find.text('${(device.volume * 100).round()} %'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('player.levelHint')), findsNothing);

      await tester.dragFrom(const Offset(100, 100), const Offset(0, 150));
      await tester.pump();
      expect(device.windowBrightness, lessThan(0.25));
      // Near the top edge it is the system's swipe.
      final volume = device.volume;
      await tester.dragFrom(const Offset(800, 20), const Offset(0, 150));
      await tester.pump(const Duration(seconds: 1));
      expect(device.volume, volume);
      // So is one at the side, where Android's back gesture starts.
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      await tester.dragFrom(Offset(width - 10, 200), const Offset(0, -150));
      await tester.pump();
      expect(device.volume, volume);

      await back(tester);
      expect(device.windowBrightness, isNull);
    });
  });
}
