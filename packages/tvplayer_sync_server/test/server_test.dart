import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';
import 'package:tvplayer_sync_server/tvplayer_sync_server.dart';

final _t0 = DateTime.utc(2026, 3, 1, 12);

void main() {
  late SyncStore store;
  late Handler api;
  late String token;
  late List<String> log;
  var now = _t0;

  setUp(() {
    now = _t0;
    store = SyncStore.inMemory();
    token = store.createToken('laptop');
    log = [];
    api = syncApi(store, clock: () => now, log: log.add);
  });

  tearDown(() => store.close());

  Future<(int, Map<String, Object?>)> call(
    String method,
    String path, {
    Object? body,
    String? auth,
    Map<String, String> headers = const {},
  }) async {
    final response = await api(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : (body is String ? body : jsonEncode(body)),
        headers: {'authorization': 'Bearer ${auth ?? token}', ...headers},
      ),
    );
    final text = await response.readAsString();
    return (response.statusCode, jsonDecode(text) as Map<String, Object?>);
  }

  Map<String, Object?> record(String key, int t, [Object? value]) =>
      SyncRecord(key: key, t: t, value: value).toJson();

  final t1 = _t0.millisecondsSinceEpoch;

  group('auth', () {
    test('health needs no token and says what it is', () async {
      final (status, body) = await call('GET', '/v1/health', auth: '');
      expect(status, 200);
      expect(body['service'], syncServiceName);
    });

    test('everything else needs a valid token', () async {
      expect((await call('GET', '/v1/info', auth: '')).$1, 401);
      expect((await call('GET', '/v1/info', auth: 'tvps_wrong')).$1, 401);
      final (status, body) = await call('GET', '/v1/info');
      expect(status, 200);
      expect(body['salt'], store.salt);
      expect(body['serverTime'], t1);
    });

    test('a revoked token is refused', () async {
      expect(store.revokeToken('laptop'), isTrue);
      expect((await call('GET', '/v1/info')).$1, 401);
      expect(store.revokeToken('laptop'), isFalse);
    });

    test('tokens are listed by name, stored only as hashes', () {
      final phone = store.createToken('phone');
      expect(phone, startsWith('tvps_'));
      expect(phone.length, greaterThan(40));
      expect(store.tokens().map((t) => t.name), ['laptop', 'phone']);
      expect(() => store.createToken('phone'), throwsArgumentError);
      expect(store.authenticate(phone), 'phone');
    });

    test('the log has no token, space or value', () async {
      await call(
        'POST',
        '/v1/spaces/watch-0123/records',
        body: {
          'records': [
            record('movie:1', t1, {'name': 'Secret title'}),
          ],
        },
      );
      await call('GET', '/v1/spaces/watch-0123/changes?since=0');
      expect(log, hasLength(2));
      for (final line in log) {
        expect(line, isNot(contains(token)));
        expect(line, isNot(contains('Secret')));
        expect(line, isNot(contains('0123')));
      }
      expect(
        log.first,
        startsWith('POST /spaces/:space/records 200 · 1 records'),
      );
    });
  });

  group('records', () {
    test('newest wins; older pushes get the stored copy back', () async {
      await call(
        'POST',
        '/v1/spaces/settings/records',
        body: {
          'records': [record('a', t1, 1)],
        },
      );
      final (status, body) = await call(
        'POST',
        '/v1/spaces/settings/records',
        body: {
          'records': [record('a', t1 - 1000, 2), record('b', t1, 3)],
        },
      );
      expect(status, 200);
      expect(body['stale'], [record('a', t1, 1)]);
      final (_, changes) = await call(
        'GET',
        '/v1/spaces/settings/changes?since=0',
      );
      expect(changes['records'], [record('a', t1, 1), record('b', t1, 3)]);
    });

    test('changes since a cursor, in pages, oldest first', () async {
      await call(
        'POST',
        '/v1/spaces/settings/records',
        body: {
          'records': [for (var i = 0; i < 5; i++) record('k$i', t1, i)],
        },
      );
      final (_, page1) = await call(
        'GET',
        '/v1/spaces/settings/changes?since=0&limit=3',
      );
      expect((page1['records'] as List).length, 3);
      expect(page1['more'], isTrue);
      final (_, page2) = await call(
        'GET',
        '/v1/spaces/settings/changes?since=${page1['cursor']}&limit=3',
      );
      expect((page2['records'] as List).map((r) => (r as Map)['k']), [
        'k3',
        'k4',
      ]);
      expect(page2['more'], isFalse);
      // A changed record comes again, after the others.
      await call(
        'POST',
        '/v1/spaces/settings/records',
        body: {
          'records': [record('k0', t1 + 1, 'new')],
        },
      );
      final (_, page3) = await call(
        'GET',
        '/v1/spaces/settings/changes?since=${page2['cursor']}',
      );
      expect(page3['records'], [record('k0', t1 + 1, 'new')]);
    });

    test('spaces are kept apart', () async {
      await call(
        'POST',
        '/v1/spaces/watch-a/records',
        body: {
          'records': [record('x', t1, 1)],
        },
      );
      final (_, other) = await call('GET', '/v1/spaces/watch-b/changes');
      expect(other['records'], isEmpty);
      expect(store.counts(), {'watch-a': 1});
    });

    test('tombstones are stored and returned', () async {
      final gone = SyncRecord(key: 'category:1', t: t1, deleted: true);
      await call(
        'POST',
        '/v1/spaces/favourites-a/records',
        body: {
          'records': [gone.toJson()],
        },
      );
      final (_, page) = await call('GET', '/v1/spaces/favourites-a/changes');
      expect(page['records'], [gone.toJson()]);
    });

    test('records dated far ahead of the clock are refused', () async {
      final far = t1 + const Duration(minutes: 11).inMilliseconds;
      final (status, body) = await call(
        'POST',
        '/v1/spaces/settings/records',
        body: {
          'records': [record('a', far, 1)],
        },
      );
      expect(status, 422);
      expect(body['error'], 'clock');
      expect(store.counts(), isEmpty);
    });
  });

  group('limits', () {
    test('bad space names and bodies are refused', () async {
      expect((await call('GET', '/v1/spaces/Bad_Space/changes')).$1, 400);
      expect(
        (await call('POST', '/v1/spaces/settings/records', body: '{nope')).$1,
        400,
      );
      expect(
        (await call(
          'POST',
          '/v1/spaces/settings/records',
          body: {
            'records': [
              {'k': 'a'},
            ],
          },
        )).$1,
        400,
      );
      expect((await call('GET', '/v1/nothing')).$1, 404);
      expect((await call('DELETE', '/v1/info')).$1, 405);
    });

    test('a body over 1 MB is refused with 413', () async {
      final big = 'x' * (syncMaxRequestBytes + 1);
      final (status, _) = await call(
        'POST',
        '/v1/spaces/settings/records',
        body: {
          'records': [record('a', t1, big)],
        },
      );
      expect(status, 413);
    });

    test('more than the most records per push is refused', () async {
      final (status, _) = await call(
        'POST',
        '/v1/spaces/settings/records',
        body: {
          'records': [
            for (var i = 0; i <= syncMaxRecords; i++) record('k$i', t1),
          ],
        },
      );
      expect(status, 413);
    });

    test('a page of changes stays near 512 KB', () async {
      final value = 'y' * 2000;
      for (var batch = 0; batch < 4; batch++) {
        await call(
          'POST',
          '/v1/spaces/settings/records',
          body: {
            'records': [
              for (var i = 0; i < 100; i++) record('k$batch-$i', t1, value),
            ],
          },
        );
      }
      final response = await api(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/spaces/settings/changes?limit=500'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      final bytes = await response.read().fold<int>(0, (n, c) => n + c.length);
      expect(bytes, lessThan(syncMaxPageBytes + 4096));
      final body = jsonDecode(
        await (await api(
          Request(
            'GET',
            Uri.parse('http://localhost/v1/spaces/settings/changes?limit=500'),
            headers: {'authorization': 'Bearer $token'},
          ),
        )).readAsString(),
      );
      expect(body['more'], isTrue);
    });
  });

  group('database', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('sync'));
    tearDown(() => dir.delete(recursive: true));

    test('keeps records, salt and tokens across restarts', () {
      final path = '${dir.path}/sync.sqlite';
      final first = SyncStore.open(path);
      final salt = first.salt;
      final t = first.createToken('pixel');
      first.push('settings', [SyncRecord(key: 'a', t: 1, value: 1)]);
      first.close();
      final again = SyncStore.open(path);
      expect(again.salt, salt);
      expect(again.authenticate(t), 'pixel');
      expect(again.changes('settings', 0).records.single.value, 1);
      again.close();
    });

    test('backup writes a copy that opens', () {
      final path = '${dir.path}/sync.sqlite';
      final live = SyncStore.open(path);
      live.push('settings', [SyncRecord(key: 'a', t: 1, value: 1)]);
      final copy = '${dir.path}/backup.sqlite';
      live.backup(copy);
      expect(() => live.backup(copy), throwsArgumentError);
      live.close();
      final restored = SyncStore.open(copy);
      expect(restored.counts(), {'settings': 1});
      restored.close();
    });

    test('a database from a newer server is refused', () {
      final path = '${dir.path}/sync.sqlite';
      SyncStore.open(path).close();
      sqlite3.open(path)
        ..userVersion = 99
        ..close();
      expect(() => SyncStore.open(path), throwsStateError);
    });

    test('the config file is checked', () {
      final file = File('${dir.path}/config.json');
      file.writeAsStringSync(
        jsonEncode({'host': '127.0.0.1', 'port': 9999, 'dataDir': dir.path}),
      );
      final config = ServerConfig.load(file.path);
      expect(config.port, 9999);
      expect(config.databasePath, '${dir.path}/sync.sqlite');
      file.writeAsStringSync(jsonEncode({'port': 'x'}));
      expect(() => ServerConfig.load(file.path), throwsFormatException);
      expect(
        () => ServerConfig.load('${dir.path}/missing.json'),
        throwsFormatException,
      );
    });
  });

  test('the app engine syncs two devices through a real server', () async {
    final server = await shelf_io.serve(syncApi(store), '127.0.0.1', 0);
    addTearDown(() => server.close(force: true));
    final address = 'http://127.0.0.1:${server.port}';
    final phoneToken = store.createToken('phone');
    const config = ProviderConfig.m3u(
      playlistUrl: 'http://example.com/list.m3u',
    );

    Future<WatchData> device(String token, WatchData data) async {
      var watch = data;
      final backend = HttpSyncBackend(
        server: parseSyncServerAddress(address)!,
        token: token,
      );
      addTearDown(backend.close);
      final clock = SyncClock();
      await SyncEngine(
        backend: backend,
        states: MemorySyncStateStore(),
        clock: clock,
      ).run(
        (info) => [
          WatchSyncSpace(
            id: watchSpace(syncAccountId(info.salt, config)),
            read: () => watch,
            write: (d) => watch = d,
            clock: clock,
          ),
        ],
      );
      return watch;
    }

    final laptop = WatchData.empty.withItems({
      movieKey(1): updatedProgress(
        null,
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 90),
        now: DateTime.now().toUtc(),
      ),
    });
    await device(token, laptop);
    final phone = await device(phoneToken, WatchData.empty);
    expect(phone.movie(1)!.position, const Duration(minutes: 12));
  });
}
