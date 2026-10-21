import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

const _playlistUrl =
    'http://example.com/get.php?username=testuser&password=testpass';

http.Response _utf8(String body) => http.Response.bytes(utf8.encode(body), 200);

void main() {
  group('M3uClient', () {
    test('fetches and parses a playlist', () async {
      final client = M3uClient(
        _playlistUrl,
        httpClient: MockClient((_) async => _utf8(fixture('playlist.m3u'))),
      );
      final entries = await client.fetch();
      expect(entries, isNotEmpty);
      expect(entries.first.name, 'Test Channel 1');
    });

    test('rejects non-http URLs', () {
      expect(() => M3uClient('not a url'), throwsArgumentError);
      expect(() => M3uClient('ftp://example.com/x.m3u'), throwsArgumentError);
    });

    test('reports HTTP errors without the URL', () async {
      final client = M3uClient(
        _playlistUrl,
        httpClient: MockClient((_) async => http.Response('', 403)),
      );
      await expectLater(
        client.fetch(),
        throwsA(
          isA<M3uException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('testpass')),
              ),
        ),
      );
    });

    test('rejects a non-playlist body', () async {
      final client = M3uClient(
        _playlistUrl,
        httpClient: MockClient(
          (_) async => http.Response('<html><body>Login</body></html>', 200),
        ),
      );
      await expectLater(client.fetch(), throwsA(isA<M3uException>()));
    });

    test('redacts network error messages', () async {
      final client = M3uClient(
        _playlistUrl,
        httpClient: MockClient(
          (_) async =>
              throw http.ClientException('failed to reach example.com'),
        ),
      );
      await expectLater(
        client.fetch(),
        throwsA(
          isA<M3uException>().having(
            (e) => e.message,
            'message',
            isNot(contains('example.com')),
          ),
        ),
      );
    });
  });

  group('M3uLiveSource', () {
    test('groups by group-title and resolves URLs', () async {
      final source = LiveSource.forConfig(
        const ProviderConfig.m3u(playlistUrl: _playlistUrl),
        httpClient: MockClient((_) async => _utf8(fixture('playlist.m3u'))),
      );
      final catalog = await source.load();
      final names = catalog.categories.map((c) => c.name).toList();
      expect(names, containsAll(['Test News', 'Test Sports']));
      final news = catalog.channelsIn('Test News');
      expect(news.single.name, 'Test Channel 1');
      expect(
        source.streamUrl(news.single).path,
        '/live/testuser/testpass/101.ts',
      );
      expect(catalog.channelsIn(null).length, catalog.channels.length);
    });
  });

  group('XtreamLiveSource', () {
    const config = ProviderConfig.xtream(
      host: 'http://example.com:8080',
      username: 'testuser',
      password: 'testpass',
    );

    test('loads categories and streams', () async {
      final source = LiveSource.forConfig(
        config,
        httpClient: MockClient((request) async {
          final action = request.url.queryParameters['action'];
          final body = switch (action) {
            'get_live_categories' => fixture('xtream/live_categories.json'),
            'get_live_streams' => fixture('xtream/live_streams.json'),
            _ => null,
          };
          return body == null
              ? http.Response('', 404)
              : http.Response.bytes(utf8.encode(body), 200);
        }),
      );
      final catalog = await source.load();
      expect(catalog.categories, isNotEmpty);
      expect(catalog.channels, isNotEmpty);
      final first = catalog.channels.first;
      expect(source.streamUrl(first).pathSegments, [
        'live',
        'testuser',
        'testpass',
        '${first.id}.ts',
      ]);
      for (final c in catalog.categories) {
        for (final ch in catalog.channelsIn(c.id)) {
          expect(ch.categoryIds, contains(c.id));
        }
      }
    });

    test('propagates auth errors', () async {
      final source = LiveSource.forConfig(
        config,
        httpClient: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(source.load(), throwsA(isA<XtreamAuthException>()));
    });
  });
}
