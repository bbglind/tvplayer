import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

const _config = ProviderConfig.xtream(
  host: 'http://example.com:8080',
  username: 'testuser',
  password: 'testpass',
);

/// Serves fixtures by `action` and counts requests.
MockClient _panel(Map<String, String> responses, [List<String>? log]) =>
    MockClient((request) async {
      final action = request.url.queryParameters['action'] ?? 'login';
      log?.add(action);
      final body = responses[action];
      return body == null
          ? http.Response('', 404)
          : http.Response.bytes(utf8.encode(body), 200);
    });

final _now = DateTime.utc(2026, 1, 1);

void main() {
  group('models', () {
    test('Movie keeps tmdb and imdb ids and survives toJson', () {
      final movie = Movie.fromJson({
        'stream_id': 5,
        'name': 'Some Movie (1999)',
        'stream_icon': 'http://example.com/p.jpg',
        'category_id': '3',
        'rating': '6.5',
        'added': '1704067200',
        'container_extension': 'mkv',
        'tmdb': '123',
        'imdb_id': 'https://www.imdb.com/title/tt0000123/',
      })!;
      expect(movie.tmdbId, '123');
      expect(movie.imdbId, 'tt0000123');
      expect(movie.year, 1999);
      final back = Movie.fromJson(movie.toJson())!;
      expect(back.streamId, 5);
      expect(back.name, movie.name);
      expect(back.posterUrl, movie.posterUrl);
      expect(back.categoryId, '3');
      expect(back.rating, 6.5);
      expect(back.added, movie.added);
      expect(back.containerExtension, 'mkv');
      expect(back.tmdbId, '123');
      expect(back.imdbId, 'tt0000123');
    });

    test('vod info year, ids and details', () {
      final movie = Movie.fromVodInfoJson(
        jsonDecode(fixture('xtream/vod_info.json')) as Map<String, Object?>,
      )!;
      expect(movie.year, 2020);
      expect(movie.tmdbId, '12345');
      expect(movie.duration, const Duration(minutes: 90));
      expect(movie.cast, 'Actor One, Actor Two');
    });

    test('Series keeps ids and survives toJson', () {
      final list = jsonDecode(fixture('xtream/series.json')) as List;
      final series = Series.fromJson({
        ...(list.first as Map<String, Object?>),
        'tmdb': 77,
        'imdb': 'tt0000777',
      })!;
      expect(series.year, 2019);
      expect(series.tmdbId, '77');
      final back = Series.fromJson(series.toJson())!;
      expect(back.seriesId, 301);
      expect(back.name, 'Test Series 1');
      expect(back.coverUrl, series.coverUrl);
      expect(back.genre, 'Comedy');
      expect(back.rating, 8);
      expect(back.lastModified, series.lastModified);
      expect(back.tmdbId, '77');
      expect(back.imdbId, 'tt0000777');
    });
  });

  group('VodCatalog', () {
    VodCatalog<Movie> catalog() => VodCatalog.movies(
      categories: const [
        Category(id: 'a', name: 'Action'),
        Category(id: 'd', name: 'Drama'),
      ],
      items: [
        for (var i = 0; i < 30000; i++)
          Movie(
            streamId: i,
            name: 'Movie ${i.toString().padLeft(5, '0')}',
            categoryId: i.isEven ? 'a' : 'd',
          ),
      ],
      fetchedAt: _now,
    );

    test('filters by category and name, fast for large catalogues', () {
      final c = catalog();
      expect(c.countIn('a'), 15000);
      expect(c.countIn('x'), 0);
      expect(c.query().length, 30000);
      expect(c.query(scope: const VodScope.category('d')).first.streamId, 1);
      // Words match anywhere in a name, so "Movie 02999" and "Movie 12999"
      // match too.
      final found = c.query(search: 'MOVIE 2999');
      expect(
        [for (final m in found) m.streamId],
        [2999, 12999, 22999, for (var i = 29990; i < 30000; i++) i],
      );
      expect(
        c
            .query(scope: const VodScope.category('a'), search: 'movie 2999')
            .map((m) => m.streamId),
        [29990, 29992, 29994, 29996, 29998],
      );
      expect(c.byId(123)?.name, 'Movie 00123');
      expect(c.byId(-1), isNull);
    });

    test('JSON round trip', () {
      final c = catalog();
      final back = VodCatalog.moviesFromJson(
        jsonDecode(jsonEncode(c.toJson((m) => m.toJson()))),
      )!;
      expect(back.items, hasLength(30000));
      expect(back.categories.map((c) => c.name), ['Action', 'Drama']);
      expect(back.fetchedAt, _now);
      expect(back.countIn('a'), 15000);
      expect(VodCatalog.moviesFromJson({'items': []}), isNull);
      expect(VodCatalog.seriesFromJson('x'), isNull);
    });
  });

  group('XtreamVodSource', () {
    test('loads movies and series with categories', () async {
      final source = XtreamVodSource(
        XtreamClient(
          _config,
          httpClient: _panel({
            'get_vod_categories':
                '[{"category_id": "10", "category_name": "Films"}]',
            'get_vod_streams': fixture('xtream/vod_streams.json'),
            'get_series_categories':
                '[{"category_id": "20", "category_name": "Shows"}]',
            'get_series': fixture('xtream/series.json'),
          }),
        ),
      );
      final movies = await source.loadMovies(now: _now);
      expect(movies.items.map((m) => m.name), ['Test Movie 1', 'Test Movie 2']);
      expect(movies.countIn('10'), 1);
      expect(movies.fetchedAt, _now);
      final series = await source.loadSeries(now: _now);
      expect(series.items, hasLength(2));
      expect(series.categories.single.name, 'Shows');
    });

    test('parses very large lists in the background', () async {
      final big = jsonEncode([
        for (var i = 0; i < 20000; i++)
          {'stream_id': i, 'name': 'Movie $i', 'category_id': '1'},
      ]);
      expect(big.length, greaterThan(XtreamClient.backgroundParseBytes));
      final source = XtreamVodSource(
        XtreamClient(
          _config,
          httpClient: _panel({
            'get_vod_categories': '[]',
            'get_vod_streams': big,
          }),
        ),
      );
      final movies = await source.loadMovies(now: _now);
      expect(movies.items, hasLength(20000));
      expect(movies.items.last.name, 'Movie 19999');
    });

    test('reuses recent series info, but retries failures', () async {
      final log = <String>[];
      final responses = <String, String>{};
      final source = XtreamVodSource(
        XtreamClient(_config, httpClient: _panel(responses, log)),
      );
      await expectLater(
        source.seriesInfo(301),
        throwsA(isA<XtreamException>()),
      );
      responses['get_series_info'] = fixture('xtream/series_info.json');
      final info = await source.seriesInfo(301);
      expect(info.episodes, isNotEmpty);
      await source.seriesInfo(301);
      expect(log, ['get_series_info', 'get_series_info']);
    });

    test('M3U providers have no movies or series', () {
      expect(
        VodSource.forConfig(
          const ProviderConfig.m3u(playlistUrl: 'http://example.com/a.m3u'),
        ),
        isNull,
      );
    });
  });

  group('metadata', () {
    final infoJson =
        jsonDecode(fixture('xtream/series_info.json')) as Map<String, Object?>;

    test('provider source maps vod info and series info', () async {
      final source = XtreamVodSource(
        XtreamClient(
          _config,
          httpClient: _panel({
            'get_vod_info': fixture('xtream/vod_info.json'),
            'get_series_info': jsonEncode(infoJson),
          }),
        ),
      );
      final metadata = ProviderMetadataSource(source);
      final movie = (await metadata.movie(
        const Movie(streamId: 201, name: 'Test Movie 1', tmdbId: '12345'),
      ))!;
      expect(movie.title, 'Test Movie 1');
      expect(movie.year, 2020);
      expect(movie.plot, 'A synthetic plot for testing.');
      expect(movie.genre, 'Drama');
      expect(movie.rating, 7.5);
      expect(movie.duration, const Duration(minutes: 90));
      expect(movie.cast, 'Actor One, Actor Two');
      expect(movie.tmdbId, '12345');

      final series = (await metadata.series(
        const Series(seriesId: 301, name: 'Test Series 1'),
      ))!;
      expect(series.plot, 'A synthetic series.');
      final episode = series.episode(
        const Episode(id: '3002', season: 1, episodeNumber: 2, title: ''),
      )!;
      expect(episode.stillUrl, 'http://example.com/stills/e2.jpg');
      expect(episode.title, 'Test Series 1 - S01E02');
    });

    test('combined source: earlier wins, later fills gaps, failures are '
        'skipped', () async {
      final combined = CombinedMetadataSource([
        _FixedSource(
          const MediaMetadata(
            title: 'Provider title',
            episodes: {(1, 1): EpisodeMetadata(title: 'Pilot')},
          ),
        ),
        _FixedSource(null, error: StateError('offline')),
        _FixedSource(
          const MediaMetadata(
            title: 'Other title',
            plot: 'Other plot',
            imdbId: 'tt0000001',
            episodes: {
              (1, 1): EpisodeMetadata(title: 'Other', plot: 'Ep plot'),
              (1, 2): EpisodeMetadata(title: 'Second'),
            },
          ),
        ),
      ]);
      const movie = Movie(streamId: 1, name: 'x');
      final m = (await combined.movie(movie))!;
      expect(m.title, 'Provider title');
      expect(m.plot, 'Other plot');
      expect(m.imdbId, 'tt0000001');
      expect(m.episodes[(1, 1)]!.title, 'Pilot');
      expect(m.episodes[(1, 1)]!.plot, 'Ep plot');
      expect(m.episodes[(1, 2)]!.title, 'Second');
    });

    test('combined source rethrows when every source fails', () async {
      final combined = CombinedMetadataSource([
        _FixedSource(null, error: StateError('first')),
        _FixedSource(null, error: StateError('second')),
      ]);
      await expectLater(
        combined.series(const Series(seriesId: 1, name: 'x')),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'first')),
      );
      expect(
        await CombinedMetadataSource([
          _FixedSource(null),
        ]).movie(const Movie(streamId: 1, name: 'x')),
        isNull,
      );
    });
  });

  test('providerKey is stable and hides the provider', () {
    final key = providerKey(_config);
    expect(key, hasLength(16));
    expect(key, providerKey(_config));
    expect(key, isNot(contains('example')));
    expect(key, isNot(contains('testuser')));
    // A new password keeps the same data.
    expect(
      providerKey(
        const ProviderConfig.xtream(
          host: 'http://example.com:8080',
          username: 'testuser',
          password: 'other',
        ),
      ),
      key,
    );
    expect(
      providerKey(
        const ProviderConfig.xtream(
          host: 'http://example.com:8080',
          username: 'otheruser',
          password: 'testpass',
        ),
      ),
      isNot(key),
    );
  });
}

class _FixedSource implements MetadataSource {
  _FixedSource(this.result, {this.error});

  final MediaMetadata? result;
  final Object? error;

  Future<MediaMetadata?> _answer() async {
    if (error case final e?) throw e;
    return result;
  }

  @override
  Future<MediaMetadata?> movie(Movie movie) => _answer();

  @override
  Future<MediaMetadata?> series(Series series) => _answer();
}
