import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer/ui/vod/series_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

final _now = DateTime.utc(2026, 3, 1, 20);

/// Made-up movies: "Copper Valley" four times (EN twice), one in a hidden
/// category, and an unrelated movie.
final _movies = VodCatalog.movies(
  categories: const [
    Category(id: 'm', name: 'Films'),
    Category(id: 'x', name: 'Hidden films'),
  ],
  items: [
    Movie(
      streamId: 1,
      name: 'NF - Copper Valley (2024)',
      categoryId: 'm',
      tmdbId: '501',
      added: DateTime.utc(2025, 3, 2, 10),
    ),
    Movie(
      streamId: 2,
      name: 'EN - Copper Valley (2024)',
      categoryId: 'm',
      tmdbId: '501',
      added: DateTime.utc(2025, 4, 24, 10),
    ),
    Movie(
      streamId: 3,
      name: 'EN - Copper Valley  (2024)',
      categoryId: 'm',
      tmdbId: '501',
      added: DateTime.utc(2025, 2, 28, 10),
    ),
    Movie(
      streamId: 4,
      name: '4K-NF - Copper Valley (2024)',
      categoryId: 'x',
      tmdbId: '501',
    ),
    for (var i = 0; i < 3; i++) ...[
      Movie(streamId: 10 + i, name: 'NF - Other $i', categoryId: 'm'),
      Movie(streamId: 20 + i, name: 'EN - Other $i', categoryId: 'm'),
      Movie(streamId: 30 + i, name: '4K-NF - Other $i', categoryId: 'm'),
    ],
  ],
  fetchedAt: DateTime.utc(2026),
);

final _series = VodCatalog.series(
  categories: const [Category(id: 's', name: 'Shows')],
  items: [
    Series(
      seriesId: 1,
      name: 'NF - Bramble Lane (2025)',
      categoryId: 's',
      tmdbId: '77',
    ),
    Series(
      seriesId: 2,
      name: 'EN - Bramble Lane (2025)',
      categoryId: 's',
      tmdbId: '77',
    ),
    for (var i = 0; i < 3; i++) ...[
      Series(seriesId: 10 + i, name: 'NF - Show $i', categoryId: 's'),
      Series(seriesId: 20 + i, name: 'EN - Show $i', categoryId: 's'),
    ],
  ],
  fetchedAt: DateTime.utc(2026),
);

SeriesInfo _info(int seriesId, int base) => SeriesInfo(
  series: _series.items.firstWhere((s) => s.seriesId == seriesId),
  seasons: const [],
  episodes: [
    for (var n = 1; n <= 3; n++)
      Episode(
        id: '${base + n}',
        season: 1,
        episodeNumber: n,
        title: 'Chapter $n',
        duration: const Duration(minutes: 40),
      ),
  ],
);

WatchProgress _progress(
  int minutes, {
  int? seriesId,
  int? episode,
  bool watched = false,
  int at = 0,
}) => WatchProgress(
  position: Duration(minutes: minutes),
  duration: Duration(minutes: seriesId == null ? 90 : 40),
  watched: watched,
  seriesId: seriesId,
  season: episode == null ? null : 1,
  episode: episode,
  updatedAt: _now.subtract(Duration(hours: 1)).add(Duration(minutes: at)),
);

