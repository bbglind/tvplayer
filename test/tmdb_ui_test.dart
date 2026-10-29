import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/service_credentials.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/state/playlist_refresh.dart';
import 'package:tvplayer/state/tmdb.dart';
import 'package:tvplayer/ui/home/home_screen.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer/ui/vod/movie_details_screen.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer/ui/vod/person_screen.dart';
import 'package:tvplayer/ui/vod/poster.dart';
import 'package:tvplayer/ui/vod/series_details_screen.dart';
import 'package:tvplayer/ui/vod/series_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

// A made-up v3 API key, not a real one.
const _key = '0123456789abcdef0123456789abcdef';
final _at = DateTime.utc(2026, 3, 1);

const _cast = TmdbCast(
  personId: 501,
  name: 'Actor One',
  character: 'Hero',
  profilePath: '/p1.jpg',
);

/// Answers from fixed titles; counts requests.
class _FakeApi implements TmdbApi {
  final titles = <TmdbKey, TmdbTitle>{};
  final searches = <String, List<TmdbSearchResult>>{};
  final asked = <String>[];
  TmdbPerson? person_;
  TmdbSeason? season_;

  @override
  Future<TmdbTitle> title(TmdbKey key) async {
    asked.add('$key');
    return titles[key] ??
        (throw const TmdbException(TmdbFailure.notFound, 'fake'));
  }

  @override
  Future<TmdbSeason> season(int tvId, int number) async =>
      season_ ?? TmdbSeason(tvId: tvId, number: number, fetchedAt: _at);

  @override
  Future<TmdbPerson> person(int id) async =>
      person_ ?? (throw const TmdbException(TmdbFailure.notFound, 'fake'));

  @override
  Future<List<TmdbSearchResult>> search(
    TmdbKind kind,
    String query, {
    int? year,
  }) async {
    asked.add('search $query');
    return searches[query] ?? const [];
  }

  /// This week's trending titles by kind (all on page 1).
  final trending_ = <TmdbKind, List<TmdbTrending>>{};

  /// When set, trending requests fail with it.
  TmdbFailure? trendingFails;

  @override
  Future<List<TmdbTrending>> trending(TmdbKind kind, {int page = 1}) async {
    asked.add('trending ${kind.name} $page');
    if (trendingFails case final f?) throw TmdbException(f, 'fake');
    return page == 1 ? trending_[kind] ?? const [] : const [];
  }
}

const _movieKey = TmdbKey(TmdbKind.movie, 1001);

final _movies = VodCatalog.movies(
  categories: const [
    Category(id: 'm0', name: 'Films'),
    Category(id: 'm1', name: 'Hidden films'),
  ],
  items: const [
    Movie(streamId: 1, name: 'Example Movie', categoryId: 'm0', tmdbId: '1001'),
    Movie(streamId: 2, name: 'Second Movie', categoryId: 'm0', tmdbId: '1002'),
    Movie(streamId: 3, name: 'Hidden Movie', categoryId: 'm1', tmdbId: '1003'),
    Movie(streamId: 4, name: 'Unknown Film (2019)', categoryId: 'm0'),
  ],
  fetchedAt: _at,
);

final _series = VodCatalog.series(
  categories: const [Category(id: 's0', name: 'Shows')],
  items: const [Series(seriesId: 7, name: 'Example Series', tmdbId: '2001')],
  fetchedAt: _at,
);

final _seriesInfo = SeriesInfo(
  series: const Series(seriesId: 7, name: 'Example Series'),
  seasons: const [],
  episodes: const [
    Episode(id: '701', season: 1, episodeNumber: 1, title: 'Pilot'),
  ],
);

