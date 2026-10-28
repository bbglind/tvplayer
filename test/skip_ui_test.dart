import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/service_credentials.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/state/skip.dart';
import 'package:tvplayer/state/tmdb.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
import 'package:tvplayer/ui/player/touch_player_screen.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'fake_touch_player.dart';
import 'helpers.dart';

final _t0 = DateTime.utc(2026, 10, 25, 19);

Duration _s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

Episode _ep(int season, int number) => Episode(
  id: '${season * 100 + number}',
  season: season,
  episodeNumber: number,
  title: 'Episode $season-$number',
  duration: const Duration(minutes: 40),
);

/// A series the provider sends with IMDb and TMDB ids (TMDB is off in
/// these tests).
const _series = Series(
  seriesId: 5,
  name: 'Test Show',
  imdbId: 'tt0000005',
  tmdbId: '55',
);

final _info = SeriesInfo(
  series: _series,
  seasons: const [],
  episodes: [_ep(1, 1), _ep(1, 2), _ep(2, 1)],
);

final _intro = SkipRange(_s(60), _s(150));
final _credits = SkipRange(_s(2300));

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
  group('lookup', () {
    late FakeSkip skip;

    ProviderContainer container({AppSettings settings = const AppSettings()}) {
      final c = ProviderContainer(
        overrides: [
          settingsStorageProvider.overrideWithValue(
            FakeSettingsStorage(settings),
          ),
          serviceCredentialsProvider.overrideWithValue(
            MemoryServiceCredentials(),
          ),
          skipDbApiProvider.overrideWithValue(skip.skipDbApi),
          introDbApiProvider.overrideWithValue(skip.introDbApi),
          skipStoreProvider.overrideWith((ref) => skip.store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => skip = FakeSkip());

    Future<SkipSegments> lookup(
      ProviderContainer c, {
      Series series = _series,
      Episode? episode,
      bool downloaded = false,
    }) async {
      await c.read(appSettingsProvider.future);
      return c
          .read(skipLookupProvider)
          .lookup(
            series,
            episode ?? _ep(1, 1),
            duration: const Duration(minutes: 40),
            downloaded: downloaded,
          );
    }

    test('SkipDB first, TheIntroDB for the types it lacks; only SkipDB '
        'is kept on disk', () async {
      skip.skipDb['1:1'] = SkipSegments(intro: _intro);
      skip.introDb['1:1'] = SkipSegments(
        intro: SkipRange(_s(0), _s(50)),
        credits: _credits,
      );
      final c = container();
      final times = await lookup(c);
      expect(times.intro, _intro);
      expect(times.credits, _credits);
      expect(skip.skipDbQueries.single.imdbId, 'tt0000005');
      expect(skip.skipDbQueries.first.duration, const Duration(minutes: 40));
      expect(skip.introDbQueries.single.tmdbId, 55);

      final stored = skip.store.get(
        'tt0000005',
        1,
        1,
        duration: const Duration(minutes: 40),
        now: DateTime.now().toUtc(),
      );
      expect(stored, SkipSegments(intro: _intro));

      // Again: SkipDB from disk, TheIntroDB from memory; nothing asked.
      expect(await lookup(c), times);
      expect(skip.skipDbQueries, hasLength(1));
      expect(skip.introDbQueries, hasLength(1));
    });

    test('TheIntroDB is not asked when SkipDB has every type', () async {
      skip.skipDb['1:1'] = SkipSegments(
        intro: _intro,
        recap: SkipRange(_s(0), _s(30)),
        credits: _credits,
      );
      await lookup(container());
      expect(skip.introDbQueries, isEmpty);
    });

    test('a service switched off is never asked', () async {
      await lookup(
        container(
          settings: const AppSettings(
            skipDbEnabled: false,
            introDbEnabled: false,
          ),
        ),
      );
      expect(skip.skipDbQueries, isEmpty);
      expect(skip.introDbQueries, isEmpty);

      await lookup(
        container(settings: const AppSettings(introDbEnabled: false)),
        episode: _ep(1, 2),
      );
      expect(skip.skipDbQueries, hasLength(1));
      expect(skip.introDbQueries, isEmpty);
    });

    test('downloaded episodes only use what is on disk', () async {
      skip.skipDb['1:1'] = SkipSegments(intro: _intro);
      final c = container();
      expect(await lookup(c, downloaded: true), SkipSegments.none);
      expect(skip.skipDbQueries, isEmpty);
      expect(skip.introDbQueries, isEmpty);

      skip.store.put(
        'tt0000005',
        1,
        1,
        SkipSegments(intro: _intro),
        duration: const Duration(minutes: 39),
        at: DateTime.utc(2020),
      );
      expect(await lookup(c, downloaded: true), SkipSegments(intro: _intro));
      expect(skip.skipDbQueries, isEmpty);
    });

    test('without an IMDb id only TheIntroDB is asked; without any id '
        'nothing, silently', () async {
      final c = container();
      await lookup(
        c,
        series: const Series(seriesId: 6, name: 'Other', tmdbId: '66'),
      );
      expect(skip.skipDbQueries, isEmpty);
      expect(skip.introDbQueries.single.tmdbId, 66);

      expect(
        await lookup(c, series: const Series(seriesId: 7, name: 'No ids')),
        SkipSegments.none,
      );
      expect(skip.skipDbQueries, isEmpty);
      expect(skip.introDbQueries, hasLength(1));
    });

    test('adding a download keeps SkipDB times for it', () async {
      skip.skipDb['1:2'] = SkipSegments(intro: _intro);
      final c = container();
      await c.read(appSettingsProvider.future);
      await c.read(skipLookupProvider).storeSkipDb(_series, _ep(1, 2));
      expect(skip.introDbQueries, isEmpty);
      expect(
        skip.store.get('tt0000005', 1, 2, now: _t0, anyAge: true),
        SkipSegments(intro: _intro),
      );
    });
  });

  test('both services are on by default; the old hidden switches are '
      'ignored', () {
    expect(const AppSettings().skipDbEnabled, isTrue);
    expect(const AppSettings().introDbEnabled, isTrue);
    final old = AppSettings.fromJson({
      'skipDbEnabled': false,
      'introDbEnabled': false,
    });
    expect(old.skipDbEnabled, isTrue);
    expect(old.introDbEnabled, isTrue);
    final off = AppSettings.fromJson(
      const AppSettings(skipDbEnabled: false).toJson(),
    );
    expect(off.skipDbEnabled, isFalse);
    expect(off.introDbEnabled, isTrue);
  });

  group('Settings', () {
    Future<
      ({
        FakeSettingsStorage settings,
        MemoryServiceCredentials keys,
        List<(SkipService, String?)> tests,
        List<Uri> opened,
      })
    >
    pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = FakeSettingsStorage();
      final keys = MemoryServiceCredentials();
      final tests = <(SkipService, String?)>[];
      final opened = <Uri>[];
      await tester.pumpWidget(
        testApp(
          overrides: [
            skipConnectionTesterProvider.overrideWithValue((
              service, {
              key,
            }) async {
              tests.add((service, key));
              return service == SkipService.introDb && key != null
                  ? SkipFailure.unauthorized
                  : null;
            }),
            linkOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          settings: settings,
          serviceCredentials: keys,
          child: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      return (settings: settings, keys: keys, tests: tests, opened: opened);
    }

    Future<void> show(WidgetTester tester, String key) async {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 300);
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('SkipDB and TheIntroDB: on/off and Test connection', (
      tester,
    ) async {
      final p = await pump(tester);
      await show(tester, 'settings.skipDb');
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('settings.skipDb.switch')))
            .value,
        isTrue,
      );
      await show(tester, 'settings.skipDbTest');
      await tester.tap(find.byKey(const Key('settings.skipDbTest')));
      await tester.pumpAndSettle();
      expect(find.text('Connected to SkipDB.'), findsOneWidget);
      expect(p.tests, [(SkipService.skipDb, null)]);

      await show(tester, 'settings.skipDb.switch');
      await tester.tap(find.byKey(const Key('settings.skipDb.switch')));
      await tester.pumpAndSettle();
      expect(p.settings.saved.skipDbEnabled, isFalse);
      // Off: not even a test.
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('settings.skipDbTest')),
            )
            .onPressed,
        isNull,
      );

      await show(tester, 'settings.introDbTest');
      await tester.tap(find.byKey(const Key('settings.introDbTest')));
      await tester.pumpAndSettle();
      expect(find.text('Connected to TheIntroDB.'), findsOneWidget);
    });

    testWidgets('TheIntroDB key: enter, test with it, remove', (tester) async {
      final p = await pump(tester);
      await show(tester, 'settings.introDbKey');
      expect(
        find.text('Not set. A key of your own raises the daily limit.'),
        findsOneWidget,
      );
      await show(tester, 'settings.introDbKey.enter');
      await tester.tap(find.byKey(const Key('settings.introDbKey.enter')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings.introDbKey.field')),
        ' my-key ',
      );
      await tester.tap(find.byKey(const Key('settings.introDbKey.save')));
      await tester.pumpAndSettle();
      expect(p.keys.values[MetadataService.introDb], 'my-key');
      expect(find.text('Saved in the system keyring.'), findsOneWidget);
      expect(find.text('my-key'), findsNothing);

      await show(tester, 'settings.introDbTest');
      await tester.tap(find.byKey(const Key('settings.introDbTest')));
      await tester.pumpAndSettle();
      expect(p.tests.last, (SkipService.introDb, 'my-key'));
      expect(
        find.text(
          "TheIntroDB didn't accept this key. Check that you copied all of "
          'it.',
        ),
        findsOneWidget,
      );

      await show(tester, 'settings.introDbKey.remove');
      await tester.tap(find.byKey(const Key('settings.introDbKey.remove')));
      await tester.pumpAndSettle();
      expect(p.keys.values.containsKey(MetadataService.introDb), isFalse);
    });

    testWidgets('About credits SkipDB (ODbL) and TheIntroDB with links', (
      tester,
    ) async {
      final p = await pump(tester);
      await show(tester, 'settings.about.introDbLink');
      expect(
        find.text(
          'SkipDB data © SkipDB contributors, available under the Open '
          'Database License (ODbL) 1.0.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('settings.about.skipDbLink')));
      await tester.tap(find.byKey(const Key('settings.about.odblLink')));
      await tester.tap(find.byKey(const Key('settings.about.introDbLink')));
      await tester.pump();
      expect(p.opened, [
        Uri.parse('https://skipdb.tv'),
        Uri.parse('https://opendatacommons.org/licenses/odbl/1-0/'),
        Uri.parse('https://theintrodb.org'),
      ]);
    });
  });

  group('desktop player', () {
    late FakeExternalPlayer player;
    late FakeSkip skip;

    Future<void> open(
      WidgetTester tester,
      PlaybackRequest request, {
      AppSettings settings = const AppSettings(),
    }) async {
      player = FakeExternalPlayer();
      skip = FakeSkip()
        ..skipDb['1:1'] = SkipSegments(intro: _intro, credits: _credits);
      addTearDown(player.dispose);
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          overrides: [
            vodSourceProvider.overrideWithValue(FakeVodSource()),
            providerKeyProvider.overrideWithValue('test'),
            useExternalMpvProvider.overrideWithValue(true),
            externalMpvProvider.overrideWithValue(player),
            embedMpvProvider.overrideWithValue(true),
            videoEmbedProvider.overrideWithValue(FakeVideoEmbed()),
          ],
          settings: FakeSettingsStorage(settings),
          skip: skip,
          now: _t0,
          child: _Launcher(request),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> playTo(WidgetTester tester, num seconds) async {
      player.emit(
        player.state.copyWith(
          status: ExternalPlayerStatus.playing,
          position: () => _s(seconds),
          duration: () => const Duration(minutes: 40),
        ),
      );
      await tester.pump();
    }

    bool prominent(WidgetTester tester) =>
        tester.widget(find.byKey(const Key('player.skip'))) is FilledButton;

    testWidgets('Skip intro stands out, then stays in the bar; i skips', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 1)));
      await playTo(tester, 30);
      await tester.pump();
      expect(skip.skipDbQueries.first.duration, const Duration(minutes: 40));
      expect(find.byKey(const Key('player.skip')), findsNothing);
      // The next episode is asked for too, with the provider's length.
      expect(skip.skipDbQueries.last.episode, 2);

      for (var p = 58; p <= 62; p++) {
        await playTo(tester, p);
      }
      expect(find.text('Skip intro'), findsOneWidget);
      expect(prominent(tester), isTrue);
      expect(findPlayerTooltip('Skip intro (i)'), findsOneWidget);
      for (var p = 63; p <= 75; p++) {
        await playTo(tester, p);
      }
      expect(find.text('Skip intro'), findsOneWidget);
      expect(prominent(tester), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump();
      expect(player.seeksTo.last, _s(150));
      await playTo(tester, 150);
      expect(find.byKey(const Key('player.skip')), findsNothing);
    });

    testWidgets('fullscreen: stands out over the video with the controls '
        'hidden, then only with them', (tester) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 1)));
      await playTo(tester, 50);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      for (var p = 51; p <= 54; p++) {
        await playTo(tester, p);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(findPlayerTooltip('Stop and go back'), findsNothing);
      expect(find.byKey(const Key('player.skip')), findsNothing);

      for (var p = 55; p <= 61; p++) {
        await playTo(tester, p);
      }
      expect(findPlayerTooltip('Stop and go back'), findsNothing);
      expect(find.text('Skip intro'), findsOneWidget);
      expect(prominent(tester), isTrue);
      // Its image goes to mpv, at the bottom right.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final overlay = player.overlays[1];
      expect(overlay, isNotNull);
      expect(overlay!.y + overlay.height, 900);
      expect(overlay.x + overlay.width, 1600);

      for (var p = 62; p <= 72; p++) {
        await playTo(tester, p);
      }
      expect(find.byKey(const Key('player.skip')), findsNothing);
      // Shown again together with the controls.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.text('Skip intro'), findsOneWidget);
      expect(prominent(tester), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
    });

    testWidgets('seeking into the intro: only with the controls', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 1)));
      await playTo(tester, 10);
      await tester.pump();
      await playTo(tester, 100);
      expect(find.text('Skip intro'), findsOneWidget);
      expect(prominent(tester), isFalse);
    });

    testWidgets('the credits bring the next-episode card, 10 s', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 1)));
      await playTo(tester, 30);
      await tester.pump();
      await playTo(tester, 2299);
      expect(find.byKey(const Key('player.nextCard')), findsNothing);
      await playTo(tester, 2300);
      expect(find.text('Next episode in 10 s'), findsOneWidget);
      await playTo(tester, 2306);
      expect(find.text('Next episode in 4 s'), findsOneWidget);
      await playTo(tester, 2310);
      expect(player.opened.last.title, 'Test Show · S01E02 · Episode 1-2');
    });

    testWidgets('without credits times the set time applies; Off starts '
        'nothing', (tester) async {
      await open(
        tester,
        EpisodePlayback(_info, _ep(1, 2)),
        settings: const AppSettings(playNextSeconds: null),
      );
      await playTo(tester, 30);
      await tester.pump();
      await playTo(tester, 2390);
      expect(find.byKey(const Key('player.nextCard')), findsNothing);
      expect(player.opened, hasLength(1));
    });

    testWidgets('movies ask nothing', (tester) async {
      await open(
        tester,
        const MoviePlayback(
          Movie(streamId: 7, name: 'A Film', imdbId: 'tt0000007'),
        ),
      );
      await playTo(tester, 30);
      await tester.pump();
      expect(skip.skipDbQueries, isEmpty);
      expect(skip.introDbQueries, isEmpty);
    });
  });

  group('touch player', () {
    late FakeTouchPlayer player;

    Future<void> open(
      WidgetTester tester,
      PlaybackRequest request, {
      AppSettings settings = const AppSettings(),
    }) async {
      tester.view.physicalSize = const Size(892, 412);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      player = FakeTouchPlayer();
      final skip = FakeSkip()
        ..skipDb['1:1'] = SkipSegments(intro: _intro, credits: _credits);
      await tester.pumpWidget(
        testApp(
          overrides: [
            vodSourceProvider.overrideWithValue(FakeVodSource()),
            providerKeyProvider.overrideWithValue('test'),
            useExternalMpvProvider.overrideWithValue(false),
            touchPlayerFactoryProvider.overrideWithValue(
              ({required hwdec}) => player,
            ),
            deviceControlsProvider.overrideWithValue(FakeDeviceControls()),
          ],
          settings: FakeSettingsStorage(settings),
          skip: skip,
          now: _t0,
          child: _Launcher(request),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      player.start(at: _s(30), length: const Duration(minutes: 40));
      await tester.pump();
      await tester.pump();
    }

    Future<void> playTo(WidgetTester tester, num seconds) async {
      player.position = _s(seconds);
      player.emit();
      await tester.pump();
    }

    testWidgets('Skip intro over the video; a tap skips', (tester) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 1)));
      for (var p = 58; p <= 61; p++) {
        await playTo(tester, p);
      }
      expect(find.text('Skip intro'), findsOneWidget);
      await tester.tap(find.byKey(const Key('player.skip')));
      await tester.pump();
      expect(player.seeks.last, _s(150));
    });

    testWidgets('credits: card, countdown, then the next episode', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 1)));
      await playTo(tester, 2300);
      expect(find.text('Next episode in 10 s'), findsOneWidget);
      await playTo(tester, 2310);
      await tester.pump();
      expect(player.opened, hasLength(2));
      expect(find.byType(TouchPlayerScreen), findsOneWidget);
    });

    testWidgets('Cancel: the episode ends and the player closes', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 1)));
      await playTo(tester, 2300);
      await tester.tap(find.byKey(const Key('player.cancelNext')));
      await tester.pump();
      expect(find.byKey(const Key('player.nextCard')), findsNothing);
      player
        ..completed = true
        ..position = const Duration(minutes: 40);
      player.emit();
      await tester.pumpAndSettle();
      expect(player.opened, hasLength(1));
      expect(find.byType(TouchPlayerScreen), findsNothing);
    });

    testWidgets('Play next episode Off: the end closes the player', (
      tester,
    ) async {
      await open(
        tester,
        EpisodePlayback(_info, _ep(1, 2)),
        settings: const AppSettings(playNextSeconds: null),
      );
      player
        ..completed = true
        ..position = const Duration(minutes: 40);
      player.emit();
      await tester.pumpAndSettle();
      expect(player.opened, hasLength(1));
      expect(find.byType(TouchPlayerScreen), findsNothing);
    });

    testWidgets('the end of an episode plays the next one', (tester) async {
      await open(tester, EpisodePlayback(_info, _ep(1, 2)));
      player
        ..completed = true
        ..position = const Duration(minutes: 40);
      player.emit();
      await tester.pump();
      await tester.pump();
      expect(player.opened, hasLength(2));
    });
  });
}
