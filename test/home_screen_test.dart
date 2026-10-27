import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/search/search_screen.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer/ui/vod/series_details_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 3, 1, 20);

DateTime _ago(Duration d) => _now.subtract(d);

const _categories = [
  Category(id: 'm', name: 'Films'),
  Category(id: 'mh', name: 'Hidden films'),
];

final _movies = VodCatalog.movies(
  categories: _categories,
  items: [
    Movie(
      streamId: 1,
      name: 'Alpha',
      categoryId: 'm',
      rating: 8,
      added: _ago(const Duration(days: 2)),
      plot: 'The first one.',
    ),
    Movie(
      streamId: 2,
      name: 'Bravo',
      categoryId: 'm',
      rating: 7.5,
      added: _ago(const Duration(days: 5)),
    ),
    Movie(
      streamId: 3,
      name: 'Charlie',
      categoryId: 'mh',
      rating: 9,
      added: _ago(const Duration(days: 1)),
    ),
    Movie(
      streamId: 4,
      name: 'Echo',
      categoryId: 'm',
      added: _ago(const Duration(days: 3)),
    ),
  ],
  fetchedAt: _now,
);

Episode _ep(int season, int number) => Episode(
  id: '${season * 100 + number}',
  season: season,
  episodeNumber: number,
  title: 'Episode $season-$number',
  duration: const Duration(minutes: 40),
);

final _series = VodCatalog.series(
  categories: const [Category(id: 's', name: 'Shows')],
  items: [
    Series(
      seriesId: 10,
      name: 'Delta',
      categoryId: 's',
      rating: 9,
      genre: 'Drama',
      lastModified: _ago(const Duration(days: 1)),
      backdropUrls: const ['http://example.com/backdrop.jpg'],
    ),
  ],
  fetchedAt: _now,
);

final _info = SeriesInfo(
  series: _series.items.single,
  seasons: const [],
  episodes: [_ep(1, 1), _ep(1, 2), _ep(2, 1)],
);

/// Hides the provider category of Charlie.
FavouritesData _hidden() => setCategoriesHidden(
  FavouritesData.empty,
  ContentKind.movie,
  ['mh'],
  hidden: true,
  now: _now,
);

class _Setup {
  _Setup({
    WatchData watch = WatchData.empty,
    FavouritesData? favourites,
    AppSettings settings = const AppSettings(),
    this.vod,
  }) : watch = MemoryWatchStore(watch),
       favourites = MemoryFavouritesStore(favourites ?? _hidden()),
       settings = FakeSettingsStorage(settings);

  final MemoryWatchStore watch;
  final MemoryFavouritesStore favourites;
  final FakeSettingsStorage settings;
  final FakeVodSource? vod;
  final player = FakeExternalPlayer();
}

Future<_Setup> _pump(
  WidgetTester tester, {
  _Setup? setup,
  // Tall, so every row is built.
  Size size = const Size(1400, 2400),
}) async {
  final s = setup ?? _Setup();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(s.player.dispose);
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(
          FakeLiveSource(syntheticCatalog(count: 5, categories: 1)),
        ),
        vodSourceProvider.overrideWithValue(
          s.vod ??
              FakeVodSource(
                movies: _movies,
                series: _series,
                seriesInfos: {10: _info},
              ),
        ),
        providerKeyProvider.overrideWithValue('test'),
        useExternalMpvProvider.overrideWithValue(true),
        externalMpvProvider.overrideWithValue(s.player),
        embedMpvProvider.overrideWithValue(false),
      ],
      settings: s.settings,
      watch: s.watch,
      favourites: s.favourites,
      now: _now,
      child: const AppShell(),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

String _featuredTitle(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('home.featured.title')),
        matching: find.byType(Text),
      ),
    )
    .data!;

Finder _row(String id) => find.byKey(Key('home.row.$id'));