Future<MemoryWatchStore> _pump(
  WidgetTester tester,
  Widget child, {
  WatchData watch = WatchData.empty,
  double scale = 1.4,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final store = MemoryWatchStore(watch);
  await tester.pumpWidget(
    testApp(
      overrides: [
        vodSourceProvider.overrideWithValue(
          FakeVodSource(
            movies: _movies,
            series: _series,
            seriesInfos: {1: _info(1, 100), 2: _info(2, 200)},
          ),
        ),
        providerKeyProvider.overrideWithValue('test'),
      ],
      watch: store,
      favourites: MemoryFavouritesStore(
        setCategoriesHidden(
          FavouritesData.empty,
          ContentKind.movie,
          ['x'],
          hidden: true,
          now: _now,
        ),
      ),
      now: _now,
      child: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> _open(WidgetTester tester, int id) async {
  await tester.tap(find.byKey(ValueKey(id)).first);
  await tester.pumpAndSettle();
}

Finder _inSources(Finder finder) => find.descendant(
  of: find.byKey(const Key('details.sources')),
  matching: finder,
);

void main() {
  testWidgets('a movie lists its other sources with labels and tells same '
      'labels apart by date', (tester) async {
    await _pump(
      tester,
      const MoviesScreen(),
      watch: WatchData(played: {movieKey(3): _now}),
    );
    await _open(tester, 1);
    expect(tester.takeException(), isNull);
    expect(find.text('Other sources'), findsOneWidget);
    // Not itself, not the one in a hidden category.
    expect(_inSources(find.byKey(const ValueKey('source.1'))), findsNothing);
    expect(_inSources(find.byKey(const ValueKey('source.4'))), findsNothing);
    // The one played last comes first, with its marker.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('source.3'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('source.2'))).dx),
    );
    expect(_inSources(find.text('EN')), findsNWidgets(2));
    expect(
      _inSources(find.textContaining('Added 28 Feb 2025')),
      findsOneWidget,
    );
    expect(_inSources(find.text('Added 24 Apr 2025')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('source.3')),
        matching: find.byKey(const Key('poster.subtitleIcon')),
      ),
      findsOneWidget,
    );
    // This page's own label is its own: no date in the facts.
    expect(find.text('2024'), findsWidgets);
    expect(find.byKey(const Key('details.lastPlayed')), findsNothing);
  });

  testWidgets('movie sources share resume, watched and continue watching', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      const MoviesScreen(),
      watch: WatchData(items: {movieKey(1): _progress(30, at: 5)}),
    );
    // One card for the group in Continue watching.
    expect(find.byKey(const ValueKey('continue.1')), findsOneWidget);
    // The other source shows the same progress.
    await _open(tester, 2);
    expect(find.text('Resume from 30:00 (from NF)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('movie.markWatched')));
    await tester.pumpAndSettle();
    expect(store.data.movie(1)!.watched, isTrue);
    expect(store.data.movie(3)!.watched, isTrue);
  });

  testWidgets('"Mark as unwatched" on an episode in progress in another '
      'source resets it everywhere', (tester) async {
    final store = await _pump(
      tester,
      const SeriesScreen(),
      watch: WatchData(
        items: {
          episodeKey('101'): _progress(12, seriesId: 1, episode: 1, at: 2),
        },
        played: {seriesKey(1): _now},
      ),
    );
    await _open(tester, 2);
    expect(find.text('Resume S01E01 from 12:00 (from NF)'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('episode.201')),
        matching: find.byTooltip('Episode options'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('episode.markWatched')), findsOneWidget);
    await tester.tap(find.byKey(const Key('episode.markUnwatched')));
    await tester.pumpAndSettle();
    expect(find.text('Play S01E01'), findsOneWidget);
    expect(store.data.episode('101')!.position, Duration.zero);
    expect(store.data.episode('201')!.position, Duration.zero);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('episode.201')),
        matching: find.byKey(const Key('poster.progress')),
      ),
      findsNothing,
    );
  });

  testWidgets('"Mark as unwatched" on a started movie resets all its '
      'sources', (tester) async {
    final store = await _pump(
      tester,
      const MoviesScreen(),
      watch: WatchData(items: {movieKey(1): _progress(30, at: 5)}),
    );
    await _open(tester, 2);
    await tester.tap(find.byKey(const Key('movie.markUnwatched')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('movie.play')), findsOneWidget);
    expect(find.byKey(const Key('movie.markUnwatched')), findsNothing);
    expect(store.data.movie(1)!.position, Duration.zero);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('continue.1')), findsNothing);
  });

  testWidgets('"Reset progress" (long press on Resume) resets a movie '
      'in all its sources, with Undo', (tester) async {
    final store = await _pump(
      tester,
      const MoviesScreen(),
      watch: WatchData(items: {movieKey(1): _progress(30, at: 5)}),
    );
    await _open(tester, 2);
    await tester.longPress(find.byKey(const Key('movie.resume')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('resume.reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('movie.play')), findsOneWidget);
    expect(store.data.movie(1)!.position, Duration.zero);
    expect(find.byKey(const Key('progress.reset')), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Resume from 30:00 (from NF)'), findsOneWidget);
    expect(store.data.movie(1)!.position, const Duration(minutes: 30));
  });

  testWidgets('series sources share episode state by season and episode', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      const SeriesScreen(),
      watch: WatchData(
        items: {
          episodeKey('101'): _progress(
            40,
            seriesId: 1,
            episode: 1,
            watched: true,
            at: 1,
          ),
          episodeKey('102'): _progress(12, seriesId: 1, episode: 2, at: 2),
        },
        played: {seriesKey(1): _now},
      ),
    );
    await _open(tester, 2);
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('episode.201')),
        matching: find.byKey(const Key('episode.watched')),
      ),
      findsOneWidget,
    );
    expect(find.text('Resume S01E02 from 12:00 (from NF)'), findsOneWidget);
    expect(find.text('Season 1 · 1/3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('season.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark season as unwatched'));
    await tester.pumpAndSettle();
    expect(store.data.episode('101')!.watched, isFalse);
    expect(find.text('Season 1 · 0/3'), findsOneWidget);

    // The NF source was played last.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source.1')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('series.scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('source.1')),
        matching: find.byKey(const Key('poster.subtitleIcon')),
      ),
      findsOneWidget,
    );
  });
}