_FakeApi _api() => _FakeApi()
  ..titles[_movieKey] = TmdbTitle(
    key: _movieKey,
    fetchedAt: _at,
    title: 'Example Movie',
    overview: 'Overview from TMDB.',
    year: 2019,
    backdropPath: '/backdrop.jpg',
    posterPath: '/poster.jpg',
    genres: const [TmdbGenre(18, 'Drama')],
    cast: const [_cast],
    recommendations: const [
      TmdbKey(TmdbKind.movie, 1002),
      TmdbKey(TmdbKind.movie, 1003),
      TmdbKey(TmdbKind.movie, 9999),
      TmdbKey(TmdbKind.tv, 2001),
    ],
  )
  ..titles[const TmdbKey(TmdbKind.tv, 2001)] = TmdbTitle(
    key: const TmdbKey(TmdbKind.tv, 2001),
    fetchedAt: _at,
    overview: 'Series overview from TMDB.',
    backdropPath: '/tv.jpg',
  )
  ..season_ = TmdbSeason(
    tvId: 2001,
    number: 1,
    fetchedAt: _at,
    episodes: const [
      TmdbEpisode(season: 1, number: 1, overview: 'Episode from TMDB.'),
    ],
  )
  ..person_ = TmdbPerson(
    id: 501,
    name: 'Actor One',
    fetchedAt: _at,
    biography: 'Short biography.',
    credits: const [
      TmdbCredit(_movieKey, year: 2019),
      TmdbCredit(TmdbKey(TmdbKind.tv, 2001), year: 2015),
      TmdbCredit(TmdbKey(TmdbKind.movie, 8888), year: 2020),
    ],
  );

/// Pumps [child] with TMDB on (unless [enabled] is false), a saved key and
/// an in-process backend answering from [api].
Future<({FakeSettingsStorage settings, List<TmdbBackend> backends})> _pump(
  WidgetTester tester,
  Widget child, {
  _FakeApi? api,
  bool enabled = true,
  bool key = true,
  bool hideCategory = false,
  bool preferTmdbPosters = false,
  bool paused = false,
  Map<int, Movie> movieDetails = const {},
  VodCatalog<Movie>? movies,
  VodCatalog<Series>? series,
  Size size = const Size(1400, 900),
}) async {
  final movieCatalog = movies ?? _movies;
  final seriesCatalog = series ?? _series;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = FakeSettingsStorage(
    AppSettings(
      tmdbEnabled: enabled,
      tmdbPreferPosters: preferTmdbPosters,
      tmdbPaused: paused,
    ),
  );
  final backends = <TmdbBackend>[];
  final vod = FakeVodRepository()
    ..movies['test'] = movieCatalog
    ..series['test'] = seriesCatalog;
  final fake = api ?? _api();
  await tester.pumpWidget(
    testApp(
      overrides: [
        vodSourceProvider.overrideWithValue(
          FakeVodSource(
            movies: movieCatalog,
            series: seriesCatalog,
            seriesInfos: {7: _seriesInfo},
            movieDetails: movieDetails,
          ),
        ),
        providerKeyProvider.overrideWithValue('test'),
        tmdbBackendFactoryProvider.overrideWithValue((credential) async {
          final store = TmdbStore.inMemory();
          final sync = TmdbSync(store: store, api: fake, now: () => _at);
          backends.add(sync);
          return sync;
        }),
        tmdbConnectionTesterProvider.overrideWithValue(
          (c) async => c.value == _key ? null : TmdbFailure.unauthorized,
        ),
      ],
      settings: settings,
      vod: vod,
      serviceCredentials: MemoryServiceCredentials({
        if (key) MetadataService.tmdb: _key,
      }),
      favourites: hideCategory
          ? MemoryFavouritesStore(
              FavouritesData(
                hidden: {
                  HiddenCategory.hiddenKey(
                    ContentKind.movie,
                    'm1',
                  ): HiddenCategory(
                    kind: ContentKind.movie,
                    categoryId: 'm1',
                    hidden: true,
                    updatedAt: _at,
                  ),
                },
              ),
            )
          : null,
      now: _at,
      child: _Host(child),
    ),
  );
  await _settle(tester);
  return (settings: settings, backends: backends);
}

/// Keeps the background fetch alive, as the app shell does.
class _Host extends ConsumerWidget {
  const _Host(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(tmdbSyncProvider, (_, _) {});
    ref.listen(tmdbTrendingProvider, (_, _) {});
    return child;
  }
}