/// Lets a player route open (its progress bar animates, so no settle).
Future<void> _openPlayer(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('opens on Home with the rows that have something to show', (
    tester,
  ) async {
    await _pump(tester);
    expect(
      find.textContaining(RegExp('^Good (morning|afternoon|evening)')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home.featured')), findsOneWidget);
    expect(_row('recentMovies'), findsOneWidget);
    expect(_row('recentSeries'), findsOneWidget);
    // No history yet, nothing started.
    expect(_row('channels'), findsNothing);
    expect(_row('continueWatching'), findsNothing);
    // No categories of mine: a hint instead.
    expect(find.byKey(const Key('home.categories.hint')), findsOneWidget);
    // Hidden categories are left out of the recently added movies.
    expect(find.byKey(const ValueKey('home.movie.1')), findsOneWidget);
    expect(find.byKey(const ValueKey('home.movie.3')), findsNothing);
  });

  testWidgets('typing in the search field opens Search with the text', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('home.search')), 'alp');
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('search.field')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'alp');
    expect(field.controller!.selection.baseOffset, 3);
  });

  testWidgets('featured: rated, recent and not hidden; rotates unless '
      'hovered; dots and arrow keys page', (tester) async {
    final setup = await _pump(tester);
    // Movies and series take turns, newest first; Charlie is hidden and
    // Echo has no rating.
    expect(_featuredTitle(tester), 'Alpha');
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(_featuredTitle(tester), 'Delta');
    expect(find.text('Drama · 2 seasons · ★ 9.0'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('home.featured'))),
    );
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(_featuredTitle(tester), 'Delta', reason: 'paused while hovered');

    await tester.tap(find.byKey(const Key('home.featured.dot.2')));
    await tester.pumpAndSettle();
    expect(_featuredTitle(tester), 'Bravo');

    // The click focused the dot; the arrow keys page.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_featuredTitle(tester), 'Alpha');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_featuredTitle(tester), 'Bravo');

    await tester.tap(find.byKey(const Key('home.featured.play')));
    await _openPlayer(tester);
    expect(setup.player.opened.single.url.path, endsWith('/2.mkv'));
  });

  testWidgets('featured Play on a series plays its next episode', (
    tester,
  ) async {
    final setup = await _pump(tester);
    await tester.tap(find.byKey(const Key('home.featured.dot.1')));
    await tester.pumpAndSettle();
    expect(_featuredTitle(tester), 'Delta');
    await tester.tap(find.byKey(const Key('home.featured.play')));
    await _openPlayer(tester);
    expect(setup.player.opened.single.url.path, endsWith('/101.mkv'));
  });

  group('recently viewed channels', () {
    testWidgets('playing a channel adds it; its card plays it again', (
      tester,
    ) async {
      final setup = await _pump(
        tester,
        setup: _Setup(
          watch: recordChannel(
            WatchData.empty,
            '2',
            _ago(const Duration(minutes: 70)),
          ),
        ),
      );
      expect(_row('channels'), findsOneWidget);
      expect(find.text('Channel 0002'), findsOneWidget);
      expect(find.text('Watched 1 h ago'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home.channel.2')));
      await _openPlayer(tester);
      expect(setup.player.opened.single.title, 'Channel 0002');
      final recent = recentChannels(setup.watch.data);
      expect(recent.single.$1, '2');
      expect(
        DateTime.now().toUtc().difference(recent.single.$2),
        lessThan(const Duration(minutes: 1)),
      );
    });

    testWidgets('the context menu removes a channel', (tester) async {
      final setup = await _pump(
        tester,
        setup: _Setup(
          watch: recordChannel(
            recordChannel(WatchData.empty, '1', _ago(const Duration(hours: 2))),
            '3',
            _ago(const Duration(hours: 1)),
          ),
        ),
      );
      expect(find.text('Channel 0001'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('home.channel.1')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context.forgetChannel')));
      await tester.pumpAndSettle();
      expect(find.text('Channel 0001'), findsNothing);
      expect(find.text('Channel 0003'), findsOneWidget);
      expect(recentChannels(setup.watch.data).map((r) => r.$1), ['3']);
    });
  });

  group('continue watching', () {
    WatchData started() {
      var data = WatchData.empty.withItems({
        movieKey(1): WatchProgress(
          position: const Duration(minutes: 30),
          duration: const Duration(minutes: 90),
          updatedAt: _ago(const Duration(hours: 2)),
        ),
        // In a hidden category.
        movieKey(3): WatchProgress(
          position: const Duration(minutes: 30),
          duration: const Duration(minutes: 90),
          updatedAt: _ago(const Duration(hours: 1)),
        ),
      });
      data = markWatched(
        data,
        episodeTargets(_info, [_info.episodes[0]]),
        watched: true,
        now: _ago(const Duration(hours: 3)),
      );
      data = data.withItems({
        episodeKey('102'): WatchProgress(
          position: const Duration(minutes: 22),
          duration: const Duration(minutes: 40),
          seriesId: 10,
          updatedAt: _ago(const Duration(minutes: 30)),
        ),
      });
      return refreshSeries(data, _info);
    }

    testWidgets('movies and episodes together, newest first, without '
        'hidden categories', (tester) async {
      await _pump(tester, setup: _Setup(watch: started()));
      final row = find.byKey(const Key('home.continue'));
      expect(row, findsOneWidget);
      final delta = find.byKey(const ValueKey('home.continue.series.10'));
      final alpha = find.byKey(const ValueKey('home.continue.movie.1'));
      expect(find.byKey(const ValueKey('home.continue.movie.3')), findsNothing);
      expect(
        tester.getTopLeft(delta).dx,
        lessThan(tester.getTopLeft(alpha).dx),
      );
      expect(
        find.descendant(
          of: delta,
          matching: find.text('S1 · E2 · 18 min left'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: alpha, matching: find.text('1 h 00 min left')),
        findsOneWidget,
      );
    });

    testWidgets('a click resumes the movie', (tester) async {
      final setup = await _pump(tester, setup: _Setup(watch: started()));
      await tester.tap(find.byKey(const ValueKey('home.continue.movie.1')));
      await _openPlayer(tester);
      expect(setup.player.opened.single.url.path, endsWith('/1.mkv'));
      expect(setup.player.opened.single.start, const Duration(minutes: 30));
    });

    testWidgets('Enter resumes the episode', (tester) async {
      final setup = await _pump(tester, setup: _Setup(watch: started()));
      // The focus of the card's InkWell, around its title.
      final title = find.descendant(
        of: find.byKey(const ValueKey('home.continue.series.10')),
        matching: find.text('Delta'),
      );
      Focus.of(tester.element(title)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _openPlayer(tester);
      expect(setup.player.opened.single.url.path, endsWith('/102.mkv'));
      expect(setup.player.opened.single.start, const Duration(minutes: 22));
    });

    testWidgets('the context menu opens the details', (tester) async {
      await _pump(tester, setup: _Setup(watch: started()));
      await tester.tap(
        find.byKey(const ValueKey('home.continue.series.10')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('context.favourites')), findsOneWidget);
      await tester.tap(find.byKey(const Key('context.details')));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesDetailsScreen), findsOneWidget);
    });

    Future<void> removeVia(WidgetTester tester, Finder card) async {
      await tester.tap(card, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context.removeContinue')));
      await tester.pumpAndSettle();
    }

    testWidgets('the context menu removes a movie; Undo brings it back', (
      tester,
    ) async {
      final setup = await _pump(tester, setup: _Setup(watch: started()));
      const alpha = ValueKey('home.continue.movie.1');
      await removeVia(tester, find.byKey(alpha));
      expect(find.byKey(alpha), findsNothing);
      expect(
        find.text('Removed “Alpha” from Continue watching'),
        findsOneWidget,
      );
      expect(continueMovies(setup.watch.data).map((m) => m.$1), [3]);
      expect(resumePosition(setup.watch.data.movie(1)), isNull);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(alpha), findsOneWidget);
      expect(
        resumePosition(setup.watch.data.movie(1)),
        const Duration(minutes: 30),
      );
    });

    testWidgets('the Undo snack bar closes after 6 s', (tester) async {
      await _pump(tester, setup: _Setup(watch: started()));
      await removeVia(
        tester,
        find.byKey(const ValueKey('home.continue.movie.1')),
      );
      final bar = find.byKey(const Key('continue.removed'));
      expect(bar, findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(bar, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });

    testWidgets('the Undo snack bar closes when another page opens', (
      tester,
    ) async {
      await _pump(tester, setup: _Setup(watch: started()));
      final bar = find.byKey(const Key('continue.removed'));
      await removeVia(
        tester,
        find.byKey(const ValueKey('home.continue.movie.1')),
      );
      expect(bar, findsOneWidget);
      // A page opened over Home.
      await tester.tap(
        find.byKey(const Key('home.row.continueWatching.seeAll')),
      );
      await tester.pumpAndSettle();
      expect(bar, findsNothing);

      // Back on Home, then another section of the sidebar.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await removeVia(
        tester,
        find.byKey(const ValueKey('home.continue.series.10')),
      );
      expect(bar, findsOneWidget);
      await tester.tap(find.text('Live TV'));
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    });

    testWidgets('removing a series keeps its watched episodes; Undo brings '
        'it back', (tester) async {
      final setup = await _pump(tester, setup: _Setup(watch: started()));
      const delta = ValueKey('home.continue.series.10');
      await removeVia(tester, find.byKey(delta));
      expect(find.byKey(delta), findsNothing);
      expect(continueSeries(setup.watch.data), isEmpty);
      expect(setup.watch.data.episode('101')!.watched, isTrue);
      expect(setup.watch.data.series[10], isNotNull);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(delta), findsOneWidget);
      expect(continueSeries(setup.watch.data), hasLength(1));
    });

    testWidgets('See all opens every started item with type chips', (
      tester,
    ) async {
      await _pump(tester, setup: _Setup(watch: started()));
      await tester.tap(
        find.byKey(const Key('home.row.continueWatching.seeAll')),
      );
      await tester.pumpAndSettle();
      final grid = find.byKey(const Key('continue.grid'));
      expect(grid, findsOneWidget);
      Finder card(String key) =>
          find.descendant(of: grid, matching: find.byKey(ValueKey(key)));
      final delta = card('home.continue.series.10');
      final alpha = card('home.continue.movie.1');
      expect(delta, findsOneWidget);
      expect(alpha, findsOneWidget);
      expect(card('home.continue.movie.3'), findsNothing, reason: 'hidden');
      expect(
        tester.getTopLeft(delta).dx,
        lessThan(tester.getTopLeft(alpha).dx),
      );

      await tester.tap(find.byKey(const Key('continue.filter.movies')));
      await tester.pumpAndSettle();
      expect(delta, findsNothing);
      expect(alpha, findsOneWidget);
      await tester.tap(find.byKey(const Key('continue.filter.series')));
      await tester.pumpAndSettle();
      expect(delta, findsOneWidget);
      expect(alpha, findsNothing);

      // Removing from the page; the filter shows the empty note.
      await removeVia(tester, delta);
      expect(find.byKey(const Key('continue.empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('continue.filter.all')));
      await tester.pumpAndSettle();
      expect(alpha, findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(grid, findsNothing);
      expect(
        find.byKey(const ValueKey('home.continue.series.10')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('home.continue.movie.1')),
        findsOneWidget,
      );
    });

    testWidgets('the See all page fits at text scale 1.4', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        size: const Size(1000, 700),
        setup: _Setup(watch: started()),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('home.row.continueWatching.seeAll')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('home.scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(
        find.byKey(const Key('home.row.continueWatching.seeAll')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('continue.grid')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a category tile opens its section with it selected', (
    tester,
  ) async {
    final (withCategory, sport) = createCategory(
      _hidden(),
      kind: ContentKind.live,
      name: 'Sport',
      icon: 'sport',
      now: _now,
    );
    final favourites = setMembership(
      withCategory,
      sport!.id,
      const ItemRef(ContentKind.live, '4'),
      name: 'Channel 0004',
      member: true,
      now: _now,
    );
    await _pump(tester, setup: _Setup(favourites: favourites));
    final tile = find.byKey(Key('home.category.${sport.id}'));
    expect(find.descendant(of: tile, matching: find.text('LIVE TV')), findsOne);
    expect(
      find.descendant(of: tile, matching: find.text('1 channel')),
      findsOne,
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(LiveTvScreen), findsOneWidget);
    expect(find.text('Channel 0004'), findsOneWidget);
    expect(find.text('Channel 0001'), findsNothing);
  });

  testWidgets('See all opens Movies with All and Recently added', (
    tester,
  ) async {
    final setup = await _pump(
      tester,
      setup: _Setup(settings: const AppSettings(movieSort: VodSort.title)),
    );
    await tester.tap(find.byKey(const Key('home.row.recentMovies.seeAll')));
    await tester.pumpAndSettle();
    expect(find.byType(MoviesScreen), findsOneWidget);
    expect(setup.settings.saved.movieSort, VodSort.recent);
    expect(find.text('All movies'), findsWidgets);
  });

  testWidgets('Edit home moves and hides rows, saved in settings', (
    tester,
  ) async {
    final setup = await _pump(tester);
    expect(find.byKey(const Key('home.row.featured.up')), findsNothing);
    await tester.tap(find.byKey(const Key('home.edit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home.row.featured.visible')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('home.row.recentMovies.up')),
    );
    await tester.tap(find.byKey(const Key('home.row.recentMovies.up')));
    await tester.pumpAndSettle();
    final rows = setup.settings.saved.homeLayout.rows;
    expect(rows.first, const HomeRow(HomeRowId.featured, visible: false));
    expect(rows.map((r) => r.id).skip(4), [
      HomeRowId.recentMovies,
      HomeRowId.recentSeries,
    ]);

    await tester.tap(find.byKey(const Key('home.edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home.featured')), findsNothing);
    expect(
      tester.getTopLeft(_row('recentMovies')).dy,
      lessThan(tester.getTopLeft(_row('recentSeries')).dy),
    );
  });

  testWidgets('rows show placeholders until the catalogues are loaded', (
    tester,
  ) async {
    final source = _SlowVodSource();
    await _pump(tester, setup: _Setup(vod: source));
    expect(find.byKey(const Key('home.placeholder')), findsWidgets);
    expect(find.byKey(const Key('home.featured')), findsNothing);
    source.release();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home.placeholder')), findsNothing);
    expect(find.byKey(const Key('home.featured')), findsOneWidget);
  });

  for (final (size, scale) in [
    (const Size(1000, 700), 1.4),
    // A phone in portrait: the phone layout.
    (const Size(412, 915), 1.4),
    (const Size(412, 915), 2.0),
  ]) {
    testWidgets('fits at text scale $scale in a ${size.width.round()} wide '
        'window', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (withCategory, _) = createCategory(
        _hidden(),
        kind: ContentKind.movie,
        name: 'Favourite films with a long name',
        icon: 'movie',
        now: _now,
      );
      await _pump(
        tester,
        size: size,
        setup: _Setup(
          favourites: withCategory,
          watch: recordChannel(WatchData.empty, '1', _now).withItems({
            movieKey(1): WatchProgress(
              position: const Duration(minutes: 30),
              duration: const Duration(minutes: 90),
              updatedAt: _now,
            ),
          }),
        ),
      );
      for (final id in HomeRowId.values) {
        await tester.scrollUntilVisible(
          _row(id.name),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('home.scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: id.name);
      }
      // The series has a backdrop: the other banner layout.
      await tester.scrollUntilVisible(
        find.byKey(const Key('home.featured.dot.1')),
        -200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('home.scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Fully on screen, so the tap hits it.
      await tester.ensureVisible(find.byKey(const Key('home.featured.dot.1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home.featured.dot.1')));
      await tester.pumpAndSettle();
      expect(_featuredTitle(tester), 'Delta');
      expect(tester.takeException(), isNull);
    });
  }
}

/// [FakeVodSource] whose catalogues arrive on [release].
class _SlowVodSource extends FakeVodSource {
  _SlowVodSource()
    : super(movies: _movies, series: _series, seriesInfos: {10: _info});

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<VodCatalog<Movie>> loadMovies({required DateTime now}) async {
    await _gate.future;
    return super.loadMovies(now: now);
  }

  @override
  Future<VodCatalog<Series>> loadSeries({required DateTime now}) async {
    await _gate.future;
    return super.loadSeries(now: now);
  }
}
