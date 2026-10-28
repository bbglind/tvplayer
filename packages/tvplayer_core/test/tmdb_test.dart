import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

Map<String, Object?> _json(String name) =>
    jsonDecode(fixture('tmdb/$name')) as Map<String, Object?>;

final _at = DateTime.utc(2026, 1, 1);

/// A clock that only moves when slept on.
class _FakeTime {
  DateTime now = DateTime.utc(2026, 1, 1);
  final slept = <Duration>[];

  Future<void> sleep(Duration d) async {
    slept.add(d);
    now = now.add(d);
  }
}

// Placeholder credentials, not real ones.
const _apiKey = '0123456789abcdef0123456789abcdef';
final _token = 'eyJ${'a' * 60}.payload.signature';

void main() {
  group('TmdbCredential', () {
    test('tells an API key from a read access token', () {
      expect(
        TmdbCredential.parse(' $_apiKey ')!.kind,
        TmdbCredentialKind.apiKey,
      );
      expect(TmdbCredential.parse(_token)!.kind, TmdbCredentialKind.bearer);
      expect(
        TmdbCredential.parse('Bearer $_token')!.value,
        _token,
        reason: 'a pasted "Bearer " prefix is dropped',
      );
    });

    test('rejects empty and malformed text', () {
      expect(TmdbCredential.parse(''), isNull);
      expect(TmdbCredential.parse('short'), isNull);
      expect(TmdbCredential.parse('two words here'), isNull);
    });

    test('never shows the value', () {
      expect('${TmdbCredential.parse(_apiKey)}', isNot(contains(_apiKey)));
      expect('${TmdbCredential.parse(_token)}', isNot(contains(_token)));
    });

    test('sends the key as a header or a query parameter', () {
      final key = TmdbCredential.parse(_apiKey)!;
      expect(key.query, {'api_key': _apiKey});
      expect(key.headers, isEmpty);
      final token = TmdbCredential.parse(_token)!;
      expect(token.headers, {'Authorization': 'Bearer $_token'});
      expect(token.query, isEmpty);
    });
  });

  group('models', () {
    test('parse a movie with its appended parts', () {
      final m = TmdbTitle.fromJson(
        TmdbKind.movie,
        _json('movie.json'),
        fetchedAt: _at,
      )!;
      expect(m.key, const TmdbKey(TmdbKind.movie, 1001));
      expect(m.title, 'Example Movie');
      expect(m.year, 2019);
      expect(m.runtimeMinutes, 128);
      expect(m.imdbId, 'tt0000001');
      expect(m.genreText, 'Drama, Crime');
      expect(m.cast.map((c) => c.name), ['Actor One', 'Actor Two']);
      expect(m.cast.first.character, 'Hero');
      expect(m.recommendations, const [
        TmdbKey(TmdbKind.movie, 1002),
        TmdbKey(TmdbKind.tv, 2002),
        TmdbKey(TmdbKind.movie, 1003),
      ]);
      expect(
        m.backdropPath,
        '/backdrop-plain-high.jpg',
        reason: 'a backdrop without text comes first, best voted',
      );
    });

    test('parse a series with its IMDb id from external_ids', () {
      final t = TmdbTitle.fromJson(
        TmdbKind.tv,
        _json('tv.json'),
        fetchedAt: _at,
      )!;
      expect(t.title, 'Example Series');
      expect(t.year, 2015);
      expect(t.seasonCount, 3);
      expect(t.runtimeMinutes, 45);
      expect(t.imdbId, 'tt0000002');
      expect(t.ongoing, isTrue);
      expect(t.backdropPath, '/tv-backdrop-en.jpg');
    });

    test('backdrop falls back to backdrop_path', () {
      expect(chooseBackdrop(null, '/b.jpg'), '/b.jpg');
      expect(chooseBackdrop(const {'backdrops': []}, null), isNull);
    });

    test('parse a season and a person', () {
      final s = TmdbSeason.fromJson(
        2001,
        1,
        _json('season.json'),
        fetchedAt: _at,
      );
      expect(s.episodes, hasLength(2));
      expect(s.episode(1)!.overview, 'First episode overview.');
      expect(s.episode(2)!.overview, isNull);
      final p = TmdbPerson.fromJson(_json('person.json'), fetchedAt: _at)!;
      expect(p.credits.map((c) => '${c.key}'), ['movie/1001', 'tv/2001']);
      expect(p.credits.first.year, 2019);
    });

    test('keys round-trip and read provider ids', () {
      expect(TmdbKey.parse('tv/7'), const TmdbKey(TmdbKind.tv, 7));
      expect(TmdbKey.parse('person/7'), isNull);
      expect(TmdbKey.fromProvider(TmdbKind.movie, '0'), isNull);
      expect(
        TmdbKey.fromProvider(TmdbKind.movie, ' 12 '),
        const TmdbKey(TmdbKind.movie, 12),
      );
      expect(TmdbKey.fromProvider(TmdbKind.movie, 'x'), isNull);
    });
  });

  group('title matching', () {
    final results = [
      for (final r in _json('search_movie.json')['results'] as List)
        TmdbSearchResult.fromJson(TmdbKind.movie, r as Map<String, Object?>)!,
    ];

    test('takes the result with the same title and year', () {
      expect(pickMatch('Example Movie', 2019, results)!.key.id, 1001);
      expect(pickMatch('example  movie!', 2020, results)!.key.id, 1001);
      expect(pickMatch('Exemple de film', 2019, results)!.key.id, 1001);
    });

    test('takes nothing when unsure', () {
      expect(pickMatch('Example Movie', null, results), isNull);
      expect(pickMatch('Example Movie', 2005, results), isNull);
      expect(pickMatch('Another', 2019, results), isNull);
    });

    test('keys titles by their normalised text and year', () {
      expect(titleKey('Example: Movie', 2019), titleKey('example movie', 2019));
      expect(titleKey('  ', 2019), isNull);
      final s = TitleSearch.of(
        TmdbKind.movie,
        'Example Movie (2019)',
        ProviderTags.empty,
      )!;
      expect(s.title, 'Example Movie');
      expect(s.year, 2019);
    });
  });

  group('DetailsView', () {
    final tmdb = TmdbTitle.fromJson(
      TmdbKind.movie,
      _json('movie.json'),
      fetchedAt: _at,
    )!;

    test('the provider wins; TMDB fills gaps', () {
      final v = DetailsView.combine(
        provider: const MediaMetadata(plot: 'Provider plot', rating: 0),
        tmdb: tmdb,
      );
      expect(v.plot, 'Provider plot');
      expect(v.genre, 'Drama, Crime');
      expect(v.year, 2019);
      expect(v.rating, 7.8, reason: 'a provider rating of 0 is no rating');
      expect(v.runtime, const Duration(minutes: 128));
      expect(v.people, hasLength(2));
    });

    test('TMDB backdrop first, the provider\'s as fallback', () {
      final v = DetailsView.combine(
        provider: const MediaMetadata(
          backdropUrls: ['http://example.com/b.jpg'],
        ),
        tmdb: tmdb,
      );
      expect(v.backdropUrl, '${tmdbImageBase}w1280/backdrop-plain-high.jpg');
      expect(
        DetailsView.combine(
          provider: const MediaMetadata(
            backdropUrls: ['http://example.com/b.jpg'],
          ),
        ).backdropUrl,
        'http://example.com/b.jpg',
      );
      expect(DetailsView.combine().backdropUrl, isNull);
    });

    test('posters follow the preference', () {
      const provider = 'http://example.com/p.jpg';
      expect(
        posterChoices(
          provider: provider,
          tmdbPath: '/t.jpg',
          preferTmdb: false,
        ),
        [provider, '${tmdbImageBase}w342/t.jpg'],
      );
      expect(
        posterChoices(provider: provider, tmdbPath: '/t.jpg', preferTmdb: true),
        ['${tmdbImageBase}w342/t.jpg', provider],
      );
      expect(
        posterChoices(provider: null, tmdbPath: null, preferTmdb: true),
        isEmpty,
      );
    });

    test('episodes keep the provider\'s text and fill gaps', () {
      const tmdbEpisode = TmdbEpisode(
        season: 1,
        number: 1,
        overview: 'TMDB overview',
        stillPath: '/still.jpg',
      );
      final filled = withTmdbEpisode(
        const EpisodeMetadata(title: 'Provider title'),
        tmdbEpisode,
      )!;
      expect(filled.title, 'Provider title');
      expect(filled.plot, 'TMDB overview');
      expect(filled.stillUrl, '${tmdbImageBase}w300/still.jpg');
      expect(
        withTmdbEpisode(const EpisodeMetadata(plot: 'Mine'), tmdbEpisode)!.plot,
        'Mine',
      );
    });
  });

  group('RateLimiter', () {
    test('spaces requests at the set rate', () async {
      final time = _FakeTime();
      final starts = <DateTime>[];
      final limiter = RateLimiter(
        perSecond: 10,
        now: () => time.now,
        sleep: time.sleep,
      );
      await Future.wait([
        for (var i = 0; i < 5; i++)
          limiter.run(() async => starts.add(time.now)),
      ]);
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i].difference(starts[i - 1]),
          greaterThanOrEqualTo(const Duration(milliseconds: 100)),
        );
      }
    });

    test('holds everything back during a back-off', () async {
      final time = _FakeTime();
      final limiter = RateLimiter(now: () => time.now, sleep: time.sleep);
      final start = time.now;
      limiter.backOff(const Duration(seconds: 5));
      await limiter.run(() async {});
      expect(time.now.difference(start), const Duration(seconds: 5));
    });

    test('limits the requests in flight', () async {
      final time = _FakeTime();
      final limiter = RateLimiter(
        maxInFlight: 2,
        now: () => time.now,
        sleep: time.sleep,
      );
      var running = 0;
      var most = 0;
      final gates = [for (var i = 0; i < 4; i++) Completer<void>()];
      final runs = [
        for (final gate in gates)
          limiter.run(() async {
            most = ++running > most ? running : most;
            await gate.future;
            running--;
          }),
      ];
      await Future<void>.delayed(Duration.zero);
      for (final gate in gates) {
        gate.complete();
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(runs);
      expect(most, 2);
    });

    test('backs off exponentially up to a minute', () {
      expect(exponentialBackOff(0), const Duration(seconds: 1));
      expect(exponentialBackOff(3), const Duration(seconds: 8));
      expect(exponentialBackOff(10), const Duration(seconds: 60));
    });
  });

  group('TmdbClient', () {
    TmdbClient clientFor(
      Future<http.Response> Function(http.Request) handler, {
      String credential = _apiKey,
      _FakeTime? time,
    }) {
      final t = time ?? _FakeTime();
      return TmdbClient(
        MockClient(handler),
        TmdbCredential.parse(credential)!,
        now: () => t.now,
        sleep: t.sleep,
      );
    }

    test('asks for everything in one English request', () async {
      late Uri asked;
      final client = clientFor((r) async {
        asked = r.url;
        return http.Response(fixture('tmdb/movie.json'), 200);
      });
      final m = await client.title(const TmdbKey(TmdbKind.movie, 1001));
      expect(m.title, 'Example Movie');
      expect(asked.path, '/3/movie/1001');
      expect(asked.queryParameters['language'], 'en-US');
      expect(
        asked.queryParameters['append_to_response'],
        'credits,recommendations,images',
      );
      expect(asked.queryParameters['include_image_language'], 'null,en');
      expect(asked.queryParameters['api_key'], _apiKey);
    });

    test('sends a read access token as a header', () async {
      late http.Request request;
      final client = clientFor((r) async {
        request = r;
        return http.Response(fixture('tmdb/tv.json'), 200);
      }, credential: _token);
      await client.title(const TmdbKey(TmdbKind.tv, 2001));
      expect(request.headers['Authorization'], 'Bearer $_token');
      expect(request.url.queryParameters, isNot(contains('api_key')));
      expect(
        request.url.queryParameters['append_to_response'],
        contains('external_ids'),
      );
    });

    test('waits out a 429 as Retry-After says, then continues', () async {
      final time = _FakeTime();
      var calls = 0;
      final client = clientFor((r) async {
        if (calls++ == 0) {
          return http.Response('', 429, headers: {'retry-after': '3'});
        }
        return http.Response(fixture('tmdb/movie.json'), 200);
      }, time: time);
      final start = time.now;
      await client.title(const TmdbKey(TmdbKind.movie, 1001));
      expect(calls, 2);
      expect(
        time.now.difference(start),
        greaterThanOrEqualTo(const Duration(seconds: 3)),
      );
    });

    test('backs off exponentially on a 429 without Retry-After', () async {
      final time = _FakeTime();
      var calls = 0;
      final client = clientFor((r) async {
        if (calls++ < 3) return http.Response('', 429);
        return http.Response(fixture('tmdb/movie.json'), 200);
      }, time: time);
      final start = time.now;
      await client.title(const TmdbKey(TmdbKind.movie, 1001));
      expect(calls, 4);
      // 1 + 2 + 4 seconds.
      expect(
        time.now.difference(start),
        greaterThanOrEqualTo(const Duration(seconds: 7)),
      );
    });

    test('errors name the failure, never the address or key', () async {
      Future<TmdbException> failure(
        Future<http.Response> Function(http.Request) handler,
      ) async {
        try {
          await clientFor(handler).title(const TmdbKey(TmdbKind.movie, 1));
        } on TmdbException catch (e) {
          return e;
        }
        fail('no exception');
      }

      final unauthorized = await failure((_) async => http.Response('', 401));
      expect(unauthorized.failure, TmdbFailure.unauthorized);
      expect(
        (await failure((_) async => http.Response('', 404))).failure,
        TmdbFailure.notFound,
      );
      expect(
        (await failure((_) async => http.Response('', 503))).failure,
        TmdbFailure.server,
      );
      final network = await failure(
        (r) async => throw http.ClientException('failed', r.url),
      );
      expect(network.failure, TmdbFailure.network);
      for (final e in [unauthorized, network]) {
        expect('$e', isNot(contains(_apiKey)));
        expect('$e', isNot(contains('themoviedb')));
      }
    });

    test('searches with the year', () async {
      late Uri asked;
      final client = clientFor((r) async {
        asked = r.url;
        return http.Response(fixture('tmdb/search_movie.json'), 200);
      });
      final results = await client.search(TmdbKind.tv, 'Example', year: 2015);
      expect(results, hasLength(3));
      expect(asked.path, '/3/search/tv');
      expect(asked.queryParameters['first_air_date_year'], '2015');
    });
  });
}
