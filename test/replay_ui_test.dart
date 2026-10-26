import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/data/archive_epg_repository.dart';
import 'package:tvplayer/state/archive_listings.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/epg/guide_screen.dart';
import 'package:tvplayer/ui/epg/programme_panel.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
import 'package:tvplayer/ui/player/player_controls.dart';
import 'package:tvplayer/ui/theme/app_colors.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

/// 19:00 CET on Monday 26 October 2026, the day after summer time ended.
final _now = DateTime.utc(2026, 10, 26, 18);

DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);

EpgProgram _p(String channel, String title, DateTime start, DateTime stop) =>
    EpgProgram(
      channelId: channel,
      title: title,
      start: start,
      stop: stop,
      description: 'About $title',
    );

final _catalog = LiveCatalog(
  categories: const [Category(id: 'c', name: 'Sweden')],
  channels: const [
    LiveStream(
      id: '1',
      name: 'SE: Kanal 1 HD ◉',
      categoryIds: ['c'],
      epgChannelId: 'k1.example',
      archiveDays: 3,
    ),
    // The provider's ◉ without archive: kept, no mark of the app.
    LiveStream(
      id: '2',
      name: 'Kanal 2 ◉',
      categoryIds: ['c'],
      epgChannelId: 'k2.example',
    ),
    LiveStream(
      id: '3',
      name: 'Kanal 3',
      categoryIds: ['c'],
      epgChannelId: 'k3.example',
      archiveDays: 1,
    ),
  ],
);

EpgGuide _guide() => EpgGuide(
  programs: {
    for (final id in ['k1', 'k2', 'k3'])
      '$id.example': [
        _p('$id.example', 'Morning $id', _at(26, 6), _at(26, 8)),
        _p('$id.example', 'Afternoon $id', _at(26, 17, 15), _at(26, 17, 50)),
        _p('$id.example', 'Evening $id', _at(26, 17, 50), _at(26, 18, 30)),
        _p('$id.example', 'Late $id', _at(26, 18, 30), _at(26, 20)),
      ],
  },
  fetchedAt: _now.subtract(const Duration(hours: 1)),
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

/// My Live TV category with every channel.
FavouritesData _favourites() {
  var (data, _) = createCategory(
    FavouritesData.empty,
    kind: ContentKind.live,
    name: 'Mine',
    icon: 'star',
    now: _now,
    newId: () => 'live0',
  );
  for (final c in _catalog.channels) {
    data = setMembership(
      data,
      'live0',
      ItemRef(ContentKind.live, c.id),
      name: c.name,
      member: true,
      now: _now,
    );
  }
  return data;
}

int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Finder _program(String channelId, DateTime start) =>
    find.byKey(Key('guide.program.$channelId.${_seconds(start)}'));

Finder _replayIcon(String channelId, DateTime start) => find.descendant(
  of: _program(channelId, start),
  matching: find.byKey(const Key('guide.replay')),
);

/// Shows the panel of [program] of [channel] from a button.
class _PanelLauncher extends StatelessWidget {
  const _PanelLauncher(this.channel, this.program);

  final LiveStream channel;
  final EpgProgram program;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () =>
          showProgrammePanel(context, channel: channel, program: program),
      child: const Text('panel'),
    ),
  );
}

