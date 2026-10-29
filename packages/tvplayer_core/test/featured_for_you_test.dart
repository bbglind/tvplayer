import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _now = DateTime.utc(2026, 6, 1, 12);

DateTime _daysAgo(num days) =>
    _now.subtract(Duration(minutes: (days * 24 * 60).round()));

TmdbKey _m(int id) => TmdbKey(TmdbKind.movie, id);

TmdbKey _tv(int id) => TmdbKey(TmdbKind.tv, id);

Movie _movie(int id, {String category = 'm', int days = 1}) => Movie(
  streamId: id,
  name: 'Movie $id',
  tmdbId: '$id',
  categoryId: category,
  added: _daysAgo(days),
  rating: 8,
);

Series _series(int id, {String category = 's'}) => Series(
  seriesId: id,
  name: 'Series $id',
  tmdbId: '$id',
  categoryId: category,
  lastModified: _daysAgo(1),
  rating: 8,
);

VodCatalog<Movie> _movies(List<Movie> items) =>
    VodCatalog.movies(categories: const [], items: items, fetchedAt: _now);

VodCatalog<Series> _seriesCatalog(List<Series> items) =>
    VodCatalog.series(categories: const [], items: items, fetchedAt: _now);

TmdbLinks _links(List<Movie> movies, List<Series> series) => TmdbLinks.build(
  movies: tmdbMovieItems(movies),
  series: tmdbSeriesItems(series),
  tags: ProviderTags.empty,
  matches: const {},
  removed: const {},
);

WatchProgress _played(num daysAgo, {int minutes = 30, int? seriesId}) =>
    WatchProgress(
      position: Duration(minutes: minutes),
      duration: const Duration(minutes: 100),
      updatedAt: _daysAgo(daysAgo),
      seriesId: seriesId,
    );

List<String> _names(List<VodPick> picks) => [for (final p in picks) p.name];

