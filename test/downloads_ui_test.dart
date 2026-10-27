import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/state/downloads_controller.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/downloads/downloads_screen.dart';
import 'package:tvplayer/ui/epg/programme_panel.dart';
import 'package:tvplayer/ui/player/mpv_player_screen.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
import 'package:tvplayer/ui/settings/downloads_section.dart';
import 'package:tvplayer/ui/vod/movie_details_screen.dart';
import 'package:tvplayer/ui/vod/series_details_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

/// 19:00 CET on Monday 26 October 2026.
final _now = DateTime.utc(2026, 10, 26, 18);

const _movie = Movie(
  streamId: 7,
  name: 'Test Movie (2020)',
  containerExtension: 'mkv',
  releaseDate: '2020-01-01',
);

const _channel = LiveStream(
  id: '1',
  name: 'Kanal 1 ◉',
  epgChannelId: 'k1.example',
  archiveDays: 3,
);

Episode _ep(int season, int number) => Episode(
  id: '${season * 100 + number}',
  season: season,
  episodeNumber: number,
  title: 'Episode $season-$number',
  containerExtension: 'mp4',
);

final _info = SeriesInfo(
  series: const Series(seriesId: 5, name: 'Test Show'),
  seasons: const [
    Season(seasonNumber: 1, name: 'Season 1'),
    Season(seasonNumber: 2, name: 'Season 2'),
  ],
  episodes: [_ep(1, 1), _ep(1, 2), _ep(2, 1)],
);

