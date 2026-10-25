import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/player/video_pointer.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
import 'package:tvplayer/ui/theme/widgets.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

final _t0 = DateTime.utc(2026, 10, 25, 19);

Episode _ep(int season, int number) => Episode(
  id: '${season * 100 + number}',
  season: season,
  episodeNumber: number,
  title: 'Episode $season-$number',
  duration: const Duration(minutes: 40),
);

final _info = SeriesInfo(
  series: const Series(seriesId: 5, name: 'Test Show'),
  seasons: const [],
  episodes: [_ep(1, 1), _ep(1, 2), _ep(2, 1)],
);

const _movie = Movie(
  streamId: 7,
  name: 'Test Movie',
  containerExtension: 'mkv',
);

final _catalog = LiveCatalog(
  categories: const [Category(id: 'c', name: 'Sweden')],
  channels: [
    for (var i = 0; i < 4; i++)
      LiveStream(
        id: '$i',
        name: 'Channel $i',
        categoryIds: const ['c'],
        epgChannelId: 'k$i.example',
      ),
  ],
);

/// My Live TV categories News (channels 0, 1) and Sport (channels 2, 3).
FavouritesData _favourites() {
  var data = FavouritesData.empty;
  for (final (i, name) in ['News', 'Sport'].indexed) {
    (data, _) = createCategory(
      data,
      kind: ContentKind.live,
      name: name,
      icon: 'star',
      now: _t0,
      newId: () => 'live$i',
    );
  }
  for (final (i, (category, channel)) in [
    ('live0', 0),
    ('live0', 1),
    ('live1', 2),
    ('live1', 3),
  ].indexed) {
    data = setMembership(
      data,
      category,
      ItemRef(ContentKind.live, '$channel'),
      name: 'Channel $channel',
      member: true,
      now: _t0.add(Duration(minutes: i)),
    );
  }
  return data;
}

