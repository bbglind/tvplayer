import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer/ui/vod/poster.dart';
import 'package:tvplayer/ui/vod/series_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

final _now = DateTime.utc(2026, 3, 1, 20);

Episode _ep(int season, int number) => Episode(
  id: '${season * 100 + number}',
  season: season,
  episodeNumber: number,
  title: 'Episode $season-$number',
  plot: 'Plot of $season-$number.',
  duration: const Duration(minutes: 40),
);

/// Series 0: two specials, season 1 with 3 episodes, season 2 with 2.
final _info = SeriesInfo(
  series: const Series(seriesId: 0, name: 'Series 0000', plot: 'A show.'),
  seasons: const [],
  episodes: [
    _ep(0, 1),
    _ep(0, 2),
    _ep(1, 1),
    _ep(1, 2),
    _ep(1, 3),
    _ep(2, 1),
    _ep(2, 2),
  ],
);

WatchProgress _progress(int minutes, {bool watched = false, int at = 0}) =>
    WatchProgress(
      position: Duration(minutes: minutes),
      duration: const Duration(minutes: 90),
      watched: watched,
      updatedAt: _now.add(Duration(minutes: at)),
      seriesId: null,
    );

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  FakeVodSource? source,
  MemoryWatchStore? watch,
  FakeVodRepository? vod,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      overrides: [
        vodSourceProvider.overrideWithValue(
          source ??
              FakeVodSource(
                movies: syntheticMovies(),
                series: syntheticSeries(),
                seriesInfos: {0: _info},
              ),
        ),
        providerKeyProvider.overrideWithValue('test'),
      ],
      watch: watch,
      vod: vod,
      now: _now,
      child: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Movies', () {
    testWidgets('categories, lazy grid of 20000 movies and search', (
      tester,
    ) async {
      await _pump(tester, child: const MoviesScreen());

      expect(find.text('All movies'), findsOneWidget);
      expect(find.text('20000'), findsOneWidget);
      expect(find.text('Movie category 2'), findsOneWidget);
      expect(find.byKey(const ValueKey(0)), findsOneWidget);
      // Lazy grid: off-screen posters aren't built.
      expect(find.byKey(const ValueKey(19999)), findsNothing);
      expect(find.byType(InkWell).evaluate().length, lessThan(200));

      await tester.enterText(
        find.byKey(const Key('movies.search')),
        'movie 1999',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(19990)), findsOneWidget);
      expect(find.byKey(const ValueKey(0)), findsNothing);

      await tester.enterText(find.byKey(const Key('movies.search')), '');
      await tester.tap(find.text('Movie category 2'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(2)), findsOneWidget);
      expect(find.byKey(const ValueKey(0)), findsNothing);
    });

    testWidgets('opens instantly from the cache; fresh caches are not '
        'downloaded again, the refresh button does', (tester) async {
      final source = FakeVodSource(movies: syntheticMovies(count: 3));
      final repo = FakeVodRepository()
        ..movies['test'] = syntheticMovies(
          count: 50,
          fetchedAt: _now.subtract(const Duration(hours: 1)),
        );
      await _pump(
        tester,
        child: const MoviesScreen(),
        source: source,
        vod: repo,
      );
      expect(find.text('50'), findsOneWidget);
      expect(source.movieLoads, 0);

      await tester.tap(find.byKey(const Key('movies.refresh')));
      await tester.pumpAndSettle();
      expect(source.movieLoads, 1);
      expect(find.text('3'), findsWidgets);
      expect(repo.movies['test']!.items, hasLength(3));
    });

    testWidgets('download errors show a retry', (tester) async {
      final source = FakeVodSource()
        ..failure = const XtreamException(
          'Request timed out (get_vod_streams)',
          kind: ProviderFailure.timeout,
        );
      await _pump(tester, child: const MoviesScreen(), source: source);
      expect(find.text('Could not load movies'), findsOneWidget);
      expect(find.text("The provider didn't respond in time."), findsOneWidget);
      source.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('All movies'), findsOneWidget);
    });

    testWidgets('continue watching, watched badges and progress bars', (
      tester,
    ) async {
      final watch = MemoryWatchStore(
        WatchData.empty.withItems({
          movieKey(3): _progress(20, at: 1),
          movieKey(1): _progress(89, watched: true),
        }),
      );
      await _pump(tester, child: const MoviesScreen(), watch: watch);

      final row = find.byKey(const Key('movies.continue'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Movie 00003')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Resume at 20:00')),
        findsOneWidget,
      );
      final watchedCard = find.byKey(const ValueKey(1));
      expect(
        find.descendant(
          of: watchedCard,
          matching: find.byKey(const Key('poster.watched')),
        ),
        findsOneWidget,
      );
      final started = find.byKey(const ValueKey(3));
      expect(
        find.descendant(
          of: started,
          matching: find.byKey(const Key('poster.progress')),
        ),
        findsOneWidget,
      );
      final untouched = find.byKey(const ValueKey(0));
      expect(
        find.descendant(
          of: untouched,
          matching: find.byKey(const Key('poster.progress')),
        ),
        findsNothing,
      );

      // Hidden while searching.
      await tester.enterText(find.byKey(const Key('movies.search')), 'movie');
      await tester.pumpAndSettle();
      expect(row, findsNothing);
    });

    testWidgets('the continue watching context menu removes a movie', (
      tester,
    ) async {
      final watch = MemoryWatchStore(
        WatchData.empty.withItems({movieKey(3): _progress(20, at: 1)}),
      );
      await _pump(tester, child: const MoviesScreen(), watch: watch);
      await tester.tap(
        find.byKey(const ValueKey('continue.3')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context.removeContinue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('movies.continue')), findsNothing);
      expect(resumePosition(watch.data.movie(3)), isNull);
    });

    testWidgets('details: provider metadata, resume and marking', (
      tester,
    ) async {
      final watch = MemoryWatchStore(
        WatchData.empty.withItems({movieKey(0): _progress(42)}),
      );
      final source = FakeVodSource(
        movies: syntheticMovies(count: 3),
        movieDetails: {
          0: const Movie(
            streamId: 0,
            name: 'Movie 00000',
            plot: 'A synthetic plot.',
            genre: 'Drama',
            cast: 'Actor One, Actor Two',
            director: 'Director One',
            releaseDate: '2020-05-01',
            rating: 7.5,
            duration: Duration(minutes: 90),
          ),
        },
      );
      await _pump(
        tester,
        child: const MoviesScreen(),
        source: source,
        watch: watch,
      );
      await tester.tap(find.byKey(const ValueKey(0)));
      await tester.pumpAndSettle();

      expect(find.text('2020 · Drama · ★ 7.5 · 1 h 30 min'), findsOneWidget);
      // The title shows once, as the heading; the top bar has only the back
      // arrow.
      expect(find.text('Movie 00000'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('A synthetic plot.'), findsOneWidget);
      expect(find.textContaining('Actor One, Actor Two'), findsOneWidget);
      expect(find.text('Resume from 42:00'), findsOneWidget);
      expect(find.text('Play from start'), findsOneWidget);

      await tester.tap(find.text('Mark as watched'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as unwatched'), findsOneWidget);
      expect(find.byKey(const Key('movie.play')), findsOneWidget);
      expect(find.byKey(const Key('poster.watched')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(watch.data.movie(0)!.watched, isTrue);

      await tester.tap(find.text('Mark as unwatched'));
      await tester.pumpAndSettle();
      expect(watch.data.movie(0)!.watched, isFalse);
      expect(watch.data.movie(0)!.position, Duration.zero);
    });

    testWidgets('M3U providers have no movies', (tester) async {
      await tester.pumpWidget(
        testApp(
          overrides: [
            vodSourceProvider.overrideWithValue(null),
            providerKeyProvider.overrideWithValue('test'),
          ],
          child: const Scaffold(body: MoviesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('available for Xtream'), findsOneWidget);
    });
  });

  group('Series', () {
    WatchData played(List<(int, int)> watched, {(int, int)? started}) {
      var data = markWatched(
        WatchData.empty,
        episodeTargets(_info, [
          for (final (s, e) in watched)
            _info.episodes.firstWhere(
              (x) => x.season == s && x.episodeNumber == e,
            ),
        ]),
        watched: true,
        now: _now,
      );
      if (started case (final s, final e)) {
        final ep = _info.episodes.firstWhere(
          (x) => x.season == s && x.episodeNumber == e,
        );
        data = data.withItems({
          episodeKey(ep.id): WatchProgress(
            position: const Duration(minutes: 10),
            duration: ep.duration,
            seriesId: 0,
            updatedAt: _now.add(const Duration(minutes: 5)),
          ),
        });
      }
      return refreshSeries(data, _info);
    }

    testWidgets('continue watching shows the next unwatched episode', (
      tester,
    ) async {
      await _pump(
        tester,
        child: const SeriesScreen(),
        watch: MemoryWatchStore(played([(1, 1)])),
      );
      final row = find.byKey(const Key('series.continue'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('S01E02 · Episode 1-2')),
        findsOneWidget,
      );
      // The grid card shows the series as started.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(0)),
          matching: find.byKey(const Key('poster.progress')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the continue watching context menu removes a series and '
        'keeps its badge', (tester) async {
      final watch = MemoryWatchStore(played([(1, 1)]));
      await _pump(tester, child: const SeriesScreen(), watch: watch);
      await tester.tap(
        find.byKey(const ValueKey('continue.0')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context.removeContinue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('series.continue')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(0)),
          matching: find.byKey(const Key('poster.progress')),
        ),
        findsOneWidget,
      );
      expect(watch.data.continueRemovals[0]?.removed, isTrue);
    });

    testWidgets('fully watched series get a badge and leave continue '
        'watching', (tester) async {
      await _pump(
        tester,
        child: const SeriesScreen(),
        watch: MemoryWatchStore(
          played([(1, 1), (1, 2), (1, 3), (2, 1), (2, 2)]),
        ),
      );
      expect(find.byKey(const Key('series.continue')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey(0)),
          matching: find.byKey(const Key('poster.watched')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('season tabs: specials last, progress, opens on the next '
        'unwatched season', (tester) async {
      final watch = MemoryWatchStore(
        played([(1, 1), (1, 2), (1, 3)], started: (2, 1)),
      );
      await _pump(tester, child: const SeriesScreen(), watch: watch);
      await tester.tap(find.byKey(const ValueKey(0)));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
        findsNothing,
      );

      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((c) => (c.label as Text).data)
          .toList();
      expect(chips, ['Season 1 · 3/3', 'Season 2 · 0/2', 'Specials · 0/2']);
      // Season 1 is complete.
      expect(
        find.descendant(
          of: find.byKey(const Key('season.1')),
          matching: find.byKey(const Key('season.complete')),
        ),
        findsOneWidget,
      );
      // Season 2 holds the episode in progress, so it is selected, and only
      // its episodes are listed.
      expect(
        tester.widget<ChoiceChip>(find.byKey(const Key('season.2'))).selected,
        isTrue,
      );
      expect(find.text('1. Episode 2-1'), findsOneWidget);
      expect(find.text('1. Episode 1-1'), findsNothing);
      // The episode's plot, under its title, in up to 2 lines.
      expect(find.text('Plot of 2-1.'), findsOneWidget);
      expect(find.text('Resume S02E01 from 10:00'), findsOneWidget);
      final inProgress = find.byKey(const ValueKey('episode.201'));
      expect(
        find.descendant(
          of: inProgress,
          matching: find.byKey(const Key('poster.progress')),
        ),
        findsOneWidget,
      );

      // Season 1: watched episodes are checked and faded.
      await tester.tap(find.byKey(const Key('season.1')));
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('episode.101'));
      expect(
        find.descendant(
          of: first,
          matching: find.byKey(const Key('episode.watched')),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: first, matching: find.byType(Opacity)).first,
            )
            .opacity,
        lessThan(1),
      );

      // Specials have their own tab.
      await tester.tap(find.byKey(const Key('season.0')));
      await tester.pumpAndSettle();
      expect(find.text('1. Episode 0-1'), findsOneWidget);
      expect(find.text('1. Episode 2-1'), findsNothing);
    });

    testWidgets('mark a season and an episode watched or unwatched', (
      tester,
    ) async {
      final watch = MemoryWatchStore();
      await _pump(tester, child: const SeriesScreen(), watch: watch);
      await tester.tap(find.byKey(const ValueKey(0)));
      await tester.pumpAndSettle();
      expect(find.text('Season 1 · 0/3'), findsOneWidget);
      expect(find.text('Play S01E01'), findsOneWidget);

      await tester.tap(find.byKey(const Key('season.menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark season as watched'));
      await tester.pumpAndSettle();
      expect(find.text('Season 1 · 3/3'), findsOneWidget);
      expect(find.byKey(const Key('episode.watched')), findsNWidgets(3));
      expect(find.text('Play S02E01'), findsOneWidget);
      expect(watch.data.series[0]!.nextEpisodeId, '201');

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('episode.102')),
          matching: find.byTooltip('Episode options'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as unwatched'));
      await tester.pumpAndSettle();
      expect(find.text('Season 1 · 2/3'), findsOneWidget);
      expect(watch.data.episode('102')!.watched, isFalse);

      await tester.tap(find.byKey(const Key('season.menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark season as unwatched'));
      await tester.pumpAndSettle();
      expect(find.text('Season 1 · 0/3'), findsOneWidget);
    });
  });

  testWidgets('a cut-off title shows in full on hover; a short one has no '
      'tooltip', (tester) async {
    const long =
        'A Very Long Movie Title That Cannot Possibly Fit On Two Lines '
        'Of A Narrow Poster Card';
    Finder tooltip(String text) =>
        find.byWidgetPredicate((w) => w is Tooltip && w.message == text);
    await tester.pumpWidget(
      testApp(
        overrides: const [],
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final title in [long, 'Short'])
                SizedBox(
                  width: 150,
                  child: PosterCard(title: title, imageUrl: null, onTap: () {}),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tooltip(long), findsOneWidget);
    expect(tooltip('Short'), findsNothing);
  });
}
