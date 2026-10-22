import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tvplayer/data/poster_cache.dart';

const _host = 'http://192.0.2.1:8080';

void main() {
  late Directory dir;
  late List<String> requests;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('poster_cache_test');
    requests = [];
  });

  tearDown(() => dir.delete(recursive: true));

  /// Serves 100 bytes per image; `/missing` is a 404, `/fail` a network
  /// error that mentions the URL.
  PosterCache cache({int maxBytes = 1000}) => PosterCache(
    client: MockClient((request) async {
      requests.add(request.url.path);
      if (request.url.path == '/missing') return http.Response('', 404);
      if (request.url.path == '/fail') {
        throw http.ClientException('failed: ${request.url}', request.url);
      }
      return http.Response.bytes(List.filled(100, 1), 200);
    }),
    directory: () async => dir,
    maxBytes: maxBytes,
  );

  List<String> files() => [
    for (final f in dir.listSync()) f.uri.pathSegments.last,
  ];

  test('downloads once, then serves from disk, also after a restart', () async {
    final first = cache();
    expect(await first.load('$_host/p/1.jpg'), hasLength(100));
    expect(await first.load('$_host/p/1.jpg'), hasLength(100));
    expect(requests, ['/p/1.jpg']);

    final second = cache();
    expect(await second.load('$_host/p/1.jpg'), hasLength(100));
    expect(requests, ['/p/1.jpg']);
    expect(await second.totalBytes, 100);
  });

  test('file names never contain the address', () async {
    await cache().load('$_host/p/user/pass/1.jpg');
    final name = files().single;
    expect(name, isNot(contains('192')));
    expect(name, isNot(contains('pass')));
    expect(name, matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  test('concurrent loads of one image share a download', () async {
    final c = cache();
    await Future.wait([
      c.load('$_host/p/1.jpg'),
      c.load('$_host/p/1.jpg'),
      c.load('$_host/p/1.jpg'),
    ]);
    expect(requests, hasLength(1));
  });

  test('stays under its size limit by removing the least recently used '
      'files', () async {
    final c = cache(maxBytes: 500);
    for (var i = 0; i < 5; i++) {
      await c.load('$_host/p/$i.jpg');
      // Distinct use times.
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Using image 0 again makes image 1 the least recently used.
    await c.load('$_host/p/0.jpg');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.load('$_host/p/5.jpg');
    expect(await c.totalBytes, lessThanOrEqualTo(500));
    expect(files(), hasLength(lessThanOrEqualTo(5)));

    requests.clear();
    await c.load('$_host/p/0.jpg');
    await c.load('$_host/p/5.jpg');
    expect(requests, isEmpty, reason: 'recently used images are kept');
    await c.load('$_host/p/1.jpg');
    expect(requests, ['/p/1.jpg'], reason: 'the oldest was removed');
  });

  test('errors never contain the address', () async {
    final c = cache();
    await expectLater(
      c.load('$_host/missing'),
      throwsA(
        isA<PosterException>().having((e) => e.message, 'message', 'HTTP 404'),
      ),
    );
    await expectLater(
      c.load('$_host/fail'),
      throwsA(
        isA<PosterException>().having(
          (e) => e.toString(),
          'text',
          isNot(contains('192.0.2.1')),
        ),
      ),
    );
    await expectLater(
      c.load('file:///etc/passwd'),
      throwsA(isA<PosterException>()),
    );
    expect(files(), isEmpty);
  });
}