DownloadItem _item(
  String id, {
  DownloadKind kind = DownloadKind.movie,
  DownloadStatus status = DownloadStatus.queued,
  String source = '7',
  String? path,
  PauseReason? pause,
  String? message,
  int bytes = 0,
  int? total,
  DateTime? from,
  DateTime? to,
  String? programme,
}) => DownloadItem(
  id: id,
  kind: kind,
  title: kind == DownloadKind.movie ? 'Test Movie' : 'Kanal 1',
  year: kind == DownloadKind.movie ? 2020 : null,
  sourceId: source,
  extension: 'mkv',
  path: path ?? '$testDownloadFolder/Movies/$id.mkv',
  addedAt: _now,
  status: status,
  pauseReason: pause,
  message: message,
  bytes: bytes,
  totalBytes: total,
  from: from,
  to: to,
  programme: programme,
);

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
  late FakeTransfers transfers;
  late FakeSettingsStorage settings;
  late FakeFreeSpace freeSpace;

  setUp(() {
    freeSpace = FakeFreeSpace();
    player = FakeExternalPlayer();
    downloads = MemoryDownloadsStore();
    transfers = FakeTransfers();
    settings = FakeSettingsStorage();
  });
  tearDown(() => player.dispose());

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<DownloadItem> items = const [],
    double scale = 1.0,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    downloads.items = List.of(items);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(
              LiveCatalog(categories: const [], channels: const [_channel]),
              hasGuide: true,
            ),
          ),
          vodSourceProvider.overrideWithValue(
            FakeVodSource(seriesInfos: {5: _info}),
          ),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(true),
          videoEmbedProvider.overrideWithValue(FakeVideoEmbed()),
          ...overrides,
        ],
        downloads: downloads,
        transfers: transfers,
        settings: settings,
        freeSpace: freeSpace,
        now: _now,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  /// Starts the downloads queue, as the app shell does.
  Future<void> startQueue(WidgetTester tester) async {
    container(tester).read(downloadsProvider);
    await tester.pump();
    await tester.pump();
  }

  group('one stream at a time', () {
    testWidgets('playing while a download runs asks first', (tester) async {
      await pump(
        tester,
        const _Launcher(LivePlayback(_channel)),
        items: [_item('a', bytes: 450, total: 1000)],
      );
      await startQueue(tester);
      expect(transfers.runs, hasLength(1));
      transfers.runs.single.report(450, 1000);
      await tester.pump();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Pause the download?'), findsOneWidget);
      expect(
        find.text(
          'Your provider allows one stream at a time. “Test Movie” is '
          'downloading (45 %). It continues when playback stops.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('download.dontPlay')));
      await tester.pumpAndSettle();
      expect(find.byType(MpvPlayerScreen), findsNothing);
      expect(player.opened, isEmpty);
      expect(transfers.runs.single.control.stopped, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download.pauseAndPlay')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MpvPlayerScreen), findsOneWidget);
      expect(transfers.runs.single.control.stopped, isTrue);
      final paused = container(tester).read(downloadsProvider).byId('a')!;
      expect(paused.pauseReason, PauseReason.playback);
      expect(
        container(tester).read(streamGuardProvider).holds(StreamUse.playback),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('player.stop')));
      await tester.pumpAndSettle();
      // The download goes on after playback.
      expect(transfers.runs, hasLength(2));
      expect(
        container(tester).read(downloadsProvider).byId('a')!.status,
        DownloadStatus.running,
      );
    });

    testWidgets('a download waits while something plays', (tester) async {
      await pump(tester, const _Launcher(LivePlayback(_channel)));
      await startQueue(tester);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      container(tester)
          .read(downloadsProvider.notifier)
          .addMovie(_movie, ProviderTags.empty);
      await tester.pump();
      expect(transfers.runs, isEmpty);
      await tester.tap(find.byKey(const Key('player.stop')));
      await tester.pumpAndSettle();
      expect(transfers.runs, hasLength(1));
    });

    testWidgets('a downloaded movie plays from its file, without asking', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('tvplayer_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/Test Movie (2020).mkv')
        ..writeAsBytesSync([1, 2, 3]);
      await pump(
        tester,
        const _Launcher(MoviePlayback(_movie)),
        items: [
          _item('done', status: DownloadStatus.done, path: file.path),
          _item('b', source: '8'),
        ],
      );
      await startQueue(tester);
      expect(transfers.runs, hasLength(1));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Pause the download?'), findsNothing);
      expect(player.opened.single.url, Uri.file(file.path));
      // The download goes on meanwhile.
      expect(transfers.runs.single.control.stopped, isFalse);
    });
  });

  group('disk space', () {
    testWidgets("a download that doesn't fit doesn't start", (tester) async {
      freeSpace.bytes = 8 * bytesPerGb;
      await pump(
        tester,
        const Scaffold(body: DownloadsScreen()),
        items: [_item('a', total: 4 * bytesPerGb)],
      );
      await startQueue(tester);
      expect(transfers.runs, isEmpty);
      final item = container(tester).read(downloadsProvider).byId('a')!;
      expect(item.pauseReason, PauseReason.lowSpace);
      expect(
        item.message,
        'Not enough disk space: needs 4.0 GB, 8.0 GB free, keeps 5 GB free.',
      );
      // Stays paused until Resume.
      freeSpace.bytes = 100 * bytesPerGb;
      await tester.pump(DownloadsController.checkInterval);
      expect(transfers.runs, isEmpty);
      await tester.tap(find.byKey(const Key('download.resume')));
      await tester.pump();
      await tester.pump();
      expect(transfers.runs, hasLength(1));
    });

    testWidgets('warns, then pauses a running download, keeping it', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(body: DownloadsScreen()),
        items: [_item('a', total: 1000)],
      );
      await startQueue(tester);
      transfers.runs.single.report(500, 1000);
      freeSpace.bytes = 5 * bytesPerGb + 500000000;
      await tester.pump(DownloadsController.checkInterval);
      await tester.pump();
      // Shown in a snack bar by the app shell.
      expect(
        container(tester).read(downloadNoticeProvider)?.text,
        'The disk is almost full: downloads pause at 5 GB free.',
      );
      expect(transfers.runs.single.control.stopped, isFalse);

      freeSpace.bytes = 4 * bytesPerGb;
      await tester.pump(DownloadsController.checkInterval);
      await tester.pump();
      expect(transfers.runs.single.control.stopped, isTrue);
      final item = container(tester).read(downloadsProvider).byId('a')!;
      expect(item.status, DownloadStatus.paused);
      expect(item.pauseReason, PauseReason.lowSpace);
      expect(item.bytes, 500);
      expect(
        container(tester).read(downloadNoticeProvider)?.text,
        startsWith('Downloads paused: less than 5 GB free'),
      );
    });
  });

  testWidgets('a recording cut off by closing the app is kept as done', (
    tester,
  ) async {
    await pump(
      tester,
      const Scaffold(body: DownloadsScreen()),
      items: [
        _item(
          'rec',
          kind: DownloadKind.recording,
          status: DownloadStatus.recording,
          programme: 'Evening news',
          path: '$testDownloadFolder/Recordings/r.ts',
        ),
      ],
    );
    final item = container(tester).read(downloadsProvider).byId('rec')!;
    expect(item.status, DownloadStatus.done);
    expect(item.message, 'Stopped early: the app was closed.');
  });

  group('Downloads page', () {
    Widget page() => const Scaffold(body: DownloadsScreen());

    testWidgets('says how each download stands', (tester) async {
      await pump(
        tester,
        page(),
        items: [
          _item('run', bytes: 450000000, total: 1000000000),
          _item('q', source: '8'),
          _item(
            'p',
            source: '9',
            status: DownloadStatus.paused,
            pause: PauseReason.user,
            bytes: 250000000,
            total: 1000000000,
          ),
          _item(
            'low',
            source: '10',
            status: DownloadStatus.paused,
            pause: PauseReason.lowSpace,
            message: 'Paused: less than 5 GB free on the disk.',
          ),
          _item(
            'f',
            source: '11',
            status: DownloadStatus.failed,
            message: 'The provider refused the download (HTTP 403).',
          ),
          _item(
            'w',
            kind: DownloadKind.replay,
            source: '1',
            programme: 'Late news',
            from: _now.subtract(const Duration(hours: 1)),
            to: _now.add(const Duration(minutes: 15)),
          ),
          _item(
            'rec',
            kind: DownloadKind.recording,
            status: DownloadStatus.done,
            programme: 'Evening news',
            from: DateTime.utc(2026, 10, 26, 17),
            to: DateTime.utc(2026, 10, 26, 17, 45),
            bytes: 2100000000,
          ),
          _item(
            'm',
            source: '12',
            status: DownloadStatus.done,
            bytes: 2100000000,
          ),
        ],
      );
      await startQueue(tester);
      transfers.runs.single.report(450000000, 1000000000);
      await tester.pump();
      String status(String id) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ValueKey('download.$id')),
              matching: find.byKey(const Key('download.status')),
            ),
          )
          .data!;
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Recordings'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(status('run'), startsWith('45 % · 450 MB of 1.0 GB'));
      expect(status('q'), 'Waiting for its turn');
      expect(status('p'), 'Paused · 25 % · 250 MB of 1.0 GB');
      expect(status('low'), 'Paused: less than 5 GB free on the disk.');
      expect(
        status('f'),
        'Failed: The provider refused the download (HTTP 403).',
      );
      expect(status('w'), 'Waiting: starts at 19:15');
      expect(
        find.text('Recording · Kanal 1 · Mon 26 Oct 18:00–18:45 · 2.1 GB'),
        findsOneWidget,
      );
      expect(find.text('Movie · 2020 · 2.1 GB'), findsOneWidget);
    });

    testWidgets('pause, resume and try again', (tester) async {
      await pump(
        tester,
        page(),
        items: [
          // A known size: the bar doesn't animate.
          _item('a', total: 1000),
          _item(
            'f',
            source: '8',
            total: 1000,
            status: DownloadStatus.failed,
            message: 'The connection closed before the end.',
          ),
        ],
      );
      await startQueue(tester);
      Finder button(String id, String action) => find.descendant(
        of: find.byKey(ValueKey('download.$id')),
        matching: find.byKey(Key('download.$action')),
      );
      await tester.tap(button('a', 'pause'));
      await tester.pump();
      await tester.pump();
      expect(transfers.runs.first.control.stopped, isTrue);
      expect(
        container(tester).read(downloadsProvider).byId('a')!.status,
        DownloadStatus.paused,
      );
      await tester.tap(button('f', 'resume'));
      await tester.pump();
      await tester.pump();
      expect(transfers.runs.last.item.id, 'f');
      await tester.tap(button('a', 'resume'));
      await tester.pump();
      expect(
        container(tester).read(downloadsProvider).byId('a')!.status,
        DownloadStatus.queued,
      );
    });

    testWidgets('Remove asks, then deletes the file', (tester) async {
      final dir = Directory.systemTemp.createTempSync('tvplayer_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/m.mkv')..writeAsBytesSync([1, 2, 3]);
      await pump(
        tester,
        page(),
        items: [
          _item('m', status: DownloadStatus.done, path: file.path, bytes: 3),
        ],
      );
      await tester.tap(find.byKey(const Key('download.remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove “Test Movie”?'), findsOneWidget);
      expect(find.text('The file (3 B) is deleted.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('download.remove.cancel')));
      await tester.pumpAndSettle();
      expect(file.existsSync(), isTrue);

      await tester.tap(find.byKey(const Key('download.remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('download.remove.confirm')));
      await tester.pumpAndSettle();
      expect(file.existsSync(), isFalse);
      expect(find.byKey(const ValueKey('download.m')), findsNothing);
      expect(downloads.items, isEmpty);
    });

    testWidgets('Cancel of a partial download deletes the part file', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('tvplayer_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final part = File('${dir.path}/a.mkv.part')..writeAsBytesSync([1, 2]);
      await pump(
        tester,
        page(),
        items: [
          _item(
            'a',
            status: DownloadStatus.paused,
            pause: PauseReason.user,
            path: '${dir.path}/a.mkv',
            bytes: 2,
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('download.cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel “Test Movie”?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('download.remove.confirm')));
      await tester.pumpAndSettle();
      expect(part.existsSync(), isFalse);
      expect(find.byKey(const ValueKey('download.a')), findsNothing);
    });

    testWidgets('Play opens the finished file', (tester) async {
      await pump(
        tester,
        page(),
        items: [
          _item(
            'rec',
            kind: DownloadKind.recording,
            status: DownloadStatus.done,
            programme: 'Evening news',
            path: '$testDownloadFolder/Recordings/r.ts',
          ),
        ],
      );
      await tester.tap(find.byKey(const Key('download.play')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        player.opened.single.url,
        Uri.file('$testDownloadFolder/Recordings/r.ts'),
      );
    });

    testWidgets('says what to do when empty', (tester) async {
      await pump(tester, page());
      expect(find.byKey(const Key('downloads.empty')), findsOneWidget);
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('fits at text scale $scale', (tester) async {
        await pump(
          tester,
          page(),
          scale: scale,
          items: [
            _item('run', bytes: 450000000, total: 1000000000),
            _item(
              'f',
              source: '8',
              status: DownloadStatus.failed,
              message: "The provider's server had a problem (HTTP 502).",
            ),
            _item('m', source: '12', status: DownloadStatus.done),
          ],
        );
        await startQueue(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Download actions', () {
    testWidgets('movie details: Download, progress, then the mark', (
      tester,
    ) async {
      await pump(tester, const MovieDetailsScreen(movie: _movie));
      await startQueue(tester);
      await tester.tap(find.byKey(const Key('details.download')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Added “Test Movie” to Downloads'), findsOneWidget);
      final item = container(tester).read(downloadsProvider).items.single;
      expect(item.path, '$testDownloadFolder/Movies/Test Movie (2020).mkv');
      transfers.runs.single.report(300, 1000);
      await tester.pump();
      expect(find.text('Downloading 30 %'), findsOneWidget);
      transfers.runs.single.finish();
      await tester.pump();
      await tester.pump();
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byKey(const Key('poster.downloaded')), findsOneWidget);
    });

    testWidgets('the Added snack bar closes after 6 s and on navigation', (
      tester,
    ) async {
      await pump(tester, const MovieDetailsScreen(movie: _movie));
      await tester.tap(find.byKey(const Key('details.download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloads.added')), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloads.added')), findsNothing);

      container(tester)
          .read(downloadsProvider.notifier)
          .remove(container(tester).read(downloadsProvider).items.single.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details.download')));
      await tester.pump();
      expect(find.byKey(const Key('downloads.added')), findsOneWidget);
      Navigator.of(tester.element(find.byType(MovieDetailsScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloads.added')), findsNothing);
    });

    testWidgets('episode menu and Download season', (tester) async {
      await pump(
        tester,
        const SeriesDetailsScreen(
          series: Series(seriesId: 5, name: 'Test Show'),
        ),
      );
      await tester.tap(find.byKey(const Key('episode.menu')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('episode.download')));
      await tester.pumpAndSettle();
      var items = container(tester).read(downloadsProvider).items;
      expect(
        items.single.path,
        '$testDownloadFolder/Series/Test Show/Season 01/'
        'Test Show - S01E01 - Episode 1-1.mp4',
      );
      expect(find.byKey(const Key('episode.downloading')), findsOneWidget);

      await tester.tap(find.byKey(const Key('season.menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('season.download')));
      await tester.pumpAndSettle();
      items = container(tester).read(downloadsProvider).items;
      expect(items.map((i) => i.sourceId), ['101', '102']);
      expect(
        find.text('Added 1 episode of “Test Show” to Downloads'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('episode.menu')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('episode.cancelDownload')), findsOneWidget);
    });

    testWidgets('a downloaded episode has its mark and Remove download', (
      tester,
    ) async {
      await pump(
        tester,
        const SeriesDetailsScreen(
          series: Series(seriesId: 5, name: 'Test Show'),
        ),
        items: [
          _item(
            'e',
            kind: DownloadKind.episode,
            source: '101',
            status: DownloadStatus.done,
          ),
        ],
      );
      expect(find.byKey(const Key('downloaded.mark')), findsOneWidget);
      await tester.tap(find.byKey(const Key('episode.menu')).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('episode.removeDownload')), findsOneWidget);
    });

    Future<void> openPanel(WidgetTester tester, EpgProgram program) async {
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showProgrammePanel(
                context,
                channel: _channel,
                program: program,
              ),
              child: const Text('panel'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('panel'));
      await tester.pumpAndSettle();
    }

    testWidgets('a past programme downloads from the archive, with margins', (
      tester,
    ) async {
      await openPanel(
        tester,
        EpgProgram(
          channelId: 'k1.example',
          title: 'Afternoon',
          start: DateTime.utc(2026, 10, 26, 15),
          stop: DateTime.utc(2026, 10, 26, 16),
        ),
      );
      expect(find.text('Download saves 15:58–17:15'), findsOneWidget);
      await tester.tap(find.byKey(const Key('programme.download')));
      await tester.pumpAndSettle();
      final item = container(tester).read(downloadsProvider).items.single;
      expect(item.kind, DownloadKind.replay);
      expect(item.from, DateTime.utc(2026, 10, 26, 14, 58));
      expect(item.to, DateTime.utc(2026, 10, 26, 16, 15));
      expect(item.minutes, 77);
      expect(
        item.path,
        '$testDownloadFolder/Recordings/Kanal 1 - Afternoon - 2026-10-26 16-00.ts',
      );
      expect(find.text('Added “Afternoon” to Downloads'), findsOneWidget);

      await tester.tap(find.text('panel'));
      await tester.pumpAndSettle();
      expect(find.text('In Downloads'), findsOneWidget);
    });

    testWidgets('a programme that just ended waits for the end margin', (
      tester,
    ) async {
      await openPanel(
        tester,
        EpgProgram(
          channelId: 'k1.example',
          title: 'Early evening',
          start: DateTime.utc(2026, 10, 26, 17),
          stop: DateTime.utc(2026, 10, 26, 17, 55),
        ),
      );
      await tester.tap(find.byKey(const Key('programme.download')));
      await tester.pumpAndSettle();
      expect(
        container(tester).read(downloadsProvider).items.single.status,
        DownloadStatus.waiting,
      );
      expect(transfers.runs, isEmpty);
    });

    testWidgets('no Download for a programme on now', (tester) async {
      await openPanel(
        tester,
        EpgProgram(
          channelId: 'k1.example',
          title: 'Now',
          start: DateTime.utc(2026, 10, 26, 17, 30),
          stop: DateTime.utc(2026, 10, 26, 18, 30),
        ),
      );
      expect(find.byKey(const Key('programme.download')), findsNothing);
    });
  });

  group('Settings › Downloads & recording', () {
    Widget section() =>
        const Scaffold(body: SingleChildScrollView(child: DownloadsSection()));

    testWidgets('shows the folder and the defaults; changes are saved', (
      tester,
    ) async {
      await pump(
        tester,
        section(),
        overrides: [
          folderPickerProvider.overrideWithValue((_) async => '/media/films'),
        ],
      );
      expect(find.text(testDownloadFolder), findsOneWidget);
      expect(find.text('15 min'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
      expect(find.text('4 h'), findsOneWidget);
      expect(find.text('5 GB'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings.downloadFolder.change')));
      await tester.pumpAndSettle();
      expect(settings.saved.downloadFolder, '/media/films');
      expect(find.text('/media/films'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings.endMargin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();
      expect(settings.saved.endMarginMinutes, 30);

      await tester.tap(find.byKey(const Key('settings.downloadFolder.reset')));
      await tester.pumpAndSettle();
      expect(settings.saved.downloadFolder, isNull);
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('fits at text scale $scale', (tester) async {
        await pump(tester, section(), scale: scale);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('settings defaults match the design', () {
    const s = AppSettings();
    expect(s.endMarginMinutes, 15);
    expect(s.startMarginMinutes, 2);
    expect(s.maxRecordingHours, 4);
    expect(s.minFreeGb, 5);
  });
}
