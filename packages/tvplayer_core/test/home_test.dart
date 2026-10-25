import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _now = DateTime.utc(2026, 6, 1);

DateTime _daysAgo(int days) => _now.subtract(Duration(days: days));

Movie _movie(int id, {int days = 1, double? rating = 8, String? category}) =>
    Movie(
      streamId: id,
      name: 'Movie $id',
      added: _daysAgo(days),
      rating: rating,
      categoryId: category ?? 'm',
    );

Series _series(int id, {int days = 1, double? rating = 8, String? category}) =>
    Series(
      seriesId: id,
      name: 'Series $id',
      lastModified: _daysAgo(days),
      rating: rating,
      categoryId: category ?? 's',
    );

VodCatalog<Movie> _movies(List<Movie> items) =>
    VodCatalog.movies(categories: const [], items: items, fetchedAt: _now);

VodCatalog<Series> _seriesCatalog(List<Series> items) =>
    VodCatalog.series(categories: const [], items: items, fetchedAt: _now);

List<String> _names(List<VodPick> picks) => [for (final p in picks) p.name];

void main() {
  group('featured', () {
    test('rated, recent movies and series take turns, newest first', () {
      final picks = featuredPicks(
        movies: _movies([
          _movie(1, days: 5),
          _movie(2, days: 2),
          _movie(3, days: 3, rating: 6.9),
          _movie(4, days: 1, rating: null),
          _movie(5, days: 10),
        ]),
        series: _seriesCatalog([_series(1, days: 4), _series(2, days: 1)]),
        favourites: FavouritesData.empty,
        now: _now,
      );
      expect(_names(picks), [
        'Movie 2',
        'Series 2',
        'Movie 1',
        'Series 1',
        'Movie 5',
      ]);
    });

    test('widens the window when the last 30 days have too few', () {
      final picks = featuredPicks(
        movies: _movies([_movie(1, days: 10), _movie(2, days: 200)]),
        series: _seriesCatalog([_series(1, days: 60), _series(2, days: 900)]),
        favourites: FavouritesData.empty,
        now: _now,
        count: 3,
      );
      expect(_names(picks), ['Movie 1', 'Series 1', 'Movie 2']);
    });

    test('a short window that has enough is not widened', () {
      final picks = featuredPicks(
        movies: _movies([for (var i = 1; i <= 6; i++) _movie(i, days: i)]),
        series: _seriesCatalog([_series(1, days: 100)]),
        favourites: FavouritesData.empty,
        now: _now,
      );
      expect(picks.whereType<SeriesPick>(), isEmpty);
      expect(picks, hasLength(5));
    });

    test('skips favourites and hidden categories', () {
      var favourites = FavouritesData.empty;
      final (withCategory, category) = createCategory(
        favourites,
        kind: ContentKind.movie,
        name: 'Mine',
        icon: 'star',
        now: _now,
      );
      favourites = setMembership(
        withCategory,
        category!.id,
        movieItemRef(_movie(1)),
        name: 'Movie 1',
        member: true,
        now: _now,
      );
      favourites = setCategoriesHidden(
        favourites,
        ContentKind.series,
        ['hidden'],
        hidden: true,
        now: _now,
      );
      final picks = featuredPicks(
        movies: _movies([_movie(1), _movie(2)]),
        series: _seriesCatalog([_series(1, category: 'hidden'), _series(2)]),
        favourites: favourites,
        now: _now,
      );
      expect(_names(picks), ['Movie 2', 'Series 2']);
    });

    test('works while a catalogue is missing', () {
      expect(
        featuredPicks(
          movies: null,
          series: null,
          favourites: FavouritesData.empty,
          now: _now,
        ),
        isEmpty,
      );
    });
  });

  test('recently added: newest first, without hidden categories', () {
    final catalog = _movies([
      for (var i = 1; i <= 30; i++)
        _movie(i, days: i, category: i == 2 ? 'hidden' : 'm'),
    ]);
    final recent = recentlyAdded(catalog, hidden: {'hidden'});
    expect(recent, hasLength(20));
    expect(recent.take(3).map((m) => m.streamId), [1, 3, 4]);
  });

  test('continue watching mixes movies and series by time', () {
    final data = WatchData.empty
        .withItems({
          movieKey(1): WatchProgress(
            position: const Duration(minutes: 20),
            duration: const Duration(minutes: 90),
            updatedAt: _daysAgo(3),
          ),
          movieKey(2): WatchProgress(
            position: const Duration(minutes: 30),
            duration: const Duration(minutes: 90),
            updatedAt: _daysAgo(1),
          ),
        })
        .withSeries(
          7,
          SeriesProgress(
            nextEpisodeId: '701',
            watchedEpisodes: 1,
            totalEpisodes: 5,
            updatedAt: _daysAgo(2),
          ),
        );
    expect(
      [
        for (final e in continueAll(data))
          switch (e) {
            ContinueMovie(:final streamId) => 'movie $streamId',
            ContinueSeries(:final seriesId) => 'series $seriesId',
          },
      ],
      ['movie 2', 'series 7', 'movie 1'],
    );
  });
}
