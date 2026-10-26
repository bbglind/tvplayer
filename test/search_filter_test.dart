import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/search/search_screen.dart';
import 'package:tvplayer/ui/vod/movie_details_screen.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer/ui/vod/poster.dart';
import 'package:tvplayer/ui/vod/series_details_screen.dart';
import 'package:tvplayer/ui/vod/series_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

final _now = DateTime.utc(2026, 3, 1, 20);

DateTime _day(int d) => DateTime.utc(2026, 1, d);

final _movies = VodCatalog.movies(
  categories: const [
    Category(id: 'm0', name: 'Drama shelf'),
    Category(id: 'm1', name: 'Kids'),
    Category(id: 'm2', name: 'Thrillers'),
  ],
  items: [
    Movie(
      streamId: 1,
      name: '4K-TOP - Lantern Harbour (2026)',
      categoryId: 'm0',
      added: _day(5),
      rating: 7,
    ),
    Movie(
      streamId: 2,
      name: 'EN - Apple Orchard (2024)',
      categoryId: 'm1',
      added: _day(9),
      rating: 0,
    ),
    Movie(
      streamId: 3,
      name: 'Ébène Nights (2019) (FR)',
      categoryId: 'm0',
      added: _day(1),
      rating: 8.5,
    ),
    const Movie(streamId: 4, name: 'Mango Season', categoryId: 'm1'),
    Movie(
      streamId: 5,
      name: 'SC - Bramble Harbour (2025)',
      categoryId: 'm2',
      added: _day(3),
      rating: 6,
    ),
  ],
  fetchedAt: _now,
);

final _series = VodCatalog.series(
  categories: const [
    Category(id: 's0', name: 'Shows'),
    Category(id: 's1', name: 'Hidden shows'),
  ],
  items: [
    Series(
      seriesId: 10,
      name: 'Harbour Lights (2010)',
      categoryId: 's0',
      genre: 'Crime / Drama / Mystery',
      releaseDate: '2021-03-04',
      lastModified: _day(2),
      rating: 8,
    ),
    Series(
      seriesId: 11,
      name: 'Sky Pirates',
      categoryId: 's0',
      genre: 'Action & Adventure / Mystery',
      releaseDate: '2025-06-01',
      lastModified: _day(5),
    ),
    const Series(
      seriesId: 12,
      name: 'Kitchen Wars (2025)',
      categoryId: 's0',
      genre: 'Reality',
    ),
    const Series(seriesId: 13, name: 'Harbour Secrets', categoryId: 's1'),
  ],
  fetchedAt: _now,
);

LiveCatalog _live({int extra = 0}) => LiveCatalog(
  categories: const [
    Category(id: 'se', name: 'Sweden'),
    Category(id: 'xx', name: 'Secret'),
  ],
  channels: [
    const LiveStream(id: '1', name: 'SVT 1 HD', categoryIds: ['se']),
    const LiveStream(id: '2', name: 'Harbour TV', categoryIds: ['se']),
    const LiveStream(id: '3', name: 'Harbour Hidden', categoryIds: ['xx']),
    for (var i = 0; i < extra; i++)
      LiveStream(
        id: '${10 + i}',
        name: 'Harbour Extra $i',
        categoryIds: ['se'],
      ),
  ],
);

/// Favourites with the provider categories [movies], [series] and [live]
/// hidden.
FavouritesData _hidden({
  Set<String> live = const {},
  Set<String> movies = const {},
  Set<String> series = const {},
}) {
  var data = FavouritesData.empty;
  for (final (kind, ids) in [
    (ContentKind.live, live),
    (ContentKind.movie, movies),
    (ContentKind.series, series),
  ]) {
    data = setCategoriesHidden(data, kind, ids, hidden: true, now: _now);
  }
  return data;
}

Widget _scaled(Widget child, double scale) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

Future<FakeSettingsStorage> _pump(
  WidgetTester tester,
  Widget screen, {
  AppSettings settings = const AppSettings(),
  FavouritesData? favourites,
  FakeLiveSource? live,
  FakeExternalPlayer? player,
  Size size = const Size(1400, 900),
  double textScale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final storage = FakeSettingsStorage(settings);
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(live ?? FakeLiveSource(_live())),
        vodSourceProvider.overrideWithValue(
          FakeVodSource(
            movies: _movies,
            series: _series,
            seriesInfos: {
              10: SeriesInfo(
                series: _series.items.first,
                seasons: const [],
                episodes: const [],
              ),
            },
          ),
        ),
        providerKeyProvider.overrideWithValue('test'),
        useExternalMpvProvider.overrideWithValue(true),
        if (player != null) externalMpvProvider.overrideWithValue(player),
        embedMpvProvider.overrideWithValue(false),
      ],
      settings: storage,
      favourites: MemoryFavouritesStore(favourites),
      now: _now,
      child: Scaffold(body: _scaled(screen, textScale)),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return storage;
}

