import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/state/downloads_controller.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/state/recording_controller.dart';
import 'package:tvplayer/ui/player/mpv_player_screen.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

/// 19:00 CET on Monday 26 October 2026.
final _now = DateTime.utc(2026, 10, 26, 18);

DateTime _at(int hour, [int minute = 0, int second = 0]) =>
    DateTime.utc(2026, 10, 26, hour, minute, second);

final _catalog = LiveCatalog(
  categories: const [Category(id: 'c', name: 'Sweden')],
  channels: const [
    LiveStream(
      id: '1',
      name: 'Kanal 1 ◉',
      categoryIds: ['c'],
      epgChannelId: 'k1.example',
      archiveDays: 3,
    ),
    LiveStream(id: '2', name: 'Kanal 2', categoryIds: ['c']),
  ],
);

EpgGuide _guide() => EpgGuide(
  programs: {
    'k1.example': [
      EpgProgram(
        channelId: 'k1.example',
        title: 'Evening news',
        start: _at(17, 50),
        stop: _at(18, 30),
      ),
    ],
  },
  fetchedAt: _now.subtract(const Duration(hours: 1)),
);

/// My Live TV category with both channels, for the Channels panel.
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
  late MemoryDownloadsStore downloads;
  late FakeFreeSpace freeSpace;

  setUp(() {
    player = FakeExternalPlayer();
    downloads = MemoryDownloadsStore();
    freeSpace = FakeFreeSpace();
  });
  tearDown(() => player.dispose());

  Future<void> open(
    WidgetTester tester, {
    LiveStream? channel,
    AppSettings settings = const AppSettings(),
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(_catalog, hasGuide: true),
          ),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(true),
          videoEmbedProvider.overrideWithValue(FakeVideoEmbed()),
        ],
        epg: FakeEpgRepository(cached: _guide()),
        favourites: MemoryFavouritesStore(_favourites()),
        settings: FakeSettingsStorage(settings),
        downloads: downloads,
        freeSpace: freeSpace,
        now: _now,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: _Launcher(LivePlayback(channel ?? _catalog.channels[0])),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    player.emit(player.state.copyWith(status: ExternalPlayerStatus.playing));
    await tester.pump();
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MpvPlayerScreen)));

  FixedClock clock(WidgetTester tester) =>
      container(tester).read(clockProvider.notifier) as FixedClock;

  Future<void> tick(WidgetTester tester, DateTime at) async {
    clock(tester).set(at);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Future<void> record(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player.record')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Record names the planned end: programme end + 15 min', (
    tester,
  ) async {
    await open(tester);
    // Evening news ends 19:30 CET.
    expect(findPlayerTooltip('Record Kanal 1 until 19:45 (r)'), findsOneWidget);
  });

  testWidgets('records what plays, with the elapsed time, and stops', (
    tester,
  ) async {
    await open(tester);
    await record(tester);
    expect(player.recordings, [
      '$testDownloadFolder/Recordings/'
          'Kanal 1 - Evening news - 2026-10-26 19-00.ts',
    ]);
    expect(find.text('REC 0:00:00'), findsOneWidget);
    expect(find.byKey(const Key('player.record')), findsNothing);
    expect(findPlayerTooltip('Stop recording (r)'), findsOneWidget);
    final item = container(tester).read(downloadsProvider).items.single;
    expect(item.kind, DownloadKind.recording);
    expect(item.status, DownloadStatus.recording);
    expect(item.to, _at(18, 45));

    await tick(tester, _at(18, 1, 5));
    expect(find.text('REC 0:01:05'), findsOneWidget);

    await tester.tap(find.byKey(const Key('player.stopRecording')));
    await tester.pump();
    await tester.pump();
    expect(player.recordingStops, 1);
    expect(find.byKey(const Key('player.recordingTime')), findsNothing);
    final done = container(tester).read(downloadsProvider).items.single;
    expect(done.status, DownloadStatus.done);
    expect(done.finishedAt, _at(18, 1, 5));
    expect(downloads.items.single.status, DownloadStatus.done);
  });

  testWidgets('r starts and stops the recording', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    await tester.pump();
    expect(player.recordings, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    await tester.pump();
    expect(player.recordingStops, 1);
  });

  testWidgets('stops by itself at the planned end', (tester) async {
    await open(tester);
    await record(tester);
    await tick(tester, _at(18, 44, 59));
    expect(player.recordingStops, 0);
    await tick(tester, _at(18, 45));
    expect(player.recordingStops, 1);
    expect(
      container(tester).read(downloadsProvider).items.single.status,
      DownloadStatus.done,
    );
  });

  testWidgets('without a guide it stops at the maximum length', (tester) async {
    await open(
      tester,
      channel: _catalog.channels[1],
      settings: const AppSettings(maxRecordingHours: 1),
    );
    expect(findPlayerTooltip('Record Kanal 2 until 20:00 (r)'), findsOneWidget);
    await record(tester);
    expect(container(tester).read(recordingProvider)!.plannedEnd, _at(19));
  });

  testWidgets('pause is greyed out while recording, and back after', (
    tester,
  ) async {
    await open(tester);
    await record(tester);
    final pause = find.byKey(const Key('player.livePause'));
    expect(tester.widget<IconButton>(pause).onPressed, isNull);
    expect(
      findPlayerTooltip("Pause isn't available while recording"),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.freezes, 0);

    await tester.tap(find.byKey(const Key('player.stopRecording')));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<IconButton>(pause).onPressed, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(player.freezes, 1);
  });

  testWidgets('switching channel asks first', (tester) async {
    await open(tester);
    await record(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kanal 2').last);
    await tester.pump();
    expect(find.text('Stop recording?'), findsOneWidget);
    expect(
      find.text(
        'Switching channel stops the recording of Kanal 1. '
        "What's recorded so far is kept.",
      ),
      findsOneWidget,
    );
    final loads = player.loads.length;

    await tester.tap(find.byKey(const Key('player.confirm.no')));
    await tester.pump();
    expect(find.text('Stop recording?'), findsNothing);
    expect(player.loads, hasLength(loads));
    expect(player.recordingStops, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kanal 2').last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('player.confirm.yes')));
    await tester.pump();
    await tester.pump();
    expect(player.recordingStops, 1);
    expect(player.loads, hasLength(loads + 1));
  });

  testWidgets('Esc keeps recording', (tester) async {
    await open(tester);
    await record(tester);
    await tester.tap(find.byKey(const Key('player.stop')));
    await tester.pump();
    expect(find.text('Stop recording?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Stop recording?'), findsNothing);
    expect(find.byType(MpvPlayerScreen), findsOneWidget);
    expect(player.recordingStops, 0);
  });

  testWidgets('Stop and Back ask first, then leave', (tester) async {
    await open(tester);
    await record(tester);
    await tester.tap(find.byKey(const Key('player.back')));
    await tester.pump();
    expect(
      find.textContaining('Leaving the player stops the recording'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('player.confirm.no')));
    await tester.pump();
    expect(find.byType(MpvPlayerScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('player.stop')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('player.confirm.yes')));
    await tester.pumpAndSettle();
    expect(find.byType(MpvPlayerScreen), findsNothing);
    expect(player.recordingStops, 1);
  });

  testWidgets('closing the app asks the player', (tester) async {
    await open(tester);
    await record(tester);
    final answer = container(tester)
        .read(recordingProvider.notifier)
        .confirmStop(RecordingStop.quit);
    await tester.pump();
    expect(
      find.textContaining('Closing the app stops the recording'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('player.confirm.no')));
    await tester.pump();
    expect(await answer, isFalse);
  });

  testWidgets('the stream ending stops the recording with a note', (
    tester,
  ) async {
    await open(tester);
    await record(tester);
    player.emit(player.state.copyWith(status: ExternalPlayerStatus.exited));
    await tester.pumpAndSettle();
    final item = downloads.items.single;
    expect(item.status, DownloadStatus.done);
    expect(item.message, 'Stopped: the stream ended.');
  });

  testWidgets("says why it can't record", (tester) async {
    freeSpace.bytes = 4 * bytesPerGb;
    await open(tester);
    await record(tester);
    expect(
      find.text("Can't record: less than 5 GB free on the disk."),
      findsOneWidget,
    );
    expect(player.recordings, isEmpty);

    freeSpace.bytes = 100 * bytesPerGb;
    player.recordingFails = true;
    await record(tester);
    expect(
      find.text("Couldn't start recording: the player refused."),
      findsOneWidget,
    );
    expect(container(tester).read(downloadsProvider).items, isEmpty);
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const Key('player.recordProblem')), findsNothing);
  });

  testWidgets('the disk filling up stops the recording', (tester) async {
    await open(tester);
    await record(tester);
    freeSpace.bytes = 4 * bytesPerGb;
    for (var s = 1; s <= RecordingController.spaceTicks; s++) {
      await tick(tester, _now.add(Duration(seconds: s)));
    }
    expect(player.recordingStops, 1);
    expect(
      downloads.items.single.message,
      'Stopped: less than 5 GB free on the disk.',
    );
  });

  testWidgets('fullscreen keeps a REC pill over the video', (tester) async {
    await open(tester);
    await record(tester);
    await tester.tap(find.byKey(const Key('player.fullscreen')));
    await tester.pump();
    expect(find.byKey(const Key('player.recordingPill')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    // The controls hid; the pill stays.
    expect(find.byKey(const Key('player.recordingPill')), findsOneWidget);
  });

  for (final scale in [1.0, 1.4]) {
    testWidgets('the bar and the question fit at text scale $scale', (
      tester,
    ) async {
      await open(tester, scale: scale);
      await record(tester);
      await tick(tester, _at(18, 12, 34));
      expect(find.text('REC 0:12:34'), findsOneWidget);
      await tester.tap(find.byKey(const Key('player.stop')));
      await tester.pump();
      expect(find.text('Stop recording?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
