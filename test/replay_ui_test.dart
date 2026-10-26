import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/epg/guide_screen.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
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
        _p('$id.example', 'Evening $id', _at(26, 17, 30), _at(26, 18, 30)),
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

  setUp(() {
    source = FakeLiveSource(_catalog, hasGuide: true);
    player = FakeExternalPlayer();
    embed = FakeVideoEmbed();
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
}