/// Lets the backend, its events and the throttled updates run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
  }
  await tester.pumpAndSettle();
}

const _movie = Movie(
  streamId: 1,
  name: 'Example Movie',
  categoryId: 'm0',
  tmdbId: '1001',
);

void main() {
  group('detail pages', () {
    testWidgets('TMDB fills gaps, shows the backdrop, cast and only catalogue '
        'recommendations', (tester) async {
      await _pump(
        tester,
        const MovieDetailsScreen(movie: _movie),
        hideCategory: true,
      );
      expect(find.byKey(const Key('details.backdrop')), findsOneWidget);
      expect(find.text('Overview from TMDB.'), findsOneWidget);
      expect(find.textContaining('Drama'), findsOneWidget);
      expect(find.text('Actor One'), findsOneWidget);
      expect(find.text('Hero'), findsOneWidget);
      // Recommendations: in the catalogue, not hidden, movies and series.
      final recommendations = find.byKey(const Key('details.recommendations'));
      await tester.scrollUntilVisible(
        recommendations,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: recommendations,
          matching: find.byKey(const ValueKey('tmdb.movie.2')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tmdb.movie.3')), findsNothing);
      expect(find.byKey(const ValueKey('tmdb.series.7')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("the provider's plot and genre win over TMDB's", (
      tester,
    ) async {
      await _pump(
        tester,
        const MovieDetailsScreen(movie: _movie),
        movieDetails: {
          1: const Movie(
            streamId: 1,
            name: 'Example Movie',
            plot: 'Plot from the provider.',
            genre: 'Comedy',
          ),
        },
      );
      expect(find.text('Plot from the provider.'), findsOneWidget);
      expect(find.text('Overview from TMDB.'), findsNothing);
      expect(find.textContaining('Comedy'), findsOneWidget);
      expect(find.textContaining('Drama'), findsNothing);
    });

    testWidgets('series: TMDB episode descriptions where the provider has '
        'none', (tester) async {
      await _pump(tester, SeriesDetailsScreen(series: _series.items.first));
      expect(find.byKey(const Key('details.backdrop')), findsOneWidget);
      expect(find.text('Series overview from TMDB.'), findsOneWidget);
      expect(find.text('Episode from TMDB.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone layout: the backdrop across the top, above the title', (
      tester,
    ) async {
      await _pump(
        tester,
        const MovieDetailsScreen(movie: _movie),
        size: const Size(412, 900),
      );
      final backdrop = find.byKey(const Key('details.backdrop'));
      final title = find.byKey(const Key('movie.title'));
      expect(tester.getTopLeft(backdrop).dx, 0);
      expect(tester.getSize(backdrop).width, 412);
      expect(
        tester.getBottomLeft(backdrop).dy,
        lessThanOrEqualTo(tester.getTopLeft(title).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cast member opens the person page with catalogue titles', (
      tester,
    ) async {
      await _pump(tester, const MovieDetailsScreen(movie: _movie));
      await tester.tap(find.byKey(const ValueKey('cast.501')));
      await _settle(tester);
      expect(find.byType(PersonScreen), findsOneWidget);
      expect(find.text('Short biography.'), findsOneWidget);
      expect(find.byKey(const Key('person.movies')), findsOneWidget);
      expect(find.byKey(const ValueKey('tmdb.movie.1')), findsOneWidget);
      expect(find.byKey(const Key('person.series')), findsOneWidget);
      expect(find.byKey(const Key('person.empty')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a person without catalogue titles says so', (tester) async {
      final api = _api()
        ..person_ = TmdbPerson(id: 501, name: 'Actor One', fetchedAt: _at);
      await _pump(
        tester,
        const PersonScreen(personId: 501, name: 'Actor One'),
        api: api,
      );
      expect(find.byKey(const Key('person.empty')), findsOneWidget);
    });

    testWidgets('Wrong TMDB match? Remove it: the title shows provider data '
        'only', (tester) async {
      await _pump(tester, const MovieDetailsScreen(movie: _movie));
      expect(find.text('Overview from TMDB.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('details.menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details.removeMatch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('details.removeMatch.confirm')));
      await _settle(tester);
      expect(find.text('Overview from TMDB.'), findsNothing);
      expect(find.byKey(const Key('details.backdrop')), findsNothing);
      expect(find.byKey(const Key('details.cast')), findsNothing);
      expect(find.byKey(const Key('details.menu')), findsNothing);
    });

    testWidgets('a title without an id is matched by searching', (
      tester,
    ) async {
      final api = _api();
      api.searches['Unknown Film'] = const [
        TmdbSearchResult(_movieKey, title: 'Unknown Film', year: 2019),
      ];
      await _pump(
        tester,
        const MovieDetailsScreen(
          movie: Movie(streamId: 4, name: 'Unknown Film (2019)'),
        ),
        api: api,
      );
      expect(api.asked, contains('search Unknown Film'));
      expect(find.text('Overview from TMDB.'), findsOneWidget);
      expect(find.byKey(const Key('details.menu')), findsOneWidget);
    });

    testWidgets('with TMDB off nothing is asked and the page is as before', (
      tester,
    ) async {
      final api = _api();
      final pumped = await _pump(
        tester,
        const MovieDetailsScreen(movie: _movie),
        api: api,
        enabled: false,
      );
      expect(pumped.backends, isEmpty);
      expect(api.asked, isEmpty);
      expect(find.byKey(const Key('details.backdrop')), findsNothing);
      expect(find.byKey(const Key('details.cast')), findsNothing);
      expect(find.byKey(const Key('details.menu')), findsNothing);
      expect(find.byKey(const Key('details.picture')), findsNothing);
    });
  });

  group('posters', () {
    const withPoster = Movie(
      streamId: 1,
      name: 'Example Movie',
      tmdbId: '1001',
      posterUrl: 'http://192.0.2.1/poster.jpg',
    );
    Future<PosterCard> card(WidgetTester tester, {required bool prefer}) async {
      await _pump(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 360,
              child: Builder(builder: (c) => moviePoster(c, withPoster)),
            ),
          ),
        ),
        preferTmdbPosters: prefer,
      );
      // Fetched in the background, then the image index updates.
      return tester.widget<PosterCard>(find.byType(PosterCard));
    }

    testWidgets('the provider poster first, TMDB as fallback', (tester) async {
      final c = await card(tester, prefer: false);
      expect(c.imageUrl, 'http://192.0.2.1/poster.jpg');
      expect(c.imageFallbackUrl, '${tmdbImageRefPrefix}w342/poster.jpg');
    });

    testWidgets('Prefer TMDB posters puts TMDB first', (tester) async {
      final c = await card(tester, prefer: true);
      expect(c.imageUrl, '${tmdbImageRefPrefix}w342/poster.jpg');
      expect(c.imageFallbackUrl, 'http://192.0.2.1/poster.jpg');
    });
  });

  group('image caches', () {
    // A provider poster hosted on TMDB's image server.
    const providerOnTmdb = '${tmdbImageBase}w600/provider.jpg';
    final fromTmdb = tmdbImageRef('/tmdb.jpg', TmdbImageSize.w342);

    Future<({FakePosterLoader posters, FakeImageCache tmdb})> load(
      WidgetTester tester, {
      required bool enabled,
    }) async {
      await tester.pumpWidget(
        testApp(
          overrides: const [],
          settings: FakeSettingsStorage(AppSettings(tmdbEnabled: enabled)),
          child: Scaffold(
            body: Column(
              children: [
                for (final url in [providerOnTmdb, fromTmdb])
                  SizedBox(width: 100, height: 150, child: Poster(url: url)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      return (
        posters: container.read(posterLoaderProvider) as FakePosterLoader,
        tmdb: container.read(tmdbImageLoaderProvider) as FakeImageCache,
      );
    }

    testWidgets('provider images use the poster cache, whatever the host', (
      tester,
    ) async {
      final caches = await load(tester, enabled: true);
      expect(caches.posters.requests, [providerOnTmdb]);
      expect(caches.tmdb.requests, ['${tmdbImageBase}w342/tmdb.jpg']);
    });

    testWidgets('nothing is loaded from TMDB while it is off', (tester) async {
      final caches = await load(tester, enabled: false);
      expect(caches.posters.requests, [providerOnTmdb]);
      expect(caches.tmdb.requests, isEmpty);
    });
  });

  group('Settings › Services', () {
    Future<void> showServices(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.tmdb')),
        300,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('enter a key, test the connection, see the fetch', (
      tester,
    ) async {
      await _pump(tester, const SettingsScreen(), key: false);
      await showServices(tester);
      expect(find.text('Not set'), findsOneWidget);
      expect(find.byKey(const Key('settings.tmdbProgress')), findsNothing);

      await tester.tap(find.byKey(const Key('settings.tmdbKey.enter')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings.tmdbKey.field')),
        'not a key',
      );
      await tester.tap(find.byKey(const Key('settings.tmdbKey.save')));
      await tester.pumpAndSettle();
      expect(find.textContaining("doesn't look like"), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('settings.tmdbKey.field')),
        _key,
      );
      await tester.tap(find.byKey(const Key('settings.tmdbKey.save')));
      await _settle(tester);
      expect(find.text('Saved in the system keyring.'), findsOneWidget);
      expect(find.text(_key), findsNothing);

      await tester.tap(find.byKey(const Key('settings.tmdbTest')));
      await tester.pumpAndSettle();
      expect(find.text('Connected to TMDB.'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.tmdbProgress')),
        200,
      );
      expect(find.text('TMDB info: 5 of 5 titles'), findsOneWidget);
      expect(find.text('Up to date.'), findsOneWidget);
    });

    testWidgets('Pause is kept in the settings', (tester) async {
      final pumped = await _pump(tester, const SettingsScreen());
      await showServices(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.tmdbPause')),
        200,
      );
      await tester.tap(find.byKey(const Key('settings.tmdbPause')));
      await _settle(tester);
      expect(pumped.settings.saved.tmdbPaused, isTrue);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('removed matches can be allowed again', (tester) async {
      final pumped = await _pump(tester, const SettingsScreen());
      await pumped.backends.single.removeLink(_movieKey);
      await pumped.backends.single.removeMatch(TmdbKind.movie, 'x|2019');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      await container
          .read(tmdbMatchesProvider.notifier)
          .remove(TmdbKind.movie, const TmdbLink(_movieKey));
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.tmdbRemoved')),
        200,
      );
      expect(find.text('Removed matches: 2'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('settings.tmdbRemoved.allow')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.tmdbRemoved.allow')));
      await _settle(tester);
      expect(find.byKey(const Key('settings.tmdbRemoved')), findsNothing);
      expect(await pumped.backends.single.removedCount(), 0);
    });

    testWidgets('About shows the TMDB notice and logo', (tester) async {
      await _pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.about.tmdb')),
        300,
      );
      expect(
        find.text(
          'This product uses the TMDB API but is not endorsed or certified '
          'by TMDB.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings.about.tmdbLogo')), findsOneWidget);
    });

    for (final scale in [1.4, 2.0]) {
      testWidgets('fits on a phone at text scale $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(tester, const SettingsScreen(), size: const Size(412, 900));
        await tester.scrollUntilVisible(
          find.byKey(const Key('settings.about.tmdb')),
          300,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('genres', () {
    testWidgets('Movies: Genre from TMDB, only genres of visible movies; '
        'movies without TMDB genres are left out', (tester) async {
      final api = _api()
        ..titles[const TmdbKey(TmdbKind.movie, 1003)] = TmdbTitle(
          key: const TmdbKey(TmdbKind.movie, 1003),
          fetchedAt: _at,
          genres: const [TmdbGenre(27, 'Horror')],
        );
      await _pump(
        tester,
        const Scaffold(body: MoviesScreen()),
        api: api,
        hideCategory: true,
      );
      await tester.tap(find.byKey(const Key('movies.genre')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('movies.genre.Drama')), findsWidgets);
      expect(
        find.byKey(const Key('movies.genre.Horror')),
        findsNothing,
        reason: 'only in a hidden category',
      );
      await tester.tap(find.byKey(const Key('movies.genre.Drama')).first);
      await tester.tap(find.byKey(const Key('movies.genre.done')));
      await tester.pumpAndSettle();
      expect(find.text('1 movie'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget, reason: 'the chip label');
    });

    testWidgets('Series: TMDB genres first, else the provider genre with '
        'TMDB names', (tester) async {
      final api = _api()
        ..titles[const TmdbKey(TmdbKind.tv, 2001)] = TmdbTitle(
          key: const TmdbKey(TmdbKind.tv, 2001),
          fetchedAt: _at,
          genres: const [TmdbGenre(10765, 'Sci-Fi & Fantasy')],
        );
      await _pump(
        tester,
        const Scaffold(body: SeriesScreen()),
        api: api,
        series: VodCatalog.series(
          categories: const [Category(id: 's0', name: 'Shows')],
          items: const [
            Series(
              seriesId: 7,
              name: 'Example Series',
              categoryId: 's0',
              tmdbId: '2001',
              genre: 'Drama',
            ),
            Series(
              seriesId: 8,
              name: 'Other Series',
              categoryId: 's0',
              genre: 'Sci-Fi / Crime',
            ),
          ],
          fetchedAt: _at,
        ),
      );
      await tester.tap(find.byKey(const Key('series.genre')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('series.genre.Sci-Fi & Fantasy')),
        findsWidgets,
      );
      expect(find.byKey(const Key('series.genre.Crime')), findsWidgets);
      expect(
        find.byKey(const Key('series.genre.Drama')),
        findsNothing,
        reason: "TMDB's genres win over the provider's",
      );
      await tester.tap(
        find.byKey(const Key('series.genre.Sci-Fi & Fantasy')).first,
      );
      await tester.tap(find.byKey(const Key('series.genre.done')));
      await tester.pumpAndSettle();
      expect(find.text('2 series'), findsOneWidget);
    });
  });

  group('Featured for you', () {
    final movies = VodCatalog.movies(
      categories: const [Category(id: 'm0', name: 'Films')],
      items: [
        for (final (id, name, tmdb, days) in [
          (1, 'Example Movie', '1001', 1),
          (2, 'Second Movie', '1002', 2),
          (5, 'Fresh Movie', null, 3),
        ])
          Movie(
            streamId: id,
            name: name,
            categoryId: 'm0',
            tmdbId: tmdb,
            added: _at.subtract(Duration(days: days)),
            rating: 8,
          ),
      ],
      fetchedAt: _at,
    );
    final series = VodCatalog.series(
      categories: const [Category(id: 's0', name: 'Shows')],
      items: [
        Series(
          seriesId: 7,
          name: 'Example Series',
          categoryId: 's0',
          tmdbId: '2001',
          lastModified: _at.subtract(const Duration(days: 1)),
          rating: 8,
        ),
      ],
      fetchedAt: _at,
    );
    _FakeApi trendingApi() => _api()
      ..trending_[TmdbKind.movie] = const [
        TmdbTrending(TmdbKey(TmdbKind.movie, 1002), 1),
        TmdbTrending(TmdbKey(TmdbKind.movie, 9999), 2),
      ]
      ..trending_[TmdbKind.tv] = const [
        TmdbTrending(TmdbKey(TmdbKind.tv, 2001), 1),
      ];

    String title(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('home.featured.title')),
            matching: find.byType(Text),
          ),
        )
        .data!;

    Future<void> showItem(WidgetTester tester, int i) async {
      await tester.tap(find.byKey(Key('home.featured.dot.$i')));
      await tester.pumpAndSettle();
    }

    /// Runs [body] with the `TMDB trending:` log lines collected.
    Future<void> withLog(Future<void> Function(List<String> log) body) async {
      final log = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message case final m? when m.startsWith('TMDB trending:')) {
          log.add(m);
        }
      };
      try {
        await body(log);
      } finally {
        debugPrint = original;
      }
    }

    testWidgets('new and trending take turns, labelled NEW and TRENDING', (
      tester,
    ) async {
      await withLog((log) async {
        await _pump(
          tester,
          const Scaffold(body: HomeScreen()),
          api: trendingApi(),
          movies: movies,
          series: series,
        );
        expect(log, ['TMDB trending: refreshed (3 titles, 2 matched)']);
        // It moved on while the backend settled.
        await showItem(tester, 0);
        expect(title(tester), 'Example Movie');
        expect(find.byKey(const Key('home.featured.label.fresh')), findsOne);
        expect(find.text('NEW'), findsOneWidget);
        await showItem(tester, 1);
        expect(title(tester), 'Second Movie');
        expect(find.text('TRENDING'), findsOneWidget);
        await showItem(tester, 2);
        expect(title(tester), 'Fresh Movie');
        await showItem(tester, 3);
        expect(title(tester), 'Example Series');
        expect(find.byKey(const Key('home.featured.label.trending')), findsOne);
        expect(find.byKey(const Key('home.featured.dot.4')), findsNothing);
      });
    });

    testWidgets('a failed fetch leaves Featured as before, unlabelled', (
      tester,
    ) async {
      await withLog((log) async {
        await _pump(
          tester,
          const Scaffold(body: HomeScreen()),
          api: trendingApi()..trendingFails = TmdbFailure.network,
          movies: movies,
          series: series,
        );
        expect(log, ['TMDB trending: failed (TmdbException(network))']);
        await showItem(tester, 0);
        expect(title(tester), 'Example Movie');
        expect(find.text('NEW'), findsNothing);
        expect(find.text('TRENDING'), findsNothing);
        await showItem(tester, 1);
        expect(title(tester), 'Example Series');
        expect(find.byKey(const Key('home.featured.dot.3')), findsOneWidget);
      });
    });

    testWidgets('waits while paused and while playing', (tester) async {
      await withLog((log) async {
        final api = trendingApi();
        await _pump(
          tester,
          const Scaffold(body: HomeScreen()),
          api: api,
          movies: movies,
          series: series,
          paused: true,
        );
        expect(log, ['TMDB trending: skipped (paused)']);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeScreen)),
        );
        container.read(playbackActiveProvider.notifier).begin();
        await container.read(tmdbSyncProvider.notifier).setPaused(false);
        await _settle(tester);
        expect(log.last, 'TMDB trending: skipped (playing)');
        expect(api.asked.where((a) => a.startsWith('trending')), isEmpty);
        container.read(playbackActiveProvider.notifier).end();
        await _settle(tester);
        expect(log.last, 'TMDB trending: refreshed (3 titles, 2 matched)');
        await showItem(tester, 0);
        expect(find.text('NEW'), findsOneWidget);
      });
    });

    for (final (scale, size) in [
      (1.4, const Size(412, 900)),
      (1.4, const Size(1000, 700)),
      (2.0, const Size(412, 900)),
    ]) {
      testWidgets('the labelled banner fits at text scale $scale in a '
          '${size.width.round()} wide window', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await withLog((_) async {
          await _pump(
            tester,
            const Scaffold(body: HomeScreen()),
            api: trendingApi(),
            movies: movies,
            series: series,
            size: size,
          );
          for (var i = 0; i < 4; i++) {
            await showItem(tester, i);
            expect(find.byKey(const Key('home.featured.title')), findsOne);
          }
          expect(find.text('TRENDING'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('with TMDB off nothing is fetched and Featured is as before', (
      tester,
    ) async {
      await withLog((log) async {
        final api = trendingApi();
        await _pump(
          tester,
          const Scaffold(body: HomeScreen()),
          api: api,
          movies: movies,
          series: series,
          enabled: false,
        );
        expect(log, ['TMDB trending: skipped (off)']);
        expect(api.asked, isEmpty);
        expect(find.text('NEW'), findsNothing);
      });
    });
  });
}
