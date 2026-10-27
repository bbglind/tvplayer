import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _t0 = DateTime.utc(2026, 1, 1);

DateTime _day(int d) => _t0.add(Duration(days: d));

final _movies = VodCatalog.movies(
  categories: const [
    Category(id: 'a', name: 'A'),
    Category(id: 'b', name: 'B'),
  ],
  items: [
    Movie(
      streamId: 1,
      name: '4K-TOP - Zebra Road (2026)',
      categoryId: 'a',
      added: _day(3),
      rating: 6,
    ),
    Movie(
      streamId: 2,
      name: 'EN - apple orchard (2024)',
      categoryId: 'b',
      added: _day(9),
      rating: 0,
    ),
    Movie(
      streamId: 3,
      name: 'Ébène Nights (2019) (FR)',
      categoryId: 'a',
      added: _day(1),
      rating: 8.5,
    ),
    const Movie(streamId: 4, name: 'Mango Season', categoryId: 'b'),
    Movie(
      streamId: 5,
      name: 'SC - Bramble (2025)',
      categoryId: 'a',
      added: _day(9),
      rating: 8.5,
    ),
  ],
  fetchedAt: _t0,
);

final _series = VodCatalog.series(
  categories: const [Category(id: 's', name: 'S')],
  items: [
    Series(
      seriesId: 10,
      name: 'Harbour Lights (2010)',
      categoryId: 's',
      genre: 'Crime / Drama / Mystery',
      releaseDate: '2021-03-04',
      lastModified: _day(2),
    ),
    Series(
      seriesId: 11,
      name: 'Sky Pirates',
      categoryId: 's',
      genre: 'Action & Adventure / Mystery',
      lastModified: _day(5),
    ),
    const Series(
      seriesId: 12,
      name: 'Kitchen Wars (2025)',
      categoryId: 's',
      genre: 'Reality',
    ),
    const Series(seriesId: 13, name: 'No Info', categoryId: 's'),
  ],
  fetchedAt: _t0,
);

List<int> _ids(List<Movie> movies) => [for (final m in movies) m.streamId];

List<int> _sids(List<Series> series) => [for (final s in series) s.seriesId];