EpgGuide _guide() => EpgGuide(
  programs: {
    for (var i = 0; i < 4; i++)
      'k$i.example': [
        EpgProgram(
          channelId: 'k$i.example',
          title: 'Show $i',
          description: 'About show $i',
          start: _t0.subtract(const Duration(minutes: 30)),
          stop: _t0.add(const Duration(minutes: 30)),
        ),
        EpgProgram(
          channelId: 'k$i.example',
          title: 'Later $i',
          description: 'About later $i',
          start: _t0.add(const Duration(minutes: 30)),
          stop: _t0.add(const Duration(minutes: 90)),
        ),
      ],
  },
  displayNames: const {},
  fetchedAt: _t0,
);

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
  late FakeExternalPlayer player;
  late FakeVideoEmbed embed;
  late FakeSettingsStorage settings;
  late MemoryWatchStore watch;

  Future<void> open(
    WidgetTester tester,
    PlaybackRequest request, {
    AppSettings appSettings = const AppSettings(),
    FavouritesData? favourites,
  }) async {
    player = FakeExternalPlayer();
    embed = FakeVideoEmbed();
    settings = FakeSettingsStorage(appSettings);
    watch = MemoryWatchStore();
    addTearDown(player.dispose);
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(_catalog, hasGuide: true),
          ),
          vodSourceProvider.overrideWithValue(FakeVodSource()),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(true),
          videoEmbedProvider.overrideWithValue(embed),
        ],
        settings: settings,
        watch: watch,
        favourites: MemoryFavouritesStore(favourites),
        epg: FakeEpgRepository(cached: _guide()),
        now: _t0,
        child: _Launcher(request),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  void emit({
    Duration position = const Duration(minutes: 1),
    Duration? duration = const Duration(minutes: 40),
    double volume = 80,
    ExternalPlayerStatus status = ExternalPlayerStatus.playing,
    bool endedAtEof = false,
  }) => player.emit(
    player.state.copyWith(
      status: status,
      position: () => position,
      duration: () => duration,
      volume: volume,
      endedAtEof: endedAtEof,
    ),
  );

  /// Waits out the single-click delay.
  Future<void> settleClick(WidgetTester tester) =>
      tester.pump(VideoPointerDown.defaultDoubleClickTime);

  group('mouse on the video', () {
    testWidgets('movie: click pauses, double click is fullscreen only, the '
        'wheel changes the volume', (tester) async {
      await open(tester, const MoviePlayback(_movie));
      emit();
      await tester.pump();

      embed.click();
      await tester.pump();
      expect(player.pauseToggles, 0, reason: 'waits for a second click');
      await settleClick(tester);
      expect(player.pauseToggles, 1);

      embed.doubleClick();
      await settleClick(tester);
      await tester.pump();
      expect(embed.fullscreenCalls, [true]);
      expect(player.pauseToggles, 1);
      // Leave fullscreen again (the overlay keeps timers running).
      embed.doubleClick();
      await settleClick(tester);
      await tester.pump();
      expect(embed.fullscreenCalls, [true, false]);

      embed.pointer(const VideoScroll(Offset(100, 100), -1));
      embed.pointer(const VideoScroll(Offset(100, 100), 2));
      await tester.pump();
      expect(player.volumeChanges, [5, -10]);

      // A touchpad adds up fractions to a notch.
      for (var i = 0; i < 3; i++) {
        embed.pointer(const VideoScroll(Offset(100, 100), -0.4));
      }
      await tester.pump();
      expect(player.volumeChanges, [5, -10, 5]);
    });

    testWidgets('live TV: no pause by click, key or button', (tester) async {
      await open(tester, LivePlayback(_catalog.channels[0]));
      emit();
      await tester.pump();
      embed.click();
      await settleClick(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.pauseToggles, 0);
      expect(find.byTooltip('Pause'), findsNothing);
      expect(find.byKey(const Key('player.seek')), findsNothing);
    });
  });

  group('volume', () {
    testWidgets('starts at the saved volume; slider, mute and keys; the '
        'volume is remembered', (tester) async {
      await open(
        tester,
        const MoviePlayback(_movie),
        appSettings: const AppSettings(playerVolume: 40),
      );
      expect(player.opened.single.volume, 40);
      emit(volume: 40);
      await tester.pump();

      await tester.tap(find.byKey(const Key('player.mute')));
      await tester.pump();
      expect(player.muteToggles, 1);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(player.muteToggles, 2);

      // Click on the slider's right end: full volume.
      final slider = tester.getRect(find.byKey(const Key('player.volume')));
      await tester.tapAt(slider.centerRight - const Offset(4, 0));
      await tester.pump();
      expect(player.volumeSets.last, greaterThan(95));

      await tester.pump(const Duration(seconds: 2));
      expect(settings.saved.playerVolume, player.state.volume!.round());
    });
  });

  group('time and clock', () {
    testWidgets('double-clicking the end time shows the time left, and '
        'is remembered', (tester) async {
      await open(tester, const MoviePlayback(_movie));
      emit(position: const Duration(minutes: 10));
      await tester.pump();
      expect(find.text('40:00'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('player.clock'))).data,
        matches(RegExp(r'^\d\d:\d\d$')),
      );

      final end = find.byKey(const Key('player.endTime'));
      await tester.tap(end);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(find.text('-30:00'), findsOneWidget);
      expect(settings.saved.showRemainingTime, isTrue);
    });
  });

  group('live TV info', () {
    testWidgets('now and next show their descriptions', (tester) async {
      await open(tester, LivePlayback(_catalog.channels[0]));
      emit();
      await tester.pumpAndSettle();
      expect(find.text('Show 0'), findsOneWidget);
      expect(find.text('About show 0'), findsOneWidget);
      expect(find.text('About later 0'), findsOneWidget);
    });
  });

  group('zap', () {
    testWidgets('c opens my categories; choosing a channel plays it here', (
      tester,
    ) async {
      await open(
        tester,
        LivePlayback(_catalog.channels[1]),
        favourites: _favourites(),
      );
      emit();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player.zap')), findsWidgets);
      // Opens on the category with the current channel.
      expect(find.byKey(const Key('zap.channel.0')), findsOneWidget);
      expect(find.byKey(const Key('zap.channel.2')), findsNothing);
      // The current channel has focus.
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<AppTile>()
            ?.key,
        const Key('zap.channel.1'),
      );

      await tester.tap(find.byKey(const Key('zap.tab.live1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zap.channel.2')), findsOneWidget);
      // The programme on now is shown.
      expect(find.text('Show 2 · until 20:30'), findsOneWidget);

      await tester.tap(find.byKey(const Key('zap.channel.3')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(player.opened, hasLength(2));
      expect(player.opened.last.title, 'Channel 3');
      expect(player.opened.last.wid, player.opened.first.wid);
      expect(find.text('Channel 3'), findsWidgets);
      // The panel closed; the channel counts as recently viewed.
      expect(find.byKey(const Key('zap.channels')), findsNothing);
      expect(watch.data.channels.keys, contains('3'));
    });

    testWidgets('keyboard: arrows and Enter switch channel', (tester) async {
      await open(
        tester,
        LivePlayback(_catalog.channels[0]),
        favourites: _favourites(),
      );
      emit();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(player.seeks, isEmpty);
      expect(player.volumeChanges, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(player.opened.last.title, 'Channel 1');
    });

    testWidgets('without my Live TV categories it shows a hint', (
      tester,
    ) async {
      await open(tester, LivePlayback(_catalog.channels[0]));
      emit();
      await tester.pump();
      await tester.tap(find.byKey(const Key('player.zap')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zap.hint')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zap.hint')), findsNothing);
    });
  });

  group('play next', () {
    testWidgets('counts down over the last 30 s; Play now plays the next '
        'season here', (tester) async {
      await open(tester, EpisodePlayback(_info, _info.episodes[1]));
      emit(position: const Duration(minutes: 39, seconds: 29));
      await tester.pump();
      expect(find.byKey(const Key('player.nextCard')), findsNothing);

      emit(position: const Duration(minutes: 39, seconds: 31));
      await tester.pump();
      expect(find.text('Next episode in 29 s'), findsOneWidget);
      expect(find.text('S02E01 · Episode 2-1'), findsOneWidget);
      emit(position: const Duration(minutes: 39, seconds: 45));
      await tester.pump();
      expect(find.text('Next episode in 15 s'), findsOneWidget);

      await tester.tap(find.byKey(const Key('player.playNow')));
      await tester.pump();
      expect(player.opened, hasLength(2));
      expect(player.opened.last.title, 'Test Show · S02E01 · Episode 2-1');
      expect(watch.data.episode('102')!.watched, isTrue);
      expect(find.byKey(const Key('player.nextCard')), findsNothing);
    });

    testWidgets('starts the next episode at 0 and at the end', (tester) async {
      await open(tester, EpisodePlayback(_info, _info.episodes[0]));
      emit(position: const Duration(minutes: 39, seconds: 50));
      await tester.pump();
      emit(position: const Duration(minutes: 40));
      await tester.pump();
      expect(player.opened.last.title, 'Test Show · S01E02 · Episode 1-2');

      // The second one ends without a 0 being seen.
      emit(position: const Duration(minutes: 39, seconds: 50));
      await tester.pump();
      emit(
        position: const Duration(minutes: 39, seconds: 50),
        endedAtEof: true,
        status: ExternalPlayerStatus.exited,
      );
      await tester.pump();
      await tester.pump();
      expect(player.opened, hasLength(3));
      expect(player.opened.last.title, 'Test Show · S02E01 · Episode 2-1');
    });

    testWidgets('Cancel (or Esc) keeps playing to the end, which offers '
        'the next episode', (tester) async {
      await open(tester, EpisodePlayback(_info, _info.episodes[1]));
      emit(position: const Duration(minutes: 39, seconds: 40));
      await tester.pump();
      await tester.pump();
      // "Play now" has focus, so Enter would play; Esc cancels.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const Key('player.nextCard')), findsNothing);
      emit(position: const Duration(minutes: 39, seconds: 50));
      await tester.pump();
      expect(find.byKey(const Key('player.nextCard')), findsNothing);

      emit(
        position: const Duration(minutes: 40),
        endedAtEof: true,
        status: ExternalPlayerStatus.exited,
      );
      await tester.pumpAndSettle();
      expect(find.text('Episode finished'), findsOneWidget);
      expect(player.opened, hasLength(1));
    });

    testWidgets('seeking back after Cancel brings the countdown back', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _info.episodes[1]));
      emit(position: const Duration(minutes: 39, seconds: 40));
      await tester.pump();
      await tester.tap(find.byKey(const Key('player.cancelNext')));
      await tester.pump();
      emit(position: const Duration(minutes: 30));
      await tester.pump();
      emit(position: const Duration(minutes: 39, seconds: 40));
      await tester.pump();
      expect(find.text('Next episode in 20 s'), findsOneWidget);
    });

    testWidgets('off: no countdown; the last episode has none', (tester) async {
      await open(
        tester,
        EpisodePlayback(_info, _info.episodes[1]),
        appSettings: const AppSettings().copyWith(playNextSeconds: () => null),
      );
      emit(position: const Duration(minutes: 39, seconds: 40));
      await tester.pump();
      expect(find.byKey(const Key('player.nextCard')), findsNothing);
    });

    testWidgets('the last episode has no countdown', (tester) async {
      await open(tester, EpisodePlayback(_info, _info.episodes[2]));
      emit(position: const Duration(minutes: 39, seconds: 40));
      await tester.pump();
      expect(find.byKey(const Key('player.nextCard')), findsNothing);
    });
  });

  group('fullscreen overlay', () {
    testWidgets('controls show over the video on movement and hide after '
        '3 s, with the cursor', (tester) async {
      await open(tester, const MoviePlayback(_movie));
      emit();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      final screen = Offset.zero & const Size(1600, 900);
      expect(embed.rects.last, screen, reason: 'the video fills the screen');
      expect(find.byTooltip('Stop'), findsOneWidget);
      // The bar is laid out over the bottom of the video.
      final stop = tester.getRect(find.byTooltip('Stop'));
      expect(stop.bottom, lessThanOrEqualTo(screen.bottom));
      expect(stop.top, greaterThan(screen.center.dy));

      // Its image goes to mpv.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final overlay = player.overlays[1];
      expect(overlay, isNotNull);
      expect(overlay!.y + overlay.height, 900);
      expect(overlay.width, 1600);

      await tester.pump(const Duration(seconds: 3));
      expect(find.byTooltip('Stop'), findsNothing);
      expect(embed.cursorCalls.last, isFalse);
      expect(player.overlays, isEmpty);
      expect(embed.rects.last, screen, reason: 'the video never shrinks');

      embed.pointer(const VideoPointerMove(Offset(10, 10)));
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Stop'), findsOneWidget);
      expect(embed.cursorCalls.last, isTrue);
      await tester.pump(const Duration(seconds: 2));
      embed.pointer(const VideoPointerMove(Offset(20, 10)));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byTooltip('Stop'), findsOneWidget);

      // Clicks on the controls reach them, not the video.
      final mute = tester.getCenter(find.byKey(const Key('player.mute')));
      embed.pointer(VideoPointerDown(mute));
      embed.pointer(VideoPointerUp(mute));
      await settleClick(tester);
      expect(player.muteToggles, 1);
      expect(player.pauseToggles, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(embed.fullscreenCalls, [true, false]);
      expect(embed.cursorCalls.last, isTrue);
    });

    testWidgets('an open panel keeps the controls up', (tester) async {
      await open(
        tester,
        LivePlayback(_catalog.channels[0]),
        favourites: _favourites(),
      );
      emit();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byTooltip('Stop'), findsOneWidget);
      expect(find.byKey(const Key('zap.channels')), findsOneWidget);
      // Live: the info strip is part of the overlay.
      expect(find.text('About show 0'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byTooltip('Stop'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    });
  });

  testWidgets('fits at text scale 1.4', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(
      tester,
      LivePlayback(_catalog.channels[0]),
      favourites: _favourites(),
    );
    emit();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    await open(tester, EpisodePlayback(_info, _info.episodes[0]));
    emit(position: const Duration(minutes: 39, seconds: 40), volume: 60);
    await tester.pump();
    expect(find.byKey(const Key('player.nextCard')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
