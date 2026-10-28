import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tvplayer/app.dart';
import 'package:tvplayer/data/errors.dart';
import 'package:tvplayer/format.dart';
import 'package:tvplayer/state/playlist_refresh.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/home/home_screen.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/settings/playlist_section.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer/ui/shell/app_messages.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

/// Monday; Stockholm is on UTC+1 since the day before, so this is 12:40
/// local time.
final _now = DateTime.utc(2026, 10, 26, 11, 40);

DateTime _ago(Duration d) => _now.subtract(d);

const _config = ProviderConfig.xtream(
  host: 'http://example.com',
  username: 'testuser',
  password: 'testpass',
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

/// Pumps a few frames: a running refresh shows a spinner, so the tree never
/// settles.
Future<void> _frames(WidgetTester tester, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _texts(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
].join('\n');

Future<void> _openPlaylist(WidgetTester tester) async {
  final button = find.byKey(const Key('settings.refreshAll'));
  await tester.scrollUntilVisible(button, 100);
  await tester.pump();
}

void main() {
  group('formatUpdated', () {
    final now = DateTime(2026, 10, 26, 12, 40);
    test('today, yesterday, a date, another year', () {
      expect(formatUpdated(DateTime(2026, 10, 26, 0, 5), now), 'Today 00:05');
      expect(
        formatUpdated(DateTime(2026, 10, 25, 21, 5), now),
        'Yesterday 21:05',
      );
      expect(
        formatUpdated(DateTime(2026, 10, 25, 23, 59), now),
        'Yesterday 23:59',
      );
      expect(
        formatUpdated(DateTime(2026, 10, 20, 14, 5), now),
        'Tue 20 Oct 14:05',
      );
      expect(
        formatUpdated(DateTime(2025, 12, 31, 9, 0), DateTime(2026, 1, 1, 8)),
        'Yesterday 09:00',
      );
      expect(
        formatUpdated(DateTime(2025, 12, 30, 9, 0), DateTime(2026, 1, 1, 8)),
        'Tue 30 Dec 2025 09:00',
      );
    });
  });

  test('refresh errors are plain words without hosts or credentials', () {
    expect(
      describeRefreshError(
        const XtreamException('Unexpected response (x)', statusCode: 502),
      ),
      "The provider's server had a problem (HTTP 502).",
    );
    expect(
      describeRefreshError(
        const XtreamException(
          'Network error (x): ***',
          kind: ProviderFailure.network,
        ),
      ),
      "Couldn't reach the provider. Check the internet connection.",
    );
    expect(
      describeRefreshError(const XtreamAuthException()),
      'Login failed: the username or password was rejected.',
    );
    expect(
      describeRefreshError(const M3uException('x', statusCode: 404)),
      'The provider refused the request (HTTP 404).',
    );
    expect(
      describeRefreshError(const EmptyResultException()),
      'The provider sent an empty list. Try again later.',
    );
  });

  group('Settings › Playlist', () {
    testWidgets('shows when each part was updated, at text scale 1.4', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final vod = FakeVodRepository()
        ..movies['test'] = syntheticMovies(
          count: 3,
          fetchedAt: DateTime.utc(2026, 10, 25, 20, 5),
        );
      final epg = FakeEpgRepository(
        cached: EpgGuide.empty(fetchedAt: DateTime.utc(2026, 10, 23, 10, 40)),
      );
      await tester.pumpWidget(
        testApp(
          overrides: [
            liveSourceProvider.overrideWithValue(
              FakeLiveSource(syntheticCatalog(count: 3), hasGuide: true),
            ),
            vodSourceProvider.overrideWithValue(
              FakeVodSource(series: syntheticSeries(count: 2)),
            ),
            providerKeyProvider.overrideWithValue('test'),
          ],
          vod: vod,
          epg: epg,
          // Off, so nothing old is refreshed while the page is open.
          playlistStatus: MemoryPlaylistStatusStore(
            PlaylistStatus.empty.withAutoRefresh(AutoRefresh.off),
          ),
          now: _now,
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openPlaylist(tester);
      await tester.pumpAndSettle();

      Finder row(PlaylistPart p, String text) => find.descendant(
        of: find.byKey(Key('settings.playlist.${p.name}')),
        matching: find.text(text),
      );
      expect(
        row(PlaylistPart.channels, 'Updated Today 12:40 · 3 channels'),
        findsOneWidget,
      );
      expect(
        row(PlaylistPart.movies, 'Updated Yesterday 21:05 · 3 movies'),
        findsOneWidget,
      );
      // No cache: downloaded when the page opened.
      expect(
        row(PlaylistPart.series, 'Updated Today 12:40 · 2 series'),
        findsOneWidget,
      );
      expect(epg.refreshes, 0);
      expect(
        row(PlaylistPart.guide, 'Updated Fri 23 Oct 12:40 · 0 programmes'),
        findsOneWidget,
      );
      expect(find.text('Refresh all'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.textContaining('Runs only while tvplayer'), findsOneWidget);
      // No overflow at 1.4: the test fails on layout errors.
      expect(tester.takeException(), isNull);

      // Daily says it goes by the calendar day.
      await tester.ensureVisible(find.byKey(const Key('settings.autoRefresh')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.autoRefresh')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Once a day: the first time tvplayer is open on '
          'a new day',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('M3U: only channels; the rest is not available', (
      tester,
    ) async {
      final source = FakeLiveSource(syntheticCatalog(count: 3));
      await tester.pumpWidget(
        testApp(
          overrides: [
            liveSourceProvider.overrideWithValue(source),
            vodSourceProvider.overrideWithValue(null),
            providerKeyProvider.overrideWithValue('test'),
          ],
          now: _now,
          child: const Scaffold(body: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await _openPlaylist(tester);
      for (final p in [
        PlaylistPart.movies,
        PlaylistPart.series,
        PlaylistPart.guide,
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key('settings.playlist.${p.name}')),
            matching: find.text('Not available for this provider'),
          ),
          findsOneWidget,
        );
      }
      source.gate = Completer();
      await tester.tap(find.text('Refresh all'));
      await tester.pump();
      expect(find.text('Refreshing 1 of 1…'), findsOneWidget);
      source.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Refresh all'), findsOneWidget);
    });

    testWidgets('Refresh all runs the parts in turn; a failing part keeps '
        'its data and says why, without hosts or credentials', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <Uri>[];
      final logs = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      final vodGate = Completer<void>();
      var vodFails = false;
      final client = MockClient((request) async {
        requests.add(request.url);
        final action = request.url.queryParameters['action'];
        if (action == 'get_vod_streams' && vodFails) {
          await vodGate.future;
          return http.Response('', 502);
        }
        final body = switch (action) {
          'get_live_streams' => [
            {'stream_id': 1, 'name': 'One', 'category_id': '1'},
            {'stream_id': 2, 'name': 'Two', 'category_id': '1'},
          ],
          'get_vod_streams' => [
            {'stream_id': 10, 'name': 'Movie', 'category_id': '1'},
          ],
          'get_series' => [
            {'series_id': 20, 'name': 'Show', 'category_id': '1'},
          ],
          _ => <Object>[],
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      });
      final key = providerKey(_config);
      final vod = FakeVodRepository()
        ..movies[key] = syntheticMovies(
          count: 4,
          fetchedAt: _ago(Duration.zero),
        )
        ..series[key] = syntheticSeries(
          count: 5,
          fetchedAt: _ago(Duration.zero),
        );
      final epg = FakeEpgRepository(cached: EpgGuide.empty(fetchedAt: _now))
        ..gate = Completer();
      final status = MemoryPlaylistStatusStore();
      await tester.pumpWidget(
        testApp(
          overrides: [httpClientProvider.overrideWithValue(client)],
          providerStorage: FakeProviderStorage(_config),
          vod: vod,
          epg: epg,
          playlistStatus: status,
          now: _now,
          child: const Scaffold(body: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await _openPlaylist(tester);
      requests.clear();
      vodFails = true;

      await tester.tap(find.byKey(const Key('settings.refreshAll')));
      await _frames(tester);
      // Channels are done, movies are waiting for the provider.
      expect(find.text('Refreshing 2 of 4…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('settings.refreshAll')))
            .onPressed,
        isNull,
      );
      Finder row(PlaylistPart p, String text) => find.descendant(
        of: find.byKey(Key('settings.playlist.${p.name}')),
        matching: find.text(text),
      );
      expect(
        row(PlaylistPart.channels, 'Updated Today 12:40 · 2 channels'),
        findsOneWidget,
      );
      expect(row(PlaylistPart.movies, 'Updating…'), findsOneWidget);
      expect(row(PlaylistPart.series, 'Waiting…'), findsOneWidget);
      expect(row(PlaylistPart.guide, 'Waiting…'), findsOneWidget);

      vodGate.complete();
      await _frames(tester);
      expect(find.text('Refreshing 4 of 4…'), findsOneWidget);
      expect(row(PlaylistPart.guide, 'Updating…'), findsOneWidget);
      epg.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Refresh all'), findsOneWidget);
      expect(
        row(
          PlaylistPart.movies,
          'Last update failed Today 12:40: The provider\'s server had a '
          'problem (HTTP 502). The previous list is kept. Last successful '
          'update Today 12:40.',
        ),
        findsOneWidget,
      );
      expect(vod.movies[key]!.items, hasLength(4));
      expect(
        _container(tester).read(movieCatalogProvider).catalog!.items,
        hasLength(4),
      );
      expect(
        row(PlaylistPart.series, 'Updated Today 12:40 · 1 series'),
        findsOneWidget,
      );
      expect(status.status.part(PlaylistPart.movies).failed, isTrue);
      expect(status.status.part(PlaylistPart.series).failed, isFalse);
      // Only the failed part is named in the confirmation.
      final notice = _container(tester).read(manualRefreshNoticeProvider)!;
      expect(notice.all, PlaylistPart.values);
      expect(notice.failed, [PlaylistPart.movies]);
      expect(
        manualRefreshText(notice),
        "Couldn't refresh movies. The provider's server had a problem "
        '(HTTP 502).',
      );

      // Nothing shown or logged names the provider or the account.
      for (final text in [_texts(tester), ...logs]) {
        expect(text, isNot(contains('example.com')));
        expect(text, isNot(contains('testuser')));
        expect(text, isNot(contains('testpass')));
      }
      debugPrint = print;
      // Only API requests: nothing that could open a stream.
      expect(requests, isNotEmpty);
      for (final r in requests) {
        expect(r.path, '/player_api.php');
      }
    });
  });

  group('Live TV reload', () {
    testWidgets('updates the shared time; a failure keeps the channels', (
      tester,
    ) async {
      final source = FakeLiveSource(syntheticCatalog(count: 3));
      final status = MemoryPlaylistStatusStore();
      await tester.pumpWidget(
        testApp(
          overrides: [
            liveSourceProvider.overrideWithValue(source),
            providerKeyProvider.overrideWithValue('test'),
          ],
          playlistStatus: status,
          now: _now,
          child: const Scaffold(body: LiveTvScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(status.status.part(PlaylistPart.channels).updatedAt, _now);

      final later = _now.add(const Duration(hours: 2));
      (_container(tester).read(clockProvider.notifier) as FixedClock).set(
        later,
      );
      await tester.tap(find.byTooltip('Reload channels'));
      await tester.pumpAndSettle();
      expect(source.loads, 2);
      expect(status.status.part(PlaylistPart.channels).updatedAt, later);

      source.failTimes = 1;
      await tester.tap(find.byTooltip('Reload channels'));
      await tester.pumpAndSettle();
      expect(source.loads, 3);
      expect(find.text('Channel 0002'), findsOneWidget);
      expect(find.text('Could not load channels'), findsNothing);
      final channels = status.status.part(PlaylistPart.channels);
      expect(channels.updatedAt, later);
      expect(channels.error, "The provider didn't respond in time.");
    });

    testWidgets('an emptied list is refused and the channels are kept', (
      tester,
    ) async {
      var empty = false;
      final full = syntheticCatalog(count: 3);
      final source = _SwitchingLiveSource(
        () => empty ? LiveCatalog(categories: [], channels: []) : full,
      );
      await tester.pumpWidget(
        testApp(
          overrides: [liveSourceProvider.overrideWithValue(source)],
          now: _now,
          child: const Scaffold(body: LiveTvScreen()),
        ),
      );
      await tester.pumpAndSettle();
      empty = true;
      await tester.tap(find.byTooltip('Reload channels'));
      await tester.pumpAndSettle();
      expect(find.text('Channel 0002'), findsOneWidget);
      expect(
        _container(tester)
            .read(playlistStatusProvider)
            .part(PlaylistPart.channels)
            .error,
        'The provider sent an empty list. Try again later.',
      );
    });
  });

  group('automatic refresh', () {
    Future<(FakeVodSource, FakeLiveSource)> pump(
      WidgetTester tester, {
      required Duration moviesAge,
      required Duration seriesAge,
      AutoRefresh mode = AutoRefresh.daily,
      DateTime? now,
    }) async {
      final start = now ?? _now;
      final vod = FakeVodRepository()
        ..movies['test'] = syntheticMovies(
          count: 3,
          fetchedAt: start.subtract(moviesAge),
        )
        ..series['test'] = syntheticSeries(
          count: 3,
          fetchedAt: start.subtract(seriesAge),
        );
      final source = FakeVodSource(
        movies: syntheticMovies(count: 5),
        series: syntheticSeries(count: 5),
      );
      final live = FakeLiveSource(syntheticCatalog(count: 3));
      await tester.pumpWidget(
        testApp(
          overrides: [
            liveSourceProvider.overrideWithValue(live),
            vodSourceProvider.overrideWithValue(source),
            providerKeyProvider.overrideWithValue('test'),
          ],
          vod: vod,
          playlistStatus: MemoryPlaylistStatusStore(
            PlaylistStatus.empty.withAutoRefresh(mode),
          ),
          now: start,
          child: const Scaffold(body: AutoRefreshHost(child: SizedBox())),
        ),
      );
      await tester.pumpAndSettle();
      return (source, live);
    }

    testWidgets('daily: on start, what was updated on an earlier day', (
      tester,
    ) async {
      final (source, live) = await pump(
        tester,
        moviesAge: const Duration(days: 2),
        seriesAge: const Duration(hours: 1),
      );
      expect(source.movieLoads, 1);
      expect(source.seriesLoads, 0);
      expect(live.loads, 1);
    });

    testWidgets('off: nothing, however old', (tester) async {
      final (source, live) = await pump(
        tester,
        moviesAge: const Duration(days: 20),
        seriesAge: const Duration(days: 20),
        mode: AutoRefresh.off,
      );
      expect(source.movieLoads, 0);
      expect(source.seriesLoads, 0);
      expect(live.loads, 1);
    });

    testWidgets('on app start: everything not just downloaded', (tester) async {
      final (source, live) = await pump(
        tester,
        moviesAge: const Duration(minutes: 5),
        seriesAge: const Duration(minutes: 5),
        mode: AutoRefresh.onStart,
      );
      expect(source.movieLoads, 1);
      expect(source.seriesLoads, 1);
      // The channels were just loaded at start.
      expect(live.loads, 1);
    });

    testWidgets('while open it checks again, and waits while something '
        'plays', (tester) async {
      final (source, _) = await pump(
        tester,
        moviesAge: const Duration(hours: 1),
        seriesAge: const Duration(hours: 1),
      );
      expect(source.movieLoads, 0);
      final container = _container(tester);
      final playback = container.read(playbackActiveProvider.notifier)..begin();
      (container.read(clockProvider.notifier) as FixedClock).set(
        _now.add(const Duration(days: 1)),
      );
      await tester.pump(PlaylistRefreshController.checkInterval);
      await tester.pumpAndSettle();
      expect(source.movieLoads, 0);

      playback.end();
      await tester.pumpAndSettle();
      expect(source.movieLoads, 1);
      expect(source.seriesLoads, 1);
    });
    testWidgets('daily: open past midnight, the next check refreshes', (
      tester,
    ) async {
      // 23:50 in Stockholm (the test device's zone), updated at 20:50.
      final evening = DateTime.utc(2026, 10, 26, 22, 50);
      final (source, _) = await pump(
        tester,
        moviesAge: const Duration(hours: 3),
        seriesAge: const Duration(hours: 3),
        now: evening,
      );
      expect(source.movieLoads, 0);
      final clock = _container(tester).read(clockProvider.notifier);
      (clock as FixedClock).set(evening.add(const Duration(minutes: 5)));
      await tester.pump(PlaylistRefreshController.checkInterval);
      await tester.pumpAndSettle();
      expect(source.movieLoads, 0, reason: 'still the same day');
      // 00:05: a new day.
      clock.set(evening.add(const Duration(minutes: 15)));
      await tester.pump(PlaylistRefreshController.checkInterval);
      await tester.pumpAndSettle();
      expect(source.movieLoads, 1);
      expect(source.seriesLoads, 1);
    });
  });

  group('first start', () {
    /// A panel whose list requests take [delay]; records the most list
    /// downloads (channels, movies, series) running at once.
    ({MockClient client, int Function() maxParallel}) panel({
      List<Object> movies = const [
        {'stream_id': 10, 'name': 'Movie', 'category_id': '1'},
      ],
      Duration delay = const Duration(milliseconds: 200),
    }) {
      var running = 0, max = 0;
      final client = MockClient((request) async {
        final action = request.url.queryParameters['action'];
        final list = switch (action) {
          'get_live_streams' || 'get_vod_streams' || 'get_series' => true,
          _ => false,
        };
        if (list) {
          running++;
          if (running > max) max = running;
          await Future<void>.delayed(delay);
          running--;
        }
        final body = switch (action) {
          null => activeAccountJson,
          'get_live_categories' ||
          'get_vod_categories' ||
          'get_series_categories' => [
            {'category_id': '1', 'category_name': 'Category'},
          ],
          'get_live_streams' => [
            {'stream_id': 1, 'name': 'One', 'category_id': '1'},
          ],
          'get_vod_streams' => movies,
          'get_series' => [
            {'series_id': 20, 'name': 'Show', 'category_id': '1'},
          ],
          _ => <Object>[],
        };
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      });
      return (client: client, maxParallel: () => max);
    }

    Future<MemoryPlaylistStatusStore> pump(
      WidgetTester tester,
      MockClient client,
    ) async {
      final status = MemoryPlaylistStatusStore();
      await tester.pumpWidget(
        testApp(
          overrides: [httpClientProvider.overrideWithValue(client)],
          providerStorage: FakeProviderStorage(_config),
          playlistStatus: status,
          now: _now,
          child: const Scaffold(body: AutoRefreshHost(child: SizedBox())),
        ),
      );
      await _frames(tester, 40);
      await tester.pumpAndSettle();
      return status;
    }

    testWidgets('without caches, the parts download one after another', (
      tester,
    ) async {
      final (:client, :maxParallel) = panel();
      await pump(tester, client);
      final container = _container(tester);
      expect(container.read(liveCatalogProvider).value?.channelCount, 1);
      expect(container.read(movieCatalogProvider).catalog?.items, hasLength(1));
      expect(
        container.read(seriesCatalogProvider).catalog?.items,
        hasLength(1),
      );
      expect(maxParallel(), 1);
    });

    testWidgets('no movies while the provider lists movie categories is a '
        'failure, not an empty catalogue', (tester) async {
      final (:client, maxParallel: _) = panel(movies: const []);
      await pump(tester, client);
      final container = _container(tester);
      final movies = container.read(movieCatalogProvider);
      expect(movies.catalog, isNull);
      expect(movies.error, 'The provider sent an empty list. Try again later.');
      final part = container
          .read(playlistStatusProvider)
          .part(PlaylistPart.movies);
      expect(part.updatedAt, isNull);
      expect(part.failedAt, _now);
      expect(part.error, 'The provider sent an empty list. Try again later.');
    });
  });

  group('manual reload confirmation', () {
    test('texts', () {
      ManualRefreshNotice notice(
        List<PlaylistPart> all, [
        List<PlaylistPart> failed = const [],
        String? error,
      ]) => ManualRefreshNotice(
        serial: 1,
        all: all,
        failed: failed,
        error: error,
      );
      expect(
        manualRefreshText(notice([PlaylistPart.guide])),
        'TV guide updated',
      );
      expect(
        manualRefreshText(notice([PlaylistPart.channels])),
        'Channels updated',
      );
      expect(
        manualRefreshText(notice(PlaylistPart.values)),
        'Playlist updated',
      );
      expect(
        manualRefreshText(
          notice(PlaylistPart.values, [
            PlaylistPart.movies,
            PlaylistPart.guide,
          ], "The provider didn't respond in time."),
        ),
        "Couldn't refresh movies and the TV guide. The provider didn't "
        'respond in time.',
      );
    });

    late FakeVodSource vodSource;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      vodSource = FakeVodSource(
        movies: syntheticMovies(count: 3),
        series: syntheticSeries(count: 3),
      );
      final vod = FakeVodRepository()
        ..movies['test'] = syntheticMovies(count: 3, fetchedAt: _now)
        ..series['test'] = syntheticSeries(count: 3, fetchedAt: _now);
      await tester.pumpWidget(
        testApp(
          overrides: [
            liveSourceProvider.overrideWithValue(
              FakeLiveSource(syntheticCatalog(count: 3), hasGuide: true),
            ),
            vodSourceProvider.overrideWithValue(vodSource),
            providerKeyProvider.overrideWithValue('test'),
          ],
          vod: vod,
          epg: FakeEpgRepository(
            cached: EpgGuide.empty(fetchedAt: _now),
            next: EpgGuide.empty(fetchedAt: _now),
          ),
          now: _now,
          child: const AppShell(),
        ),
      );
      await tester.pumpAndSettle();
    }

    final bar = find.byKey(const Key('playlist.manualDone'));

    Future<void> open(WidgetTester tester, String section) async {
      await tester.tap(find.text(section).first);
      await tester.pumpAndSettle();
    }

    testWidgets('automatic refreshes and first downloads stay silent', (
      tester,
    ) async {
      await pump(tester);
      expect(bar, findsNothing);
    });

    testWidgets('Reload channels confirms; closes after 6 s', (tester) async {
      await pump(tester);
      await open(tester, 'Live TV');
      await tester.tap(find.byTooltip('Reload channels'));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      expect(find.text('Channels updated'), findsOneWidget);
      expect(tester.widget<SnackBar>(bar).duration, messageDuration);
      expect(find.byKey(const Key('message.icon.success')), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(bar, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });

    testWidgets('one message at a time; closes when another page opens', (
      tester,
    ) async {
      await pump(tester);
      await open(tester, 'Live TV');
      await tester.tap(find.byTooltip('Reload channels'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh TV guide'));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      expect(find.text('Channels updated'), findsNothing);
      expect(find.text('TV guide updated'), findsOneWidget);

      await open(tester, 'Movies');
      expect(bar, findsNothing);
    });

    testWidgets('TV Guide and Movies confirm; a failure says why', (
      tester,
    ) async {
      await pump(tester);
      await open(tester, 'TV Guide');
      await tester.tap(find.byTooltip('Refresh TV guide'));
      await tester.pumpAndSettle();
      expect(find.text('TV guide updated'), findsOneWidget);

      await open(tester, 'Movies');
      await tester.tap(find.byKey(const Key('movies.refresh')));
      await tester.pumpAndSettle();
      expect(find.text('Movies updated'), findsOneWidget);

      vodSource.failure = const XtreamException(
        'Unexpected response (get_vod_streams)',
        statusCode: 502,
      );
      await tester.tap(find.byKey(const Key('movies.refresh')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Couldn't refresh movies. The provider's server had a problem "
          '(HTTP 502).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Refresh all confirms once', (tester) async {
      await pump(tester);
      await open(tester, 'Settings');
      await _openPlaylist(tester);
      await tester.tap(find.byKey(const Key('settings.refreshAll')));
      await tester.pumpAndSettle();
      expect(bar, findsOneWidget);
      expect(find.text('Playlist updated'), findsOneWidget);
    });
  });

  group('failure notice', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final player = FakeExternalPlayer();
      addTearDown(player.dispose);
      final vod = FakeVodRepository()
        ..movies['test'] = syntheticMovies(
          count: 3,
          fetchedAt: _ago(const Duration(days: 2)),
        )
        ..series['test'] = syntheticSeries(
          count: 3,
          fetchedAt: _ago(const Duration(hours: 1)),
        );
      await tester.pumpWidget(
        testApp(
          overrides: [
            liveSourceProvider.overrideWithValue(
              FakeLiveSource(syntheticCatalog(count: 3)),
            ),
            vodSourceProvider.overrideWithValue(
              FakeVodSource()
                ..failure = const XtreamException(
                  'Unexpected response (get_vod_streams)',
                  statusCode: 502,
                ),
            ),
            providerKeyProvider.overrideWithValue('test'),
            useExternalMpvProvider.overrideWithValue(true),
            externalMpvProvider.overrideWithValue(player),
            embedMpvProvider.overrideWithValue(false),
          ],
          vod: vod,
          now: _now,
          child: const AppShell(),
        ),
      );
      await tester.pumpAndSettle();
    }

    final bar = find.byKey(const Key('playlist.autoFailed'));

    testWidgets('a quiet snack bar that closes after 6 s', (tester) async {
      await pump(tester);
      expect(bar, findsOneWidget);
      expect(
        find.text("Couldn't refresh movies. The previous data is kept."),
        findsOneWidget,
      );
      final snackBar = tester.widget<SnackBar>(bar);
      expect(snackBar.persist, isFalse);
      expect(snackBar.duration, const Duration(seconds: 6));
      expect(find.byKey(const Key('message.icon.error')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      expect(bar, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });

    testWidgets('a part that keeps failing is not reported again', (
      tester,
    ) async {
      await pump(tester);
      expect(bar, findsOneWidget);
      await tester.pump(messageDuration);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);

      final container = _container(tester);
      (container.read(clockProvider.notifier) as FixedClock).set(
        _now.add(const Duration(hours: 2)),
      );
      await tester.pump(PlaylistRefreshController.checkInterval);
      await tester.pumpAndSettle();
      // Tried again (and failed again), quietly.
      expect(
        container
            .read(playlistStatusProvider)
            .part(PlaylistPart.movies)
            .failedAt,
        _now.add(const Duration(hours: 2)),
      );
      expect(bar, findsNothing);
    });

    testWidgets('closes when another page opens', (tester) async {
      await pump(tester);
      expect(bar, findsOneWidget);
      await tester.tap(find.text('Live TV'));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });

    testWidgets('"Details" opens Settings with the reason', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
      await _openPlaylist(tester);
      expect(
        find.textContaining("The provider's server had a problem (HTTP 502)."),
        findsOneWidget,
      );
    });

    testWidgets('at app start, once per part per session, after a failure '
        'recorded earlier', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const offline = XtreamException(
        'Network error (x)',
        kind: ProviderFailure.network,
      );
      // An earlier "Refresh all" without network, recorded on disk.
      var earlier = PlaylistStatus.empty.withAutoRefresh(AutoRefresh.onStart);
      for (final p in PlaylistPart.values) {
        earlier = earlier.withPart(
          p,
          PartStatus(
            updatedAt: _ago(const Duration(days: 1)),
            failedAt: _ago(const Duration(minutes: 20)),
            error: describeRefreshError(offline),
          ),
        );
      }
      final live = FakeLiveSource(
        syntheticCatalog(count: 3),
        hasGuide: true,
        failTimes: 1 << 20,
      );
      final vod = FakeVodRepository()
        ..movies[providerKey(_config)] = syntheticMovies(
          count: 3,
          fetchedAt: _ago(const Duration(days: 1)),
        )
        ..series[providerKey(_config)] = syntheticSeries(
          count: 3,
          fetchedAt: _ago(const Duration(days: 1)),
        );
      // As the app starts: the saved provider, then the app on Home.
      await tester.pumpWidget(
        testApp(
          providerStorage: FakeProviderStorage(_config),
          overrides: [
            liveSourceProvider.overrideWithValue(live),
            vodSourceProvider.overrideWithValue(
              FakeVodSource()..failure = offline,
            ),
            useExternalMpvProvider.overrideWithValue(true),
            externalMpvProvider.overrideWithValue(FakeExternalPlayer()),
            embedMpvProvider.overrideWithValue(false),
          ],
          vod: vod,
          epg: FakeEpgRepository(failure: offline),
          playlistStatus: MemoryPlaylistStatusStore(earlier),
          now: _now,
          child: const RootGate(),
        ),
      );
      await tester.pumpAndSettle();

      // One notice for the whole run, on Home.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(bar, findsOneWidget);
      expect(
        find.text(
          "Couldn't refresh channels, movies, series and the TV guide. "
          'The previous data is kept.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(bar, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);

      // Failing again later in the same session: Settings only.
      final container = _container(tester);
      (container.read(clockProvider.notifier) as FixedClock).set(
        _now.add(const Duration(hours: 2)),
      );
      await container
          .read(playlistStatusProvider.notifier)
          .setAutoRefresh(AutoRefresh.every6Hours);
      await tester.pump(PlaylistRefreshController.checkInterval);
      await tester.pumpAndSettle();
      expect(
        container
            .read(playlistStatusProvider)
            .part(PlaylistPart.movies)
            .failedAt,
        _now.add(const Duration(hours: 2)),
      );
      expect(bar, findsNothing);
    });
  });
}

/// [LiveSource] whose catalog comes from [next] on every load.
class _SwitchingLiveSource extends FakeLiveSource {
  _SwitchingLiveSource(this.next) : super(next());

  final LiveCatalog Function() next;

  @override
  Future<LiveCatalog> load() async {
    loads++;
    return next();
  }
}