Widget _scaled(double scale, Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

void main() {
  late FakeLiveSource source;
  late FakeExternalPlayer player;
  late FakeVideoEmbed embed;
  late MemoryWatchStore watch;

  setUp(() {
    source = FakeLiveSource(_catalog, hasGuide: true);
    player = FakeExternalPlayer();
    embed = FakeVideoEmbed();
    watch = MemoryWatchStore();
  });

  tearDown(() => player.dispose());

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1.0,
    Size size = const Size(1600, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(source),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(true),
          videoEmbedProvider.overrideWithValue(embed),
        ],
        epg: FakeEpgRepository(cached: _guide()),
        favourites: MemoryFavouritesStore(_favourites()),
        watch: watch,
        now: _now,
        child: _scaled(scale, child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder markIn(String text) => find.descendant(
    of: find.ancestor(of: find.text(text), matching: find.byType(Row)).first,
    matching: find.byKey(const Key('replay.mark')),
  );

  group('replay mark on channels', () {
    for (final scale in [1.0, 1.4]) {
      testWidgets('Live TV at text scale $scale', (tester) async {
        await pump(
          tester,
          const Scaffold(body: LiveTvScreen()),
          scale: scale,
          size: const Size(1000, 700),
        );
        // The provider's ◉ gives way to the app's mark.
        expect(find.text('SE: Kanal 1 HD'), findsOneWidget);
        expect(find.text('SE: Kanal 1 HD ◉'), findsNothing);
        expect(markIn('SE: Kanal 1 HD'), findsOneWidget);
        expect(find.byTooltip('Replay: 3 days back'), findsOneWidget);
        expect(find.byTooltip('Replay: 1 day back'), findsOneWidget);
        // Without archive the name stays as the provider wrote it.
        expect(find.text('Kanal 2 ◉'), findsOneWidget);
        expect(markIn('Kanal 2 ◉'), findsNothing);
      });

      testWidgets('TV guide channel column at text scale $scale', (
        tester,
      ) async {
        await pump(
          tester,
          const Scaffold(body: GuideScreen()),
          scale: scale,
          size: const Size(1000, 700),
        );
        expect(find.text('SE: Kanal 1 HD'), findsOneWidget);
        expect(find.byTooltip('Replay: 3 days back'), findsOneWidget);
        expect(find.text('Kanal 2 ◉'), findsOneWidget);
      });
    }

    testWidgets('zap panel: the mark is named in the hint line', (
      tester,
    ) async {
      await pump(tester, _Launcher(LivePlayback(_catalog.channels[2])));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      player.emit(
        player.state.copyWith(status: ExternalPlayerStatus.playing, volume: 80),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(
        findPlayerTooltip('Watch SE: Kanal 1 HD · Replay: 3 days back'),
        findsOneWidget,
      );
      expect(findPlayerTooltip('Watch Kanal 2 ◉'), findsOneWidget);
    });
  });

  group('TV guide', () {
    Future<void> guide(WidgetTester tester, {double scale = 1.0}) => pump(
      tester,
      const Scaffold(body: GuideScreen()),
      scale: scale,
      size: const Size(1400, 800),
    );

    testWidgets('replayable programmes are marked, others dimmed', (
      tester,
    ) async {
      await guide(tester);
      // Ended and running on a channel with archive: replay icon.
      expect(_replayIcon('1', _at(26, 17, 15)), findsOneWidget);
      expect(_replayIcon('1', _at(26, 17, 50)), findsOneWidget);
      expect(_replayIcon('1', _at(26, 18, 30)), findsNothing);
      // Without archive: no icon; ended ones muted.
      expect(_replayIcon('2', _at(26, 17, 15)), findsNothing);
      final ended = tester.widget<Text>(
        find.descendant(
          of: _program('2', _at(26, 17, 15)),
          matching: find.text('Afternoon k2'),
        ),
      );
      expect(ended.style?.color, AppColors.textMuted);
      final running = tester.widget<Text>(
        find.descendant(
          of: _program('2', _at(26, 17, 50)),
          matching: find.text('Evening k2'),
        ),
      );
      expect(running.style?.color, isNot(AppColors.textMuted));
      expect(
        find.byTooltip('18:15–18:50  Afternoon k1 · Replay available'),
        findsOneWidget,
      );
      expect(find.byTooltip('18:15–18:50  Afternoon k2'), findsOneWidget);
    });

    testWidgets('an ended programme: Play replays it from its start', (
      tester,
    ) async {
      await guide(tester);
      await tester.tap(_program('1', _at(26, 17, 15)));
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammePanel), findsOneWidget);
      expect(find.text('Afternoon k1'), findsWidgets);
      expect(find.text('About Afternoon k1'), findsOneWidget);
      expect(
        find.text('SE: Kanal 1 HD · Mon 26 Oct 18:15–18:50'),
        findsOneWidget,
      );
      // Play has focus: Enter plays.
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilledButton>()
            ?.key,
        const Key('programme.play'),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ProgrammePanel), findsNothing);
      // 17:15 UTC is 18:15 in the provider's zone; 45 min recorded.
      expect(
        player.opened.single.url.path,
        '/timeshift/user/pass/46/2026-10-26:18-15/1.ts',
      );
      expect(player.opened.single.start, isNull);
    });

    testWidgets('a running programme: Watch live or Play from start', (
      tester,
    ) async {
      await guide(tester);
      await tester.tap(_program('1', _at(26, 17, 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('programme.watchLive')), findsOneWidget);
      await tester.tap(find.byKey(const Key('programme.playFromStart')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        player.opened.single.url.path,
        '/timeshift/user/pass/11/2026-10-26:18-50/1.ts',
      );
    });

    testWidgets('Watch live opens the live channel', (tester) async {
      await guide(tester);
      await tester.tap(_program('1', _at(26, 17, 50)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('programme.watchLive')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(player.opened.single.url.path, '/live/user/pass/1.ts');
    });

    testWidgets('without archive: on now plays live at once; the Menu key '
        'shows the panel; ended says why there is no Play', (tester) async {
      await guide(tester);
      await tester.tap(_program('2', _at(26, 17, 15)));
      await tester.pumpAndSettle();
      expect(
        find.text('No replay: this channel has no archive'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('programme.play')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammePanel), findsNothing);

      // Right click on the programme on now: the panel, not playback.
      await tester.tap(
        _program('2', _at(26, 17, 50)),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammePanel), findsOneWidget);
      expect(player.opened, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(_program('2', _at(26, 17, 50)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(player.opened.single.url.path, '/live/user/pass/2.ts');
    });

    testWidgets('keyboard: Enter or the Menu key on a programme', (
      tester,
    ) async {
      await guide(tester);
      final cell = find.descendant(
        of: _program('1', _at(26, 17, 15)),
        matching: find.byType(InkWell),
      );
      Focus.of(
        tester.element(
          find.descendant(of: cell, matching: find.byType(Tooltip)),
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammePanel), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammePanel), findsNothing);
    });

    testWidgets('too old for the archive, or not started', (tester) async {
      await pump(
        tester,
        _PanelLauncher(
          _catalog.channels[2],
          _p('k3.example', 'Old k3', _at(25, 6), _at(25, 7)),
        ),
      );
      await tester.tap(find.text('panel'));
      await tester.pumpAndSettle();
      expect(find.text('No replay: older than 1 day'), findsOneWidget);
      expect(find.byKey(const Key('programme.close')), findsOneWidget);
      await tester.tap(find.byKey(const Key('programme.close')));
      await tester.pumpAndSettle();

      await pump(
        tester,
        _PanelLauncher(
          _catalog.channels[0],
          _p('k1.example', 'Later k1', _at(26, 20), _at(26, 21)),
        ),
      );
      await tester.tap(find.text('panel'));
      await tester.pumpAndSettle();
      expect(find.text('Not started yet'), findsOneWidget);
    });

    testWidgets("the provider's flag: not in the archive", (tester) async {
      await pump(
        tester,
        _PanelLauncher(
          _catalog.channels[0],
          EpgProgram(
            channelId: 'k1.example',
            title: 'Missing',
            start: _at(26, 10),
            stop: _at(26, 11),
            archived: false,
          ),
        ),
      );
      await tester.tap(find.text('panel'));
      await tester.pumpAndSettle();
      expect(
        find.text("No replay: not in the provider's archive"),
        findsOneWidget,
      );
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('the panel fits at text scale $scale', (tester) async {
        await pump(
          tester,
          _PanelLauncher(
            _catalog.channels[0],
            EpgProgram(
              channelId: 'k1.example',
              title: 'A Programme With A Rather Long Title For The Panel',
              description: List.filled(80, 'A long description.').join(' '),
              category: 'Documentary',
              start: _at(26, 16),
              stop: _at(26, 17, 30),
            ),
          ),
          scale: scale,
          size: const Size(800, 500),
        );
        await tester.tap(find.text('panel'));
        await tester.pumpAndSettle();
        // Layout errors fail the test.
        expect(find.byKey(const Key('programme.play')), findsOneWidget);
        final panel = tester.getRect(find.byType(ProgrammePanel));
        expect(
          tester.getRect(find.byKey(const Key('programme.play'))).bottom,
          lessThanOrEqualTo(panel.bottom),
        );
      });

      testWidgets('marked guide at text scale $scale', (tester) async {
        await guide(tester, scale: scale);
        expect(_replayIcon('1', _at(26, 17, 15)), findsOneWidget);
      });
    }

    testWidgets('scrolling back loads past programmes, one channel at a time', (
      tester,
    ) async {
      source.archive['1'] = [
        EpgProgram(
          channelId: 'k1.example',
          title: 'Yesterday k1',
          start: _at(25, 20),
          stop: _at(25, 21),
          archived: true,
        ),
      ];
      final gate = source.archiveGate = Completer<void>();
      await guide(tester);
      expect(source.archiveRequests, isEmpty, reason: 'XMLTV covers the view');

      tester
          .state<GuideGridState>(find.byType(GuideGrid))
          .scrollToTime(_at(25, 21));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      // One at a time, nearest the middle of the view first; channel 2
      // has no archive.
      expect(source.archiveRequests, ['3']);
      expect(find.byKey(const Key('guide.past.1')), findsOneWidget);
      expect(find.byKey(const Key('guide.past.3')), findsOneWidget);
      expect(find.byKey(const Key('guide.past.2')), findsNothing);
      expect(find.text('Loading past programmes…'), findsNWidgets(2));

      source.archiveGate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(source.archiveRequests, ['3', '1']);
      expect(find.byKey(const Key('guide.past.1')), findsNothing);
      expect(_replayIcon('1', _at(25, 20)), findsOneWidget);
      expect(source.maxArchiveInFlight, 1);

      // Loaded: scrolling there again asks nothing.
      tester
          .state<GuideGridState>(find.byType(GuideGrid))
          .scrollToTime(_at(25, 20, 30));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(source.archiveRequests, ['3', '1']);
    });

    testWidgets('a failed download says so', (tester) async {
      source.failArchive = true;
      await guide(tester);
      tester
          .state<GuideGridState>(find.byType(GuideGrid))
          .scrollToTime(_at(25, 21));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load past programmes"), findsNWidgets(2));
    });
  });

  group('past listings loader', () {
    late MemoryArchiveEpgRepository repo;
    late ProviderContainer container;

    LiveStream channel(String id, {int days = 3}) =>
        LiveStream(id: id, name: 'Kanal $id', archiveDays: days);

    setUp(() {
      repo = MemoryArchiveEpgRepository();
      container = ProviderContainer(
        overrides: [
          liveSourceProvider.overrideWithValue(source),
          providerKeyProvider.overrideWithValue('test'),
          archiveEpgRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWith(() => FixedClock(_now)),
        ],
      );
      addTearDown(container.dispose);
    });

    ArchiveListingsController loader() =>
        container.read(archiveListingsProvider.notifier);

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('never two requests at once; channels no longer wanted are '
        'dropped', () async {
      container.read(archiveListingsProvider);
      final gate = source.archiveGate = Completer<void>();
      loader().want([channel('a'), channel('b'), channel('c')]);
      await settle();
      expect(source.archiveRequests, ['a']);
      expect(
        container.read(archiveListingsProvider).statusOf('b'),
        ArchiveStatus.loading,
      );
      // Scrolled on: b is no longer visible.
      loader().want([channel('c')]);
      expect(
        container.read(archiveListingsProvider).statusOf('b'),
        ArchiveStatus.none,
      );
      source.archiveGate = null;
      gate.complete();
      await settle();
      await settle();
      expect(source.archiveRequests, ['a', 'c']);
      expect(source.maxArchiveInFlight, 1);
    });

    test('needed now goes first', () async {
      container.read(archiveListingsProvider);
      final gate = source.archiveGate = Completer<void>();
      loader().want([channel('a'), channel('b')]);
      await settle();
      loader().need(channel('z'));
      source.archiveGate = null;
      gate.complete();
      for (var i = 0; i < 4; i++) {
        await settle();
      }
      expect(source.archiveRequests, ['a', 'z', 'b']);
    });

    test('keeps the past only, caches it and asks again after 12 h', () async {
      source.archive['a'] = [
        _p('k', 'Too old', _at(20, 10), _at(20, 11)),
        _p('k', 'Past', _at(26, 10), _at(26, 11)),
        _p('k', 'Future', _at(26, 19), _at(26, 20)),
      ];
      container.read(archiveListingsProvider);
      loader().want([channel('a')]);
      for (var i = 0; i < 3; i++) {
        await settle();
      }
      final entry = container.read(archiveListingsProvider).entries['a']!;
      expect(entry.programs.map((p) => p.title), ['Past']);
      loader().want([channel('a')]);
      await settle();
      expect(source.archiveRequests, ['a']);
      // Saved shortly after.
      await Future<void>.delayed(ArchiveListingsController.saveDelay);
      await settle();
      expect(repo.saved['test']?.keys, ['a']);

      container.read(clockProvider.notifier).state = _now.add(
        const Duration(hours: 12),
      );
      loader().want([channel('a')]);
      await settle();
      expect(source.archiveRequests, ['a', 'a']);
    });

    test('the disk cache is used; a failure waits five minutes', () async {
      repo.saved['test'] = {
        'a': ArchiveEntry(
          fetchedAt: _now.subtract(const Duration(hours: 1)),
          programs: [_p('k', 'Cached', _at(26, 10), _at(26, 11))],
        ),
      };
      container.read(archiveListingsProvider);
      await settle();
      loader().want([channel('a')]);
      await settle();
      expect(source.archiveRequests, isEmpty);
      expect(
        container.read(archiveListingsProvider).statusOf('a'),
        ArchiveStatus.loaded,
      );

      source.failArchive = true;
      loader().want([channel('b')]);
      for (var i = 0; i < 3; i++) {
        await settle();
      }
      expect(
        container.read(archiveListingsProvider).statusOf('b'),
        ArchiveStatus.failed,
      );
      loader().want([channel('b')]);
      await settle();
      expect(source.archiveRequests, ['b']);
      container.read(clockProvider.notifier).state = _now.add(
        ArchiveListingsController.retryAfter,
      );
      source.failArchive = false;
      loader().want([channel('b')]);
      for (var i = 0; i < 3; i++) {
        await settle();
      }
      expect(source.archiveRequests, ['b', 'b']);
      expect(
        container.read(archiveListingsProvider).statusOf('b'),
        ArchiveStatus.loaded,
      );
    });

    test('channels without replay are never asked for', () async {
      container.read(archiveListingsProvider);
      loader().want([channel('a', days: 0)]);
      await settle();
      expect(source.archiveRequests, isEmpty);
    });
  });

  group('replay player', () {
    final kanal1 = _catalog.channels[0];

    ReplayPlayback replay(DateTime from) => ReplayPlayback(
      kanal1,
      from: from,
      serverZone: 'Europe/Stockholm',
      requestedAt: _now,
    );

    Future<void> open(
      WidgetTester tester,
      PlaybackRequest request, {
      double scale = 1.0,
      Size size = const Size(1600, 900),
    }) async {
      await pump(tester, _Launcher(request), scale: scale, size: size);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    /// mpv reports [position] in the loaded stream of [length].
    Future<void> emit(
      WidgetTester tester, {
      Duration position = Duration.zero,
      Duration? length,
      bool eof = false,
      bool seekable = true,
    }) async {
      player.emit(
        player.state.copyWith(
          status: ExternalPlayerStatus.playing,
          position: () => position,
          duration: () => length,
          volume: 80,
          eofReached: eof,
          seekable: () => seekable,
        ),
      );
      await tester.pump();
    }

    void setClock(WidgetTester tester, DateTime t) =>
        (ProviderScope.containerOf(
          tester.element(find.byType(_Launcher, skipOffstage: false)),
        ).read(clockProvider.notifier) as FixedClock).set(t);

    testWidgets('plays the archive from the minute, then seeks to the second; '
        'clock time, REPLAY and the programme', (tester) async {
      await open(
        tester,
        replay(_at(26, 17, 15).add(const Duration(seconds: 30))),
      );
      final opened = player.opened.single;
      expect(opened.url.path, '/timeshift/user/pass/46/2026-10-26:18-15/1.ts');
      expect(opened.start, const Duration(seconds: 30));
      expect(opened.keepOpen, isTrue);

      await emit(
        tester,
        position: const Duration(minutes: 1),
        length: const Duration(minutes: 35),
      );
      expect(find.byKey(const Key('replay.badge')), findsOneWidget);
      expect(find.text('Afternoon k1 · SE: Kanal 1 HD'), findsOneWidget);
      expect(find.text('18:16:00'), findsOneWidget);
      // An ended programme: the bar covers it, no "behind live".
      expect(find.text('18:50'), findsOneWidget);
      expect(find.byKey(const Key('replay.behind')), findsNothing);
      expect(find.text('About Afternoon k1'), findsOneWidget);
    });

    testWidgets('seeking: inside the loaded stream, else from a new start; '
        'Shift seeks a minute', (tester) async {
      await open(tester, replay(_at(26, 17, 15)));
      await emit(
        tester,
        position: const Duration(minutes: 1),
        length: const Duration(minutes: 35),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(player.seeksTo, [const Duration(minutes: 1, seconds: 10)]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(player.seeksTo.last, Duration.zero);
      expect(player.reloaded, isEmpty);

      // Past the end of what was loaded: the archive from there.
      await emit(
        tester,
        position: const Duration(minutes: 34, seconds: 55),
        length: const Duration(minutes: 35),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final reload = player.reloaded.single;
      expect(reload.url.path, '/timeshift/user/pass/11/2026-10-26:18-50/1.ts');
      expect(reload.start, const Duration(seconds: 5));
      expect(reload.keepOpen, isTrue);
      expect(player.opened, hasLength(1), reason: 'one mpv, one stream');
      // While it loads the bar shows progress.
      expect(find.byKey(const Key('replay.loading')), findsOneWidget);
    });

    testWidgets('a stream mpv cannot seek in loads from a new start', (
      tester,
    ) async {
      await open(tester, replay(_at(26, 17, 15)));
      await emit(
        tester,
        position: const Duration(minutes: 1),
        length: const Duration(minutes: 35),
        seekable: false,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(player.seeksTo, isEmpty);
      expect(
        player.reloaded.single.url.path,
        '/timeshift/user/pass/45/2026-10-26:18-16/1.ts',
      );
      expect(player.reloaded.single.start, const Duration(seconds: 10));
    });

    testWidgets('behind live: the bar reaches now; seeking close to now goes '
        'live', (tester) async {
      await open(tester, replay(_at(26, 17, 50)));
      await emit(tester, length: const Duration(minutes: 10));
      expect(find.text('Behind live 10 min'), findsOneWidget);
      expect(find.text('Evening k1 · SE: Kanal 1 HD'), findsOneWidget);
      // From 17:00 (two hours back, display time) to now.
      expect(find.text('19:00'), findsOneWidget);

      await emit(
        tester,
        position: const Duration(minutes: 9, seconds: 55),
        length: const Duration(minutes: 10),
      );
      expect(find.text('Behind live 0:05'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(player.reloaded.single.url.path, '/live/user/pass/1.ts');
      expect(player.reloaded.single.keepOpen, isFalse);
    });

    testWidgets('the end of the archive behind live loads it again from '
        'there, without an error; again at once: live', (tester) async {
      await open(tester, replay(_at(26, 17, 50)));
      setClock(tester, _now.add(const Duration(seconds: 30)));
      await emit(
        tester,
        position: const Duration(minutes: 9),
        length: const Duration(minutes: 9),
        eof: true,
      );
      await tester.pump();
      final reload = player.reloaded.single;
      expect(reload.url.path, '/timeshift/user/pass/3/2026-10-26:18-59/1.ts');
      expect(reload.start, isNull);
      expect(find.text('Playback failed'), findsNothing);
      expect(find.byKey(const Key('replay.badge')), findsOneWidget);

      // Nothing more came: the end again right away.
      await emit(tester, eof: true);
      await tester.pump();
      expect(player.reloaded, hasLength(2));
      expect(player.reloaded.last.url.path, '/live/user/pass/1.ts');
      expect(player.opened, hasLength(1));
    });

    testWidgets('the end of the archive within 10 s of live: live', (
      tester,
    ) async {
      await open(tester, replay(_at(26, 17, 59)));
      setClock(tester, _now.add(const Duration(seconds: 30)));
      await emit(
        tester,
        position: const Duration(seconds: 82),
        length: const Duration(seconds: 82),
        eof: true,
      );
      await tester.pump();
      expect(player.reloaded.single.url.path, '/live/user/pass/1.ts');
      expect(find.byKey(const Key('replay.badge')), findsNothing);
    });

    testWidgets('Go live (button or l) plays the channel live here and '
        'counts it as viewed; no watch progress', (tester) async {
      await open(tester, replay(_at(26, 17, 15)));
      await emit(tester, length: const Duration(minutes: 35));
      expect(
        findPlayerTooltip('Go live: watch SE: Kanal 1 HD live (l)'),
        findsOneWidget,
      );
      expect(watch.data.channels, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(player.reloaded.single.url.path, '/live/user/pass/1.ts');
      expect(watch.data.channels.keys, ['1']);
      expect(watch.data.items, isEmpty);
      expect(find.byKey(const Key('player.goLive')), findsNothing);
    });

    testWidgets('the Go live button', (tester) async {
      await open(tester, replay(_at(26, 17, 15)));
      await emit(tester, length: const Duration(minutes: 35));
      await tester.tap(find.byKey(const Key('player.goLive')));
      await tester.pump();
      expect(player.reloaded.single.url.path, '/live/user/pass/1.ts');
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('the bar fits at text scale $scale', (tester) async {
        await open(
          tester,
          replay(_at(26, 17, 50)),
          scale: scale,
          size: const Size(1280, 720),
        );
        await emit(tester, length: const Duration(minutes: 10));
        // Layout errors fail the test.
        expect(find.byKey(const Key('replay.behind')), findsOneWidget);
        expect(find.byKey(const Key('player.goLive')), findsOneWidget);
        expect(findPlayerTooltip(PlayerSeekBar.tooltip), findsOneWidget);
      });
    }
  });
}
