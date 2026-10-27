import 'package:flutter/gestures.dart';
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
import 'package:tvplayer/ui/player/player_hint.dart';
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Loads the catalogues, as Home does in the app.
    ref.watch(providerTagsProvider);
    return Scaffold(
      body: TextButton(
        onPressed: () => openPlayback(context, ref, request),
        child: const Text('open'),
      ),
    );
  }
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
    FakeVodSource? vod,
    FakeVodRepository? vodCache,
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
          vodSourceProvider.overrideWithValue(vod ?? FakeVodSource()),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(true),
          videoEmbedProvider.overrideWithValue(embed),
        ],
        settings: settings,
        watch: watch,
        vod: vodCache,
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
      expect(find.byKey(const Key('player.pause')), findsNothing);
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

  testWidgets('the title shows the provider label; the full name is a hint', (
    tester,
  ) async {
    const series = Series(seriesId: 9, name: 'NF-DO - Bramble Lane (2025)');
    final info = SeriesInfo(
      series: series,
      seasons: const [],
      episodes: const [
        Episode(
          id: '91',
          season: 1,
          episodeNumber: 1,
          title: 'NF-DO - Bramble Lane (2025) - S01E01 - The Gate',
        ),
      ],
    );
    final catalog = VodCatalog.series(
      categories: const [],
      items: [
        series,
        for (var i = 0; i < 3; i++)
          Series(seriesId: i, name: 'NF-DO - Other $i'),
      ],
      fetchedAt: _t0,
    );
    await open(
      tester,
      EpisodePlayback(info, info.episodes.first),
      vod: FakeVodSource(series: catalog),
      // Cached, as it is before anything plays.
      vodCache: FakeVodRepository()..series['test'] = catalog,
    );
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.text('NF-DO')), findsOne);
    expect(
      find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.textSpan?.toPlainText() ?? '').endsWith(
                'Bramble Lane · S01E01 · The Gate',
              ),
        ),
      ),
      findsOne,
    );
    expect(
      findPlayerTooltip('NF-DO - Bramble Lane (2025) - S01E01 - The Gate'),
      findsOne,
    );
    expect(player.opened.single.title, startsWith('Bramble Lane · S01E01'));
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

    testWidgets('the Next episode button and n play the next episode here', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _info.episodes[0]));
      emit(position: const Duration(minutes: 10));
      await tester.pump();
      final button = find.byKey(const Key('player.nextEpisodeButton'));
      expect(button, findsOneWidget);
      expect(findPlayerTooltip('Play the next episode (n)'), findsOneWidget);

      await tester.tap(button);
      await tester.pump();
      expect(player.opened, hasLength(2));
      expect(player.opened.last.title, 'Test Show · S01E02 · Episode 1-2');
      expect(watch.data.episode('101')!.watched, isTrue);

      emit(position: const Duration(minutes: 5));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(player.opened, hasLength(3));
      expect(player.opened.last.title, 'Test Show · S02E01 · Episode 2-1');

      // The last episode has none; n does nothing.
      emit();
      await tester.pump();
      expect(button, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(player.opened, hasLength(3));
    });

    testWidgets('movies and live TV have no Next episode button', (
      tester,
    ) async {
      await open(tester, const MoviePlayback(_movie));
      emit();
      await tester.pump();
      expect(find.byKey(const Key('player.nextEpisodeButton')), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await open(tester, LivePlayback(_catalog.channels[0]));
      emit();
      await tester.pump();
      expect(find.byKey(const Key('player.nextEpisodeButton')), findsNothing);
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
      expect(findPlayerTooltip('Stop and go back'), findsOneWidget);
      // The bar is laid out over the bottom of the video.
      final stop = tester.getRect(findPlayerTooltip('Stop and go back'));
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
      expect(findPlayerTooltip('Stop and go back'), findsNothing);
      expect(embed.cursorCalls.last, isFalse);
      expect(player.overlays, isEmpty);
      expect(embed.rects.last, screen, reason: 'the video never shrinks');

      embed.pointer(const VideoPointerMove(Offset(10, 10)));
      await tester.pump();
      await tester.pump();
      expect(findPlayerTooltip('Stop and go back'), findsOneWidget);
      expect(embed.cursorCalls.last, isTrue);
      await tester.pump(const Duration(seconds: 2));
      embed.pointer(const VideoPointerMove(Offset(20, 10)));
      await tester.pump(const Duration(seconds: 2));
      expect(findPlayerTooltip('Stop and go back'), findsOneWidget);

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
      expect(findPlayerTooltip('Stop and go back'), findsOneWidget);
      expect(find.byKey(const Key('zap.channels')), findsOneWidget);
      // Live: the info strip is part of the overlay.
      expect(find.text('About show 0'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(findPlayerTooltip('Stop and go back'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    });

    testWidgets('after zapping with the keyboard the controls hide again', (
      tester,
    ) async {
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
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.opened.last.title, 'Channel 1');
      expect(find.byKey(const Key('zap.channels')), findsNothing);
      // The new channel's now/next shows, then everything hides.
      expect(find.text('About show 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(findPlayerTooltip('Stop and go back'), findsNothing);
      expect(embed.cursorCalls.last, isFalse);
      expect(embed.rects.last, Offset.zero & const Size(1600, 900));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    });

    testWidgets('after zapping with the mouse the controls hide again', (
      tester,
    ) async {
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
      await tester.pumpAndSettle();
      // In fullscreen clicks arrive through mpv's window.
      final row = tester.getCenter(find.byKey(const Key('zap.channel.1')));
      embed.pointer(VideoPointerMove(row));
      embed.pointer(VideoPointerDown(row));
      embed.pointer(VideoPointerUp(row));
      await settleClick(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.opened.last.title, 'Channel 1');
      expect(find.byKey(const Key('zap.channels')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(findPlayerTooltip('Stop and go back'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    });

    testWidgets('zapping in a window, then fullscreen: the controls hide', (
      tester,
    ) async {
      await open(
        tester,
        LivePlayback(_catalog.channels[0]),
        favourites: _favourites(),
      );
      emit();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zap.channel.1')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(player.opened.last.title, 'Channel 1');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(findPlayerTooltip('Stop and go back'), findsNothing);
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

  testWidgets('the episode control bar fits a small window at text scale '
      '1.4, windowed and fullscreen', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, EpisodePlayback(_info, _info.episodes[0]));
    tester.view.physicalSize = const Size(900, 600);
    emit(position: const Duration(minutes: 10), volume: 60);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player.nextEpisodeButton')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(find.byKey(const Key('player.nextEpisodeButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
  });

  group('tooltips', () {
    const window = Rect.fromLTWH(0, 0, 1600, 900);
    final hint = find.byKey(const Key('player.hint'));

    String? hintText(WidgetTester tester) => hint.evaluate().isEmpty
        ? null
        : tester
              .widget<Text>(
                find.descendant(of: hint, matching: find.byType(Text)),
              )
              .data;

    Future<TestGesture> mouse(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(800, 5));
      addTearDown(gesture.removePointer);
      return gesture;
    }

    /// Hovers every bar control (and the back arrow) and checks its hint
    /// shows below the bar, under the control and clear of the video.
    Future<Set<String>> hoverBar(
      WidgetTester tester,
      TestGesture gesture,
    ) async {
      final video = tester.getRect(find.byKey(const Key('mpv.video')));
      final rects = embed.rects.length;
      final controls = find.byWidgetPredicate(
        (w) => w is PlayerTooltip && !w.side,
      );
      final messages = <String>{};
      for (final element in controls.evaluate().toList()) {
        final message = (element.widget as PlayerTooltip).message;
        final target = tester.getRect(find.byWidget(element.widget));
        await gesture.moveTo(target.center);
        await tester.pump();
        expect(hintText(tester), message);
        final pill = tester.getRect(hint);
        expect(pill.overlaps(video), isFalse, reason: message);
        expect(window.contains(pill.topLeft), isTrue, reason: message);
        expect(window.contains(pill.bottomRight), isTrue, reason: message);
        expect(pill.left, lessThanOrEqualTo(target.center.dx));
        expect(pill.right, greaterThanOrEqualTo(target.center.dx));
        messages.add(message);
      }
      await gesture.moveTo(video.center);
      await tester.pump();
      expect(hint, findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('mpv.video'))),
        video,
        reason: 'hints never resize the video',
      );
      expect(embed.rects.length, rects);
      return messages;
    }

    /// Hovers [target] in a side panel and checks its tooltip stays clear
    /// of the video.
    Future<void> hoverSide(
      WidgetTester tester,
      TestGesture gesture,
      Finder target,
      String message,
    ) async {
      final video = tester.getRect(find.byKey(const Key('mpv.video')));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(seconds: 1));
      final tooltip = tester.getRect(find.text(message).last);
      expect(tooltip.overlaps(video), isFalse, reason: message);
      expect(tooltip.right, lessThanOrEqualTo(window.right), reason: message);
      await gesture.moveTo(video.center);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('windowed movie: every bar control has a hint below the bar, '
        'at text scale 1.4', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, const MoviePlayback(_movie));
      emit();
      await tester.pump();
      final gesture = await mouse(tester);
      expect(await hoverBar(tester, gesture), {
        'Back (stops playback)',
        'Pause (Space or click the video)',
        'Seek (← / →: 10 s, with Shift: 1 min)',
        'Show the time left (double-click or Enter)',
        'Mute (m)',
        'Volume (↑ / ↓, or the mouse wheel on the video)',
        'Subtitles and audio (s: next subtitles)',
        'Fullscreen (f or double-click, Esc to leave)',
        'Stop and go back',
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('windowed episode: Next episode, and the next-episode card '
        'keeps its tooltips beside the video', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, EpisodePlayback(_info, _info.episodes[0]));
      emit(position: const Duration(minutes: 39, seconds: 40));
      await tester.pump();
      final gesture = await mouse(tester);
      expect(
        await hoverBar(tester, gesture),
        contains('Play the next episode (n)'),
      );
      await hoverSide(
        tester,
        gesture,
        find.byKey(const Key('player.playNow')),
        'Play the next episode now (n)',
      );
      await hoverSide(
        tester,
        gesture,
        find.byKey(const Key('player.cancelNext')),
        'Cancel and play to the end (Esc)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('windowed live TV: bar hints, and the panels keep their '
        'tooltips beside the video', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(
        tester,
        LivePlayback(_catalog.channels[0]),
        favourites: _favourites(),
      );
      emit();
      await tester.pump();
      final gesture = await mouse(tester);
      expect(await hoverBar(tester, gesture), {
        'Back (stops playback)',
        'Mute (m)',
        'Volume (↑ / ↓, or the mouse wheel on the video)',
        'Channels: switch channel (c)',
        'Favourite: change my categories',
        'Subtitles and audio (s: next subtitles)',
        'Fullscreen (f or double-click, Esc to leave)',
        'Stop and go back',
      });

      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      await hoverSide(
        tester,
        gesture,
        find.byTooltip('Close (Esc)'),
        'Close (Esc)',
      );
      await hoverSide(
        tester,
        gesture,
        find.byKey(const Key('zap.tab.live0')),
        'Show the channels in News',
      );
      await hoverSide(
        tester,
        gesture,
        find.byKey(const Key('zap.channel.1')),
        'Watch Channel 1',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.tap(find.byKey(const Key('player.favourite')));
      await tester.pump();
      await hoverSide(
        tester,
        gesture,
        find.byKey(const Key('player.favourite.News')),
        'Remove from News',
      );
      await hoverSide(
        tester,
        gesture,
        find.byKey(const Key('player.favourite.create')),
        'Create the category and add this channel',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.tap(findPlayerTooltip(RegExp('^Subtitles')));
      await tester.pump();
      await hoverSide(
        tester,
        gesture,
        find.byKey(const Key('player.sub.off')),
        'Turn subtitles off',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard focus shows the hint', (tester) async {
      await open(tester, const MoviePlayback(_movie));
      emit();
      await tester.pump();
      expect(hint, findsNothing);
      for (var i = 0; i < 20 && hintText(tester) == null; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      final focused = FocusManager.instance.primaryFocus!.context!;
      final owner = focused.findAncestorWidgetOfExactType<PlayerTooltip>();
      expect(hintText(tester), owner!.message);
    });

    testWidgets('fullscreen: hints show in the bar drawn by mpv, also for '
        'panels, and go with the controls', (tester) async {
      await open(
        tester,
        LivePlayback(_catalog.channels[0]),
        favourites: _favourites(),
      );
      emit();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      final mute = tester.getCenter(find.byKey(const Key('player.mute')));
      embed.pointer(VideoPointerMove(mute));
      await tester.pump();
      await tester.pump();
      expect(hintText(tester), 'Mute (m)');
      final pill = tester.getRect(hint);
      expect(pill.bottom, lessThanOrEqualTo(window.bottom));
      expect(
        pill.top,
        greaterThan(
          tester.getRect(find.byKey(const Key('player.mute'))).bottom,
        ),
      );

      // Hidden controls take the hint with them.
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('player.mute')), findsNothing);
      expect(hint, findsNothing);
      embed.pointer(const VideoPointerMove(Offset(10, 10)));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('player.mute')), findsOneWidget);
      expect(hintText(tester), isNull);

      // Panel controls use the hint line too: their tooltips can't be
      // drawn by mpv.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      final close = tester.getCenter(findPlayerTooltip('Close (Esc)'));
      embed.pointer(VideoPointerMove(close));
      await tester.pump();
      await tester.pump();
      expect(hintText(tester), 'Close (Esc)');

      // Closing the panel takes its hint away (a frame later: the tree
      // is locked while it goes).
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('zap.channels')), findsNothing);
      expect(hintText(tester), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(embed.fullscreenCalls, [true, false]);
      expect(hintText(tester), isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