void main() {
  group('sort', () {
    test('recently added, newest first, undated last, ties keep order', () {
      expect(_ids(_movies.query(sort: VodSort.recent)), [2, 5, 1, 3, 4]);
    });

    test('A–Z by title without the tag, diacritics folded', () {
      expect(_ids(_movies.query(sort: VodSort.title)), [2, 5, 3, 4, 1]);
    });

    test('top rated, unrated (null or 0) last', () {
      expect(_ids(_movies.query(sort: VodSort.rating)), [3, 5, 1, 2, 4]);
    });

    test('series sort by last update', () {
      expect(_sids(_series.query(sort: VodSort.recent)), [11, 10, 12, 13]);
    });

    test('no sort keeps the scope order', () {
      expect(_ids(_movies.query(scope: const VodScope.ids([5, 1, 3]))), [
        5,
        1,
        3,
      ]);
      expect(
        _ids(
          _movies.query(
            scope: const VodScope.ids([5, 1, 3]),
            sort: VodSort.title,
          ),
        ),
        [5, 3, 1],
      );
    });

    test('my order keeps the scope order, also with a search', () {
      const scope = VodScope.ids([5, 1, 3]);
      expect(_ids(_movies.query(scope: scope, sort: VodSort.myOrder)), [
        5,
        1,
        3,
      ]);
      final all = _ids(_movies.query(scope: scope, sort: VodSort.myOrder));
      final found = _ids(
        _movies.query(
          scope: scope,
          sort: VodSort.myOrder,
          search: _movies.items.firstWhere((m) => m.streamId == 1).name,
        ),
      );
      expect(found, [
        for (final id in all)
          if (found.contains(id)) id,
      ]);
    });

    test('byName', () {
      expect(VodSort.byName('myOrder'), VodSort.myOrder);
      expect(VodSort.byName('rating'), VodSort.rating);
      expect(VodSort.byName('nope'), isNull);
      expect(VodSort.byName(null), isNull);
    });
  });

  group('year filter', () {
    test('quick picks are relative to the current year', () {
      List<int> recent(int years) => _ids(
        _movies.query(
          filters: VodFilters(years: YearFilter.recent(years)),
          currentYear: 2026,
        ),
      );
      expect(recent(1), [1]);
      expect(recent(2), [1, 5]);
      expect(recent(5), [1, 2, 5]);
    });

    test('custom ranges, open ends; items without a year are left out', () {
      List<int> range(int? from, int? to) => _ids(
        _movies.query(
          filters: VodFilters(
            years: YearFilter.range(from: from, to: to),
          ),
          currentYear: 2026,
        ),
      );
      expect(range(2019, 2024), [2, 3]);
      expect(range(null, 2019), [3]);
      expect(range(2025, null), [1, 5]);
      // Without a year filter, the item without a year is included.
      expect(_movies.query().length, 5);
    });

    test('series use the release date, then the title year', () {
      List<int> range(int from, int to) => _sids(
        _series.query(
          filters: VodFilters(
            years: YearFilter.range(from: from, to: to),
          ),
        ),
      );
      expect(range(2021, 2021), [10]);
      expect(range(2010, 2010), isEmpty);
      expect(range(2025, 2025), [12]);
    });

    test('equality', () {
      expect(const YearFilter.recent(2), const YearFilter.recent(2));
      expect(
        const YearFilter.range(from: 2000),
        isNot(const YearFilter.range(from: 2000, to: 2001)),
      );
      expect(
        const VodFilters(genres: {'A', 'B'}),
        const VodFilters(genres: {'B', 'A'}),
      );
      expect(const VodFilters().isEmpty, isTrue);
      expect(const VodFilters(genres: {'A'}).isEmpty, isFalse);
    });
  });

  group('genres', () {
    test('splitGenres', () {
      expect(splitGenres('Crime / Drama / Mystery'), [
        'Crime',
        'Drama',
        'Mystery',
      ]);
      expect(splitGenres('Action & Adventure / Mystery'), [
        'Action & Adventure',
        'Mystery',
      ]);
      expect(splitGenres('Drama,Comedy | drama'), ['Drama', 'Comedy']);
      expect(splitGenres(' Sci-Fi  &  Fantasy '), ['Sci-Fi & Fantasy']);
      expect(splitGenres(''), isEmpty);
      expect(splitGenres(null), isEmpty);
    });

    test('series filter keeps items with any selected genre', () {
      List<int> withGenres(Set<String> genres) =>
          _sids(_series.query(filters: VodFilters(genres: genres)));
      expect(withGenres({'Mystery'}), [10, 11]);
      expect(withGenres({'action & adventure'}), [11]);
      expect(withGenres({'Reality', 'Crime'}), [10, 12]);
      expect(withGenres({'Western'}), isEmpty);
    });

    test('genre counts, most common first', () {
      expect(_series.genreCounts(), [
        (genre: 'Mystery', count: 2),
        (genre: 'Action & Adventure', count: 1),
        (genre: 'Crime', count: 1),
        (genre: 'Drama', count: 1),
        (genre: 'Reality', count: 1),
      ]);
    });

    test('movies have no provider genres; a source can be plugged in', () {
      expect(_movies.genreSource, isNull);
      expect(_movies.genreCounts(), isEmpty);
      // Without a source a genre filter changes nothing.
      expect(
        _movies.query(filters: const VodFilters(genres: {'Drama'})).length,
        5,
      );
      List<String> source(Movie m) => m.streamId.isOdd ? ['Drama'] : [];
      expect(
        _ids(
          _movies.query(
            filters: const VodFilters(genres: {'Drama'}),
            genres: source,
          ),
        ),
        [1, 3, 5],
      );
      expect(_movies.genreCounts(genres: source), [(genre: 'Drama', count: 3)]);
    });
  });

  test('scope, search, filters and sort apply together', () {
    final found = _movies.query(
      scope: const VodScope.category('a'),
      search: 'r',
      filters: const VodFilters(years: YearFilter.range(from: 2020)),
      sort: VodSort.title,
    );
    // "Zebra Road" and "Bramble" contain an r; "Ébène Nights" is 2019.
    expect(_ids(found), [5, 1]);
    // Hidden categories leave All, and the search ignores tags.
    expect(
      _ids(
        _movies.query(
          scope: const VodScope.all(hidden: {'a'}),
          search: 'en',
        ),
      ),
      isEmpty,
    );
  });

  test('an attached search index is used; a wrong one is refused', () {
    final catalog = VodCatalog.movies(
      categories: const [],
      items: const [
        Movie(streamId: 1, name: 'One'),
        Movie(streamId: 2, name: 'Two'),
      ],
      fetchedAt: _t0,
    );
    final index = SearchIndex(catalog.names);
    catalog.attachSearchIndex(index);
    expect(catalog.searchIndex, same(index));
    expect(
      () => catalog.attachSearchIndex(SearchIndex(['x'])),
      throwsArgumentError,
    );
  });

  group('live search', () {
    final catalog = LiveCatalog(
      categories: const [
        Category(id: 'se', name: 'SE'),
        Category(id: 'uk', name: 'UK'),
      ],
      channels: const [
        LiveStream(id: '1', name: '### SWEDEN ###', categoryIds: ['se']),
        LiveStream(id: '2', name: 'SVT 1 HD', categoryIds: ['se']),
        LiveStream(id: '3', name: 'SVT 2', categoryIds: ['se']),
        LiveStream(id: '4', name: 'News One', categoryIds: ['uk']),
        LiveStream(id: '5', name: 'SVT1 Play', categoryIds: ['uk']),
      ],
    );

    List<String> ids(List<LiveStream> list) => [for (final c in list) c.id];

    test('finds channels, without separators', () {
      expect(ids(catalog.search('svt1')), ['2', '5']);
      expect(ids(catalog.search('sweden')), isEmpty);
      expect(ids(catalog.search('')), ['2', '3', '4', '5']);
    });

    test('within a list, in its order or ranked', () {
      expect(ids(catalog.search('svt', within: catalog.channelsIn('uk'))), [
        '5',
      ]);
      expect(ids(catalog.search('one', ranked: true)), ['4']);
      expect(ids(catalog.search('svt 2', ranked: true)), ['3']);
      expect(ids(catalog.search('svt', ranked: true)), ['2', '3', '5']);
    });
  });
}