void main() {
  group('trendingDecision', () {
    TrendingDecision decide({
      bool enabled = true,
      bool paused = false,
      bool playing = false,
      DateTime? fetchedAt,
    }) => trendingDecision(
      enabled: enabled,
      paused: paused,
      playing: playing,
      fetchedAt: fetchedAt,
      now: _now,
    );

    test('off, paused and playing win in that order', () {
      expect(
        decide(enabled: false, paused: true, playing: true),
        TrendingDecision.off,
      );
      expect(decide(paused: true, playing: true), TrendingDecision.paused);
      expect(decide(playing: true), TrendingDecision.playing);
    });

    test('fresh for 24 hours, then refresh', () {
      expect(decide(), TrendingDecision.refresh, reason: 'never fetched');
      expect(decide(fetchedAt: _daysAgo(0.9)), TrendingDecision.fresh);
      expect(decide(fetchedAt: _daysAgo(1)), TrendingDecision.refresh);
    });
  });

  group('usableTrending', () {
    final titles = [TmdbTrending(_m(1), 1)];

    test('the stored list is used for at most 7 days', () {
      expect(
        usableTrending(
          TmdbTrendingList(
            titles,
            _now.subtract(const Duration(days: 6, hours: 23)),
          ),
          _now,
        ),
        titles,
      );
      expect(
        usableTrending(
          TmdbTrendingList(titles, _now.subtract(const Duration(days: 7))),
          _now,
        ),
        titles,
      );
      expect(
        usableTrending(
          TmdbTrendingList(
            titles,
            _now.subtract(const Duration(days: 7, minutes: 1)),
          ),
          _now,
        ),
        isEmpty,
      );
    });

    test('nothing when never fetched or empty', () {
      expect(usableTrending(TmdbTrendingList(titles, null), _now), isEmpty);
      expect(usableTrending(TmdbTrendingList.empty, _now), isEmpty);
    });

    test('a list older than 7 days gives Featured as before', () {
      final movies = _movies([_movie(1), _movie(2), _movie(3)]);
      final series = _seriesCatalog([_series(1), _series(2), _series(3)]);
      final trending = trendingPicks(
        trending: usableTrending(
          TmdbTrendingList([TmdbTrending(_m(1), 1)], _daysAgo(8)),
          _now,
        ),
        movies: movies,
        series: series,
        links: _links(movies.items, series.items),
        movieGroups: VariantGroups.empty,
        seriesGroups: VariantGroups.empty,
        favourites: FavouritesData.empty,
        watch: WatchData.empty,
      );
      final fresh = featuredPicks(
        movies: movies,
        series: series,
        favourites: FavouritesData.empty,
        now: _now,
      );
      expect(mixFeatured(fresh, trending), [
        for (final p in fresh) FeaturedPick(p, FeaturedSource.fresh),
      ]);
      expect(fresh, hasLength(5));
    });
  });

  group('genreAffinity', () {
    final genres = {
      1: ['Science Fiction'],
      2: ['Drama'],
      3: ['Comedy'],
    };
    Map<String, double> affinity(WatchData watch) => genreAffinity(
      watch,
      movieGenres: (id) => genres[id] ?? const [],
      seriesGenres: (id) => id == 9 ? const ['Sci-Fi & Fantasy'] : const [],
      now: _now,
    );

    test('shares of what was watched in the last 90 days', () {
      final a = affinity(
        WatchData(
          items: {
            movieKey(1): _played(2),
            movieKey(2): _played(40),
            movieKey(3): _played(100),
          },
        ),
      );
      // Movie 1 counts 1, movie 2 half (older than 30 days), movie 3 not.
      expect(a[genreFamily('Science Fiction')], closeTo(1 / 1.5, 1e-9));
      expect(a[genreFamily('Drama')], closeTo(0.5 / 1.5, 1e-9));
      expect(a.containsKey(genreFamily('Comedy')), isFalse);
    });

    test('short plays do not count; watched to the end does', () {
      expect(
        affinity(WatchData(items: {movieKey(1): _played(1, minutes: 4)})),
        isEmpty,
      );
      expect(
        affinity(
          WatchData(
            items: {
              movieKey(1): WatchProgress(
                position: Duration.zero,
                watched: true,
                updatedAt: _daysAgo(1),
              ),
            },
          ),
        ),
        {genreFamily('Science Fiction'): 1.0},
      );
    });

    test('series episodes add up, and feed the movie genre family', () {
      final a = affinity(
        WatchData(
          items: {
            movieKey(2): _played(1),
            for (var e = 1; e <= 20; e++)
              episodeKey('e$e'): _played(1, seriesId: 9),
          },
        ),
      );
      // The series counts at most 3, the movie 1.
      expect(a[genreFamily('Science Fiction')], closeTo(3 / 4, 1e-9));
      expect(a[genreFamily('Drama')], closeTo(1 / 4, 1e-9));
    });
  });

  group('trendingPicks', () {
    final movies = [
      _movie(1),
      _movie(2),
      _movie(3, category: 'hidden'),
      _movie(4),
      _movie(5),
      _movie(6),
    ];
    final series = [_series(10), _series(11), _series(12)];
    final trending = [
      TmdbTrending(_m(1), 1, genres: const ['Comedy']),
      TmdbTrending(_m(2), 2, genres: const ['Science Fiction']),
      TmdbTrending(_m(3), 3, genres: const ['Drama']),
      TmdbTrending(_m(4), 4, genres: const ['Drama']),
      TmdbTrending(_m(5), 5, genres: const ['Drama']),
      TmdbTrending(_m(6), 6, genres: const ['Drama']),
      TmdbTrending(_m(99), 7, genres: const ['Drama']),
      TmdbTrending(_tv(10), 1, genres: const ['Sci-Fi & Fantasy']),
      TmdbTrending(_tv(11), 2, genres: const ['Crime']),
      TmdbTrending(_tv(12), 3, genres: const ['Crime']),
    ];

    List<VodPick> picks({
      FavouritesData? favourites,
      WatchData watch = WatchData.empty,
      Map<String, double> affinity = const {},
    }) => trendingPicks(
      trending: trending,
      movies: _movies(movies),
      series: _seriesCatalog(series),
      links: _links(movies, series),
      movieGroups: VariantGroups.empty,
      seriesGroups: VariantGroups.empty,
      favourites:
          favourites ??
          setCategoriesHidden(
            FavouritesData.empty,
            ContentKind.movie,
            ['hidden'],
            hidden: true,
            now: _now,
          ),
      watch: watch,
      affinity: affinity,
    );

    test('without history: TMDB order, only titles in the catalogue', () {
      // Ranks count relative to each list: series 3 of 3 comes after
      // movie 5 of 7.
      expect(_names(picks()), [
        'Movie 1',
        'Series 10',
        'Movie 2',
        'Series 11',
        'Movie 4',
        'Movie 5',
        'Series 12',
        'Movie 6',
      ]);
    });

    test('genres watched often come first', () {
      final names = _names(picks(affinity: {genreFamily('Drama'): 0.8}));
      expect(names.take(3), ['Movie 4', 'Movie 5', 'Movie 6']);
      final scifi = _names(
        picks(affinity: {genreFamily('Science Fiction'): 1}),
      );
      expect(scifi.take(2), ['Series 10', 'Movie 2']);
    });

    test('leaves out favourites, watched, in progress and finished', () {
      final (withCategory, category) = createCategory(
        FavouritesData.empty,
        kind: ContentKind.movie,
        name: 'Mine',
        icon: 'star',
        now: _now,
      );
      final favourites = setMembership(
        withCategory,
        category!.id,
        movieItemRef(_movie(1)),
        name: 'Movie 1',
        member: true,
        now: _now,
      );
      final watch = WatchData(
        items: {
          movieKey(2): WatchProgress(
            position: Duration.zero,
            watched: true,
            updatedAt: _daysAgo(1),
          ),
          movieKey(4): _played(1),
        },
        series: {
          10: SeriesProgress(
            updatedAt: _daysAgo(1),
            watchedEpisodes: 2,
            totalEpisodes: 8,
            nextEpisodeId: 'e3',
          ),
          11: SeriesProgress(
            updatedAt: _daysAgo(1),
            watchedEpisodes: 8,
            totalEpisodes: 8,
          ),
        },
      );
      expect(_names(picks(favourites: favourites, watch: watch)), [
        'Movie 3',
        'Movie 5',
        'Series 12',
        'Movie 6',
      ], reason: 'Movie 3 shows: its category is not hidden here');
    });

    test('one per variant group', () {
      final variants = [
        _movie(1),
        const Movie(
          streamId: 21,
          name: 'Movie 1',
          tmdbId: '1',
          categoryId: 'm',
        ),
      ];
      final result = trendingPicks(
        trending: [TmdbTrending(_m(1), 1)],
        movies: _movies(variants),
        series: null,
        links: _links(variants, const []),
        movieGroups: VariantGroups.movies(variants, ProviderTags.empty),
        seriesGroups: VariantGroups.empty,
        favourites: FavouritesData.empty,
        watch: WatchData.empty,
      );
      expect(result, hasLength(1));
    });
  });

  group('mixFeatured', () {
    List<VodPick> movies(List<int> ids) => [
      for (final i in ids) MoviePick(_movie(i)),
    ];

    String text(List<FeaturedPick> mix) => mix
        .map(
          (p) =>
              '${p.source == FeaturedSource.fresh ? 'N' : 'T'}${(p.pick as MoviePick).movie.streamId}',
        )
        .join(' ');

    test('new and trending take turns, new first, 4 + 4', () {
      expect(
        text(
          mixFeatured(movies([1, 2, 3, 4, 5, 6]), movies([11, 12, 13, 14, 15])),
        ),
        'N1 T11 N2 T12 N3 T13 N4 T14',
      );
    });

    test('the other side fills up when one runs short', () {
      expect(
        text(mixFeatured(movies([1, 2, 3, 4, 5, 6, 7]), movies([11, 12]))),
        'N1 T11 N2 T12 N3 N4 N5 N6',
      );
      expect(
        text(
          mixFeatured(movies([1]), movies([11, 12, 13, 14, 15, 16, 17, 18])),
        ),
        'N1 T11 T12 T13 T14 T15 T16 T17',
      );
    });

    test('an item in both shows once, as trending', () {
      expect(text(mixFeatured(movies([1, 2, 3]), movies([2]))), 'N1 T2 N3');
    });

    test('without trending, the first five new items', () {
      expect(
        text(mixFeatured(movies([1, 2, 3, 4, 5, 6]), const [])),
        'N1 N2 N3 N4 N5',
      );
    });
  });
}
