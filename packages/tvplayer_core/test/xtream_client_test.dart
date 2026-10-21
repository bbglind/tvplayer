import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

const _config = ProviderConfig.xtream(
  host: 'http://example.com:8080/',
  username: 'testuser',
  password: 'testpass',
);

/// Serves fixtures by `action`; records the requests made.
class _FakePanel {
  final requests = <Uri>[];
  final responses = <String, String>{};

  late final client = MockClient((request) async {
    requests.add(request.url);
    final action = request.url.queryParameters['action'] ?? 'login';
    final body = responses[action];
    if (body == null) return http.Response('', 404);
    // No charset on purpose: the client must still decode UTF-8.
    return http.Response.bytes(
      utf8.encode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  late _FakePanel panel;
  late XtreamClient xtream;

  setUp(() {
    panel = _FakePanel();
    xtream = XtreamClient(_config, httpClient: panel.client);
  });

  group('requests', () {
    test('use player_api.php with credentials and action', () async {
      panel.responses['get_live_streams'] = '[]';
      await xtream.getLiveStreams(categoryId: '1');
      final uri = panel.requests.single;
      expect(uri.scheme, 'http');
      expect(uri.host, 'example.com');
      expect(uri.port, 8080);
      expect(uri.path, '/player_api.php');
      expect(uri.queryParameters, {
        'username': 'testuser',
        'password': 'testpass',
        'action': 'get_live_streams',
        'category_id': '1',
      });
    });

    test('host without scheme defaults to http', () async {
      final client = XtreamClient(
        const ProviderConfig.xtream(
          host: 'example.com',
          username: 'testuser',
          password: 'testpass',
        ),
        httpClient: panel.client,
      );
      panel.responses['get_live_categories'] = '[]';
      await client.getLiveCategories();
      expect(
        panel.requests.single.toString(),
        startsWith('http://example.com/player_api.php?'),
      );
    });

    test('rejects non-xtream configs', () {
      expect(
        () => XtreamClient(
          const ProviderConfig.m3u(playlistUrl: 'http://example.com/a.m3u'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('login', () {
    test('returns account info without credentials', () async {
      panel.responses['login'] = fixture('xtream/account_info.json');
      final info = await xtream.login();
      expect(info.status, 'Active');
      expect(info.isActive, isTrue);
      expect(info.expiresAt, DateTime.utc(2030, 1, 1));
      expect(info.isTrial, isFalse);
      expect(info.maxConnections, 2);
      expect(info.activeConnections, 0);
      expect(info.allowedOutputFormats, ['m3u8', 'ts']);
      expect(info.serverTimezone, 'UTC');
      expect(info.toString(), isNot(contains('testpass')));
    });

    test('throws XtreamAuthException when auth is 0', () async {
      panel.responses['login'] = fixture('xtream/account_info_denied.json');
      await expectLater(xtream.login(), throwsA(isA<XtreamAuthException>()));
    });

    test('throws XtreamAuthException on HTTP 401', () async {
      final client = XtreamClient(
        _config,
        httpClient: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(client.login(), throwsA(isA<XtreamAuthException>()));
    });
  });

  test('categories tolerate mixed types, unicode and missing ids', () async {
    panel.responses['get_live_categories'] = fixture(
      'xtream/live_categories.json',
    );
    final categories = await xtream.getLiveCategories();
    expect(categories.map((c) => c.id), ['1', '2', '3']);
    expect(categories[2].name, 'Tëst Ünïcode 测试 📺');
    expect(categories[0].parentId, '0');
    expect(categories[2].parentId, isNull);
  });

  test('vod and series categories use their own actions', () async {
    panel.responses['get_vod_categories'] = '[]';
    panel.responses['get_series_categories'] = '[]';
    expect(await xtream.getVodCategories(), isEmpty);
    expect(await xtream.getSeriesCategories(), isEmpty);
    expect(panel.requests.map((u) => u.queryParameters['action']), [
      'get_vod_categories',
      'get_series_categories',
    ]);
  });

  test('live streams', () async {
    panel.responses['get_live_streams'] = fixture('xtream/live_streams.json');
    final channels = await xtream.getLiveStreams();
    expect(channels.map((c) => c.streamId), [101, 102, 103]);

    final first = channels[0];
    expect(first.name, 'Test Channel 1');
    expect(first.number, 1);
    expect(first.logoUrl, 'http://example.com/logos/test1.png');
    expect(first.epgChannelId, 'test1.example');
    expect(first.categoryId, '1');
    expect(first.categoryIds, ['1']);
    expect(first.hasArchive, isTrue);
    expect(first.archiveDays, 7);
    expect(first.added, DateTime.utc(2024, 1, 1));

    final second = channels[1];
    expect(second.name, 'Test Channel 2 Ünïcode');
    expect(second.number, 2);
    expect(second.logoUrl, isNull);
    expect(second.epgChannelId, isNull);
    expect(second.hasArchive, isFalse);
    expect(second.added, isNull);

    expect(channels[2].name, 'Test Channel 3 minimal');
  });

  test('VOD streams', () async {
    panel.responses['get_vod_streams'] = fixture('xtream/vod_streams.json');
    final movies = await xtream.getVodStreams();
    expect(movies, hasLength(2));
    expect(movies[0].containerExtension, 'mkv');
    expect(movies[0].rating, 7.5);
    expect(movies[0].tmdbId, '12345');
    expect(movies[1].streamId, 202);
    expect(movies[1].rating, isNull);
    expect(movies[1].containerExtension, isNull);
  });

  test('VOD info', () async {
    panel.responses['get_vod_info'] = fixture('xtream/vod_info.json');
    final movie = await xtream.getVodInfo(201);
    expect(panel.requests.single.queryParameters['vod_id'], '201');
    expect(movie.streamId, 201);
    expect(movie.name, 'Test Movie 1');
    expect(movie.containerExtension, 'mkv');
    expect(movie.plot, 'A synthetic plot for testing.');
    expect(movie.duration, const Duration(minutes: 90));
    expect(movie.backdropUrls, ['http://example.com/backdrops/movie1.jpg']);
    expect(movie.trailerId, isNull);
    expect(movie.tmdbId, '12345');
  });

  test('VOD info for unknown movie throws', () async {
    panel.responses['get_vod_info'] = '{"info": [], "movie_data": []}';
    await expectLater(xtream.getVodInfo(999), throwsA(isA<XtreamException>()));
  });

  test('series list', () async {
    panel.responses['get_series'] = fixture('xtream/series.json');
    final series = await xtream.getSeries();
    expect(series.map((s) => s.seriesId), [301, 302]);
    expect(series[0].rating, 8.0);
    expect(series[0].cast, isNull);
    expect(series[0].backdropUrls, isEmpty);
    expect(series[0].lastModified, DateTime.utc(2024, 1, 1));
  });

  group('series info', () {
    test('episodes keyed by season', () async {
      panel.responses['get_series_info'] = fixture('xtream/series_info.json');
      final info = await xtream.getSeriesInfo(301);
      expect(panel.requests.single.queryParameters['series_id'], '301');
      expect(info.series.seriesId, 301);
      expect(info.series.name, 'Test Series 1');
      expect(info.seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(info.seasons[0].episodeCount, 2);
      expect(info.seasons[1].name, 'Season 2');
      expect(info.episodes.map((e) => e.id), ['3001', '3002', '4001']);
      final e2 = info.episodes[1];
      expect(e2.season, 1);
      expect(e2.episodeNumber, 2);
      expect(e2.containerExtension, 'mkv');
      expect(e2.duration, const Duration(seconds: 1450));
      expect(e2.rating, 7.1);
      expect(info.episodesForSeason(2).single.title, 'Test Series 1 - S02E01');
    });

    test('episodes as list of lists, without seasons', () async {
      panel.responses['get_series_info'] = fixture(
        'xtream/series_info_list_episodes.json',
      );
      final info = await xtream.getSeriesInfo(302);
      expect(info.series.seriesId, 302);
      expect(info.seasons.map((s) => s.seasonNumber), [1, 3]);
      expect(info.episodes.map((e) => e.id), ['5001', '5101']);
      expect(info.episodes[1].title, 'Episode 1');
    });
  });

  group('short EPG', () {
    test('decodes base64 and uses timestamps', () async {
      panel.responses['get_short_epg'] = fixture('xtream/short_epg.json');
      final programs = await xtream.getShortEpg(101, limit: 4);
      expect(panel.requests.single.queryParameters, containsPair('limit', '4'));
      expect(programs, hasLength(2));
      expect(programs[0].title, 'Test Morning Show');
      expect(programs[0].description, 'Ünïcode description – 测试');
      expect(programs[0].start, DateTime.utc(2024, 1, 1, 8));
      expect(programs[0].stop, DateTime.utc(2024, 1, 1, 9));
      expect(programs[0].channelId, 'test1.example');
      // Plain text and string dates are accepted as fallback.
      expect(programs[1].title, 'Plain Title');
      expect(programs[1].start, DateTime.utc(2024, 1, 1, 9));
    });

    test('empty response yields no programmes', () async {
      panel.responses['get_short_epg'] = '{"epg_listings": []}';
      expect(await xtream.getShortEpg(101), isEmpty);
    });
  });

  group('errors never leak credentials or URLs', () {
    Matcher leaksNothing() => isA<XtreamException>().having(
      (e) => e.toString(),
      'toString',
      allOf(
        isNot(contains('testuser')),
        isNot(contains('testpass')),
        isNot(contains('example.com')),
        isNot(contains('player_api')),
      ),
    );

    test('HTTP error', () async {
      panel.responses.clear();
      await expectLater(xtream.getLiveStreams(), throwsA(leaksNothing()));
    });

    test('invalid JSON echoing credentials', () async {
      panel.responses['get_live_streams'] =
          '{"username": "testuser", "password": "testpass", broken';
      await expectLater(xtream.getLiveStreams(), throwsA(leaksNothing()));
    });

    test('network error', () async {
      final client = XtreamClient(
        _config,
        httpClient: MockClient(
          (request) async => throw http.ClientException(
            'Connection refused to example.com for testuser:testpass',
            request.url,
          ),
        ),
      );
      await expectLater(client.login(), throwsA(leaksNothing()));
    });

    test('client toString', () {
      expect(xtream.toString(), isNot(contains('testpass')));
    });
  });

  group('URL builders', () {
    test('live stream defaults to .ts', () {
      expect(
        xtream.liveStreamUrl(101).toString(),
        'http://example.com:8080/live/testuser/testpass/101.ts',
      );
      expect(
        xtream.liveStreamUrl(101, extension: 'm3u8').path,
        '/live/testuser/testpass/101.m3u8',
      );
    });

    test('movie uses container extension', () {
      const movie = Movie(streamId: 201, name: 'M', containerExtension: 'mkv');
      expect(
        xtream.movieUrl(movie).toString(),
        'http://example.com:8080/movie/testuser/testpass/201.mkv',
      );
      expect(
        xtream.movieUrl(const Movie(streamId: 202, name: 'M')).path,
        endsWith('/202.mp4'),
      );
    });

    test('episode uses container extension', () {
      const episode = Episode(
        id: '3001',
        season: 1,
        episodeNumber: 1,
        title: 'E',
        containerExtension: 'mkv',
      );
      expect(
        xtream.episodeUrl(episode).toString(),
        'http://example.com:8080/series/testuser/testpass/3001.mkv',
      );
    });

    test('credentials are percent-encoded', () {
      final client = XtreamClient(
        const ProviderConfig.xtream(
          host: 'https://example.com/sub/',
          username: 'test user',
          password: 'p/ss',
        ),
        httpClient: panel.client,
      );
      expect(
        client.liveStreamUrl(1).toString(),
        'https://example.com/sub/live/test%20user/p%2Fss/1.ts',
      );
    });

    test('xmltv url', () {
      expect(
        xtream.xmltvUrl().toString(),
        'http://example.com:8080/xmltv.php?username=testuser&password=testpass',
      );
    });
  });
}