/// Titles of the posters in the grid of [section], in order.
List<String> _grid(WidgetTester tester, String section) => [
  for (final p in tester.widgetList<PosterCard>(
    find.descendant(
      of: find.byKey(Key('$section.grid')),
      matching: find.byType(PosterCard),
    ),
  ))
    p.title,
];

Future<void> _tapKey(WidgetTester tester, String key) async {
  // A CheckboxMenuButton passes its key on to the button inside it.
  await tester.tap(find.byKey(Key(key)).first);
  await tester.pumpAndSettle();
}

/// Whether keyboard focus is inside [finder].
bool _focusIn(WidgetTester tester, Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final element = tester.element(finder);
  if (context == element) return true;
  var inside = false;
  context.visitAncestorElements((e) {
    inside = e == element;
    return !inside;
  });
  return inside;
}

void main() {
  group('Movies and series: sort', () {
    testWidgets('recently added by default; A–Z and top rated, remembered', (
      tester,
    ) async {
      final settings = await _pump(tester, const MoviesScreen());
      expect(find.text('Recently added'), findsOneWidget);
      expect(_grid(tester, 'movies'), [
        'EN - Apple Orchard (2024)',
        '4K-TOP - Lantern Harbour (2026)',
        'SC - Bramble Harbour (2025)',
        'Ébène Nights (2019) (FR)',
        'Mango Season',
      ]);

      await _tapKey(tester, 'movies.sort');
      await _tapKey(tester, 'movies.sort.title');
      // By title without the tag; É sorts as E.
      expect(_grid(tester, 'movies'), [
        'EN - Apple Orchard (2024)',
        'SC - Bramble Harbour (2025)',
        'Ébène Nights (2019) (FR)',
        '4K-TOP - Lantern Harbour (2026)',
        'Mango Season',
      ]);
      expect(settings.saved.movieSort, VodSort.title);
      expect(settings.saved.seriesSort, VodSort.recent);

      await _tapKey(tester, 'movies.sort');
      await _tapKey(tester, 'movies.sort.rating');
      // Unrated (0 or none) last.
      expect(_grid(tester, 'movies'), [
        'Ébène Nights (2019) (FR)',
        '4K-TOP - Lantern Harbour (2026)',
        'SC - Bramble Harbour (2025)',
        'EN - Apple Orchard (2024)',
        'Mango Season',
      ]);
      expect(find.text('Top rated'), findsOneWidget);
    });

    testWidgets('series say "Recently updated" and start with the saved '
        'sort', (tester) async {
      await _pump(
        tester,
        const SeriesScreen(),
        settings: const AppSettings(seriesSort: VodSort.rating),
      );
      expect(find.text('Top rated'), findsOneWidget);
      expect(_grid(tester, 'series').first, 'Harbour Lights (2010)');

      await _tapKey(tester, 'series.sort');
      expect(find.text('Recently updated'), findsOneWidget);
      await _tapKey(tester, 'series.sort.recent');
      expect(_grid(tester, 'series'), [
        'Sky Pirates',
        'Harbour Lights (2010)',
        'Kitchen Wars (2025)',
        'Harbour Secrets',
      ]);
    });
  });

  group('Movies and series: filters', () {
    testWidgets('year quick picks, custom range, count and reset', (
      tester,
    ) async {
      await _pump(tester, const MoviesScreen());
      expect(find.text('5 movies'), findsOneWidget);
      final reset = find.byKey(const Key('movies.filters.reset'));
      expect(reset, findsNothing);

      await _tapKey(tester, 'movies.year');
      await _tapKey(tester, 'movies.year.2');
      // 2025 and 2026; the movie without a year is left out.
      expect(_grid(tester, 'movies'), [
        '4K-TOP - Lantern Harbour (2026)',
        'SC - Bramble Harbour (2025)',
      ]);
      expect(find.text('2 movies'), findsOneWidget);
      expect(find.text('Last 2 years'), findsOneWidget);
      expect(reset, findsOneWidget);

      await _tapKey(tester, 'movies.year');
      await _tapKey(tester, 'movies.year.1');
      expect(_grid(tester, 'movies'), ['4K-TOP - Lantern Harbour (2026)']);
      expect(find.text('1 movie'), findsOneWidget);

      await _tapKey(tester, 'movies.year');
      await _tapKey(tester, 'movies.year.custom');
      await tester.enterText(find.byKey(const Key('year.from')), '2024');
      await tester.enterText(find.byKey(const Key('year.to')), '2019');
      await _tapKey(tester, 'year.apply');
      expect(find.byKey(const Key('year.error')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('year.from')), '2019');
      await tester.enterText(find.byKey(const Key('year.to')), '2024');
      await _tapKey(tester, 'year.apply');
      expect(_grid(tester, 'movies'), [
        'EN - Apple Orchard (2024)',
        'Ébène Nights (2019) (FR)',
      ]);
      expect(find.text('2019–2024'), findsOneWidget);

      // An open end.
      await _tapKey(tester, 'movies.year');
      await _tapKey(tester, 'movies.year.custom');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('year.from')))
            .controller!
            .text,
        '2019',
      );
      await tester.enterText(find.byKey(const Key('year.to')), '');
      await _tapKey(tester, 'year.apply');
      expect(find.text('From 2019'), findsOneWidget);
      expect(find.text('5 movies'), findsNothing);
      expect(find.text('4 movies'), findsOneWidget);

      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.text('5 movies'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
      expect(reset, findsNothing);
    });

    testWidgets('series genres: multi-select, any of them; movies have no '
        'genre filter yet', (tester) async {
      await _pump(tester, const SeriesScreen());
      await _tapKey(tester, 'series.genre');
      expect(find.text('Action & Adventure'), findsOneWidget);
      await _tapKey(tester, 'series.genre.Mystery');
      // The menu stays open while ticking.
      await _tapKey(tester, 'series.genre.Reality');
      await _tapKey(tester, 'series.genre.done');
      expect(_grid(tester, 'series'), [
        'Sky Pirates',
        'Harbour Lights (2010)',
        'Kitchen Wars (2025)',
      ]);
      expect(find.text('2 genres'), findsOneWidget);
      expect(find.text('3 series'), findsOneWidget);

      await _tapKey(tester, 'series.genre');
      await _tapKey(tester, 'series.genre.Reality');
      await _tapKey(tester, 'series.genre.done');
      expect(find.text('Mystery'), findsOneWidget);

      // Year from the release date, not the title: Harbour Lights is 2021.
      await _tapKey(tester, 'series.year');
      await _tapKey(tester, 'series.year.custom');
      await tester.enterText(find.byKey(const Key('year.from')), '2021');
      await tester.enterText(find.byKey(const Key('year.to')), '2021');
      await _tapKey(tester, 'year.apply');
      expect(_grid(tester, 'series'), ['Harbour Lights (2010)']);

      await _tapKey(tester, 'series.filters.reset');
      expect(find.text('4 series'), findsOneWidget);

      await _pump(tester, const MoviesScreen());
      expect(find.byKey(const Key('movies.genre')), findsNothing);
    });

    testWidgets('filters apply with the category; continue watching hides '
        'while filtering', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      await _pump(tester, const MoviesScreen());
      await tester.tap(find.text('Drama shelf'));
      await tester.pumpAndSettle();
      expect(find.text('2 movies'), findsOneWidget);
      await _tapKey(tester, 'movies.year');
      await _tapKey(tester, 'movies.year.5');
      expect(_grid(tester, 'movies'), ['4K-TOP - Lantern Harbour (2026)']);
    });
  });

  group('local search', () {
    testWidgets('searches the whole section; "Only in" limits it to the '
        'category', (tester) async {
      await _pump(tester, const MoviesScreen());
      await tester.tap(find.text('Kids'));
      await tester.pumpAndSettle();
      expect(find.text('2 movies'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('movies.search')), 'HARBOUR');
      await tester.pumpAndSettle();
      // Neither is in Kids.
      expect(_grid(tester, 'movies'), [
        '4K-TOP - Lantern Harbour (2026)',
        'SC - Bramble Harbour (2025)',
      ]);
      expect(find.text('Only in Kids'), findsOneWidget);

      await _tapKey(tester, 'movies.onlyIn');
      expect(_grid(tester, 'movies'), isEmpty);
      expect(find.text('No movies found'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('movies.search')), 'orchard');
      await tester.pumpAndSettle();
      expect(_grid(tester, 'movies'), ['EN - Apple Orchard (2024)']);

      // The provider tag isn't searched; accents are ignored.
      await _tapKey(tester, 'movies.onlyIn');
      await tester.enterText(find.byKey(const Key('movies.search')), 'top');
      await tester.pumpAndSettle();
      expect(_grid(tester, 'movies'), isEmpty);
      await tester.enterText(find.byKey(const Key('movies.search')), 'ebene');
      await tester.pumpAndSettle();
      expect(_grid(tester, 'movies'), ['Ébène Nights (2019) (FR)']);
    });

    testWidgets('clicking a category while searching clears the search', (
      tester,
    ) async {
      await _pump(tester, const MoviesScreen());
      final search = find.byKey(const Key('movies.search'));
      await tester.enterText(search, 'HARBOUR');
      await tester.pumpAndSettle();
      expect(_grid(tester, 'movies'), hasLength(2));

      await tester.tap(find.text('Kids'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: search, matching: find.byType(TextField)),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(find.byKey(const Key('movies.onlyIn')), findsNothing);
      expect(find.text('2 movies'), findsOneWidget);
    });

    testWidgets('search, sort and filters apply together', (tester) async {
      await _pump(tester, const MoviesScreen());
      await tester.enterText(find.byKey(const Key('movies.search')), 'harbour');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'movies.sort');
      await _tapKey(tester, 'movies.sort.title');
      expect(_grid(tester, 'movies'), [
        'SC - Bramble Harbour (2025)',
        '4K-TOP - Lantern Harbour (2026)',
      ]);
      await _tapKey(tester, 'movies.year');
      await _tapKey(tester, 'movies.year.1');
      expect(_grid(tester, 'movies'), ['4K-TOP - Lantern Harbour (2026)']);
    });
  });

  group('Search page', () {
    late FakeExternalPlayer player;

    setUp(() => player = FakeExternalPlayer());
    tearDown(() => player.dispose());

    testWidgets('the field is focused; results are grouped with counts; '
        'hidden categories are left out', (tester) async {
      await _pump(
        tester,
        const SearchScreen(),
        player: player,
        favourites: _hidden(live: {'xx'}, movies: {'m2'}, series: {'s1'}),
      );
      expect(find.text('Find channels, movies and series'), findsOneWidget);
      expect(_focusIn(tester, find.byKey(const Key('search.field'))), isTrue);

      await tester.enterText(find.byKey(const Key('search.field')), 'harbour');
      await tester.pumpAndSettle();
      expect(find.text('Harbour TV'), findsOneWidget);
      expect(find.text('Harbour Hidden'), findsNothing);
      expect(find.text('4K-TOP - Lantern Harbour (2026)'), findsOneWidget);
      expect(find.text('SC - Bramble Harbour (2025)'), findsNothing);
      expect(find.text('Harbour Lights (2010)'), findsOneWidget);
      expect(find.text('Harbour Secrets'), findsNothing);
      for (final g in ['live', 'movies', 'series']) {
        expect(
          tester.widget<Text>(find.byKey(Key('search.$g.count'))).data,
          '1',
        );
      }
      // Favourite stars on results.
      expect(find.byKey(const Key('favourite.star')), findsNWidgets(3));

      await tester.enterText(find.byKey(const Key('search.field')), 'svt1');
      await tester.pumpAndSettle();
      expect(find.text('SVT 1 HD'), findsOneWidget);
      expect(find.text('No movies found'), findsOneWidget);
      expect(find.text('No series found'), findsOneWidget);
    });

    testWidgets('the setting shows hidden categories', (tester) async {
      await _pump(
        tester,
        const SearchScreen(),
        player: player,
        settings: const AppSettings(showHiddenInGlobalSearch: true),
        favourites: _hidden(live: {'xx'}, movies: {'m2'}, series: {'s1'}),
      );
      await tester.enterText(find.byKey(const Key('search.field')), 'harbour');
      await tester.pumpAndSettle();
      expect(find.text('Harbour Hidden'), findsOneWidget);
      expect(find.text('SC - Bramble Harbour (2025)'), findsOneWidget);
      expect(find.text('Harbour Secrets'), findsOneWidget);
    });

    testWidgets('"Show all" lists a whole group; back and Esc return', (
      tester,
    ) async {
      await _pump(
        tester,
        const SearchScreen(),
        player: player,
        live: FakeLiveSource(_live(extra: 8)),
      );
      await tester.enterText(find.byKey(const Key('search.field')), 'harbour');
      await tester.pumpAndSettle();
      // Five channels, then "Show all".
      expect(
        find.byType(ChannelRow),
        findsNWidgets(SearchScreen.previewChannels),
      );
      expect(find.byKey(const Key('search.movies.all')), findsNothing);

      await _tapKey(tester, 'search.live.all');
      expect(find.byKey(const Key('search.all')), findsOneWidget);
      expect(find.text('10 channels'), findsOneWidget);
      expect(find.text('Harbour Extra 7'), findsOneWidget);
      expect(find.text('Lantern Harbour'), findsNothing);

      await _tapKey(tester, 'search.back');
      expect(find.byKey(const Key('search.all')), findsNothing);
      expect(find.byKey(const Key('search.results')), findsOneWidget);

      await _tapKey(tester, 'search.live.all');
      await tester.tap(find.text('Harbour Extra 7'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.opened.single.title, 'Harbour Extra 7');
    });

    testWidgets('Enter moves to the first result and Enter plays it', (
      tester,
    ) async {
      await _pump(tester, const SearchScreen(), player: player);
      await tester.enterText(find.byKey(const Key('search.field')), 'harbour');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        _focusIn(tester, find.byKey(const ValueKey('search.live.2'))),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.opened.single.title, 'Harbour TV');
    });

    testWidgets('clicking a movie or series opens its details', (tester) async {
      await _pump(tester, const SearchScreen(), player: player);
      await tester.enterText(find.byKey(const Key('search.field')), 'harbour');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search.movie.1')));
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('search.series.10')));
      await tester.pumpAndSettle();
      expect(find.byType(SeriesDetailsScreen), findsOneWidget);
    });

    testWidgets('catalogues load on demand, with a loading state', (
      tester,
    ) async {
      final live = FakeLiveSource(_live())..gate = Completer<void>();
      await _pump(
        tester,
        const SearchScreen(),
        player: player,
        live: live,
        settle: false,
      );
      expect(find.byKey(const Key('search.loading')), findsOneWidget);
      expect(find.textContaining('Loading channels'), findsOneWidget);
      expect(live.loads, 1);

      await tester.enterText(find.byKey(const Key('search.field')), 'harbour');
      await tester.pump();
      await tester.pump();
      expect(find.text('Loading channels…'), findsOneWidget);
      expect(find.text('Harbour Lights (2010)'), findsOneWidget);

      live.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Loading channels…'), findsNothing);
      expect(find.text('Harbour TV'), findsOneWidget);
    });
  });

  group('at text scale 1.4', () {
    testWidgets('headers, toolbars, menus and search results lay out '
        'without overflow', (tester) async {
      const size = Size(1000, 700);
      final player = FakeExternalPlayer();
      addTearDown(player.dispose);
      await _pump(
        tester,
        const SeriesScreen(),
        size: size,
        textScale: 1.4,
        player: player,
      );
      await tester.tap(find.text('Shows'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('series.search')), 'harbour');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'series.genre');
      await _tapKey(tester, 'series.genre.Mystery');
      await _tapKey(tester, 'series.genre.done');
      await _tapKey(tester, 'series.year');
      await _tapKey(tester, 'series.year.2');
      await _tapKey(tester, 'series.sort');
      await _tapKey(tester, 'series.sort.title');
      await _tapKey(tester, 'series.year');
      await _tapKey(tester, 'series.year.custom');
      expect(find.byKey(const Key('year.from')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await _pump(
        tester,
        const LiveTvScreen(),
        size: size,
        textScale: 1.4,
        player: player,
      );
      await tester.tap(find.text('Sweden'));
      await tester.enterText(find.byKey(const Key('live.search')), 'harbour');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live.onlyIn')), findsOneWidget);

      await _pump(
        tester,
        const SearchScreen(),
        size: size,
        textScale: 1.4,
        player: player,
        live: FakeLiveSource(_live(extra: 8)),
      );
      await tester.enterText(find.byKey(const Key('search.field')), 'harbour');
      await tester.pumpAndSettle();
      await _tapKey(tester, 'search.live.all');
      expect(find.byKey(const Key('search.all')), findsOneWidget);
    });
  });
}
