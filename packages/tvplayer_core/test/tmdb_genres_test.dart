import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  group('providerGenresToTmdb', () {
    List<String> map(String genre) => providerGenresToTmdb(splitGenres(genre));

    test('maps provider names to TMDB series genres', () {
      expect(map('Drama / Crime'), ['Drama', 'Crime']);
      expect(map('Sci-Fi'), ['Sci-Fi & Fantasy']);
      expect(map('Science Fiction, Fantasy'), ['Sci-Fi & Fantasy']);
      expect(map('Action / Adventure'), ['Action & Adventure']);
      expect(map('Action & Adventure'), ['Action & Adventure']);
      expect(map('Action-Adventure'), ['Action & Adventure']);
      expect(map('War | Politics'), ['War & Politics']);
      expect(map("Children's"), ['Kids']);
      expect(map('Documentaries'), ['Documentary']);
      expect(map('Reality-TV'), ['Reality']);
      expect(map('Talk Show / Soap Opera'), ['Talk', 'Soap']);
      expect(map('animated'), ['Animation']);
      expect(map('COMEDY'), ['Comedy']);
    });

    test('keeps names TMDB has no series genre for, tidied', () {
      expect(map('Horror / Thriller'), ['Horror', 'Thriller']);
      expect(map('romance'), ['Romance']);
      expect(map('SPORT'), ['Sport']);
      expect(map('Anime'), ['Anime']);
      expect(map('Comédie dramatique'), ['Comédie dramatique']);
      expect(map('TV Movie'), ['TV Movie']);
    });

    test('nothing for no genre', () {
      expect(map(''), isEmpty);
      expect(
        providerSeriesGenres(const Series(seriesId: 1, name: 'A')),
        isEmpty,
      );
    });
  });

  group('genre sources', () {
    const movieKey = TmdbKey(TmdbKind.movie, 10);
    const tvKey = TmdbKey(TmdbKind.tv, 20);
    final links = TmdbLinks.build(
      movies: [
        (id: 1, name: 'Linked', tmdbId: '10', year: null),
        (id: 2, name: 'Unlinked', tmdbId: null, year: null),
      ],
      series: [
        (id: 5, name: 'With TMDB genres', tmdbId: '20', year: null),
        (id: 6, name: 'Linked, no genres', tmdbId: '21', year: null),
        (id: 7, name: 'Unlinked', tmdbId: null, year: null),
      ],
      tags: ProviderTags.empty,
      matches: const {},
      removed: const {},
    );
    final index = {
      movieKey: ['Science Fiction', 'Thriller'],
      tvKey: ['Sci-Fi & Fantasy'],
      const TmdbKey(TmdbKind.tv, 21): <String>[],
    };

    test('movies: TMDB movie genres only, none without', () {
      final source = tmdbMovieGenres(links, index);
      expect(source(const Movie(streamId: 1, name: 'Linked', genre: 'Drama')), [
        'Science Fiction',
        'Thriller',
      ]);
      expect(
        source(const Movie(streamId: 2, name: 'Unlinked', genre: 'Drama')),
        isEmpty,
      );
    });

    test('series: TMDB genres, else the provider genre mapped', () {
      final source = tmdbSeriesGenres(links, index);
      expect(source(const Series(seriesId: 5, name: 'A', genre: 'Drama')), [
        'Sci-Fi & Fantasy',
      ]);
      expect(source(const Series(seriesId: 6, name: 'B', genre: 'Sci-Fi')), [
        'Sci-Fi & Fantasy',
      ]);
      expect(source(const Series(seriesId: 7, name: 'C', genre: 'Crime')), [
        'Crime',
      ]);
    });

    test('a catalogue filters and counts by the source', () {
      final catalog = VodCatalog.movies(
        categories: const [],
        items: const [
          Movie(streamId: 1, name: 'Linked', categoryId: 'a'),
          Movie(streamId: 2, name: 'Unlinked', categoryId: 'a'),
        ],
        fetchedAt: DateTime.utc(2026),
      );
      final source = tmdbMovieGenres(links, index);
      expect(catalog.genreCounts(genres: source), [
        (genre: 'Science Fiction', count: 1),
        (genre: 'Thriller', count: 1),
      ]);
      expect(
        catalog
            .query(
              filters: const VodFilters(genres: {'thriller'}),
              genres: source,
            )
            .map((m) => m.name),
        ['Linked'],
        reason: 'movies without TMDB genres are left out',
      );
    });
  });

  test('genre families join movie and series names', () {
    expect(genreFamily('Science Fiction'), genreFamily('Sci-Fi & Fantasy'));
    expect(genreFamily('Fantasy'), genreFamily('Sci-Fi & Fantasy'));
    expect(genreFamily('Adventure'), genreFamily('Action & Adventure'));
    expect(genreFamily('War'), genreFamily('War & Politics'));
    expect(genreFamily('Drama'), isNot(genreFamily('Crime')));
  });
}
