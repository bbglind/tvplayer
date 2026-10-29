import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _t0 = DateTime.utc(2026, 3, 1, 12);

/// The "server" clock of the tests, moved by hand.
var _serverNow = _t0;

void _advance(Duration d) => _serverNow = _serverNow.add(d);

const _config = ProviderConfig.xtream(
  host: 'http://example.com:8080',
  username: 'user',
  password: 'pass',
);

/// One device: its data, its clock ([skew] from the server's) and sync
/// state, and a [sync] against the shared [backend].
class _Device {
  _Device(this.backend);

  final MemorySyncBackend backend;
  Duration skew = Duration.zero;
  late final clock = SyncClock(device: () => _serverNow.add(skew));
  final states = MemorySyncStateStore();

  var watch = WatchData.empty;
  var favourites = FavouritesData.empty;
  var settings = <String, Object?>{'subtitlesOn': true, 'movieSort': 'recent'};
  var stamps = <String, int>{};
  var backups = 0;

  DateTime now() => clock.now();

  /// A setting changed by the user.
  void set(String name, Object? value) {
    settings = {...settings, name: value};
    stamps = {...stamps, name: now().millisecondsSinceEpoch};
  }

  List<SyncSpace> spaces(SyncInfo info) {
    final account = syncAccountId(info.salt, _config);
    Future<void> backup() async => backups++;
    return [
      SettingsSyncSpace(
        id: settingsSpace,
        values: () => settings,
        stamps: () => stamps,
        write: (values, times) {
          settings = {...settings, ...values};
          stamps = {...stamps, ...times};
        },
        clock: clock,
        backup: backup,
      ),
      WatchSyncSpace(
        id: watchSpace(account),
        read: () => watch,
        write: (d) => watch = d,
        clock: clock,
        backup: backup,
      ),
      FavouritesSyncSpace(
        id: favouritesSpace(account),
        read: () => favourites,
        write: (d) => favourites = d,
        clock: clock,
        backup: backup,
      ),
    ];
  }

  SyncEngine engine({int pageLimit = syncMaxRecords}) => SyncEngine(
    backend: backend,
    states: states,
    clock: clock,
    pageLimit: pageLimit,
  );

  Future<SyncReport> sync({int pageLimit = syncMaxRecords}) =>
      engine(pageLimit: pageLimit).run(spaces);
}

WatchData _progress(WatchData d, int movie, int minutes, DateTime now) =>
    d.withItems({
      movieKey(movie): updatedProgress(
        d.movie(movie),
        position: Duration(minutes: minutes),
        duration: const Duration(minutes: 100),
        now: now,
      ),
    });

/// Creates a category of [kind] named [name] on [d] with id [id].
FavouriteCategory _category(
  _Device d,
  String id,
  String name, {
  ContentKind kind = ContentKind.live,
}) {
  final (data, category) = createCategory(
    d.favourites,
    kind: kind,
    name: name,
    icon: 'star',
    now: d.now(),
    newId: () => id,
  );
  d.favourites = data;
  return category!;
}

void _add(_Device d, String category, String item, {String? name}) =>
    d.favourites = setMembership(
      d.favourites,
      category,
      ItemRef(ContentKind.live, item),
      name: name ?? 'Channel $item',
      member: true,
      now: d.now(),
    );

void main() {
  late MemorySyncBackend backend;
  late _Device laptop;
  late _Device phone;

  setUp(() {
    _serverNow = _t0;
    backend = MemorySyncBackend(salt: 'salt-1', clock: () => _serverNow);
    laptop = _Device(backend);
    phone = _Device(backend);
  });

  group('records', () {
    test('the hash ignores the order of map keys', () {
      final a = SyncRecord(
        key: 'k',
        t: 1,
        value: {
          'a': 1,
          'b': [2, 3],
        },
      );
      final b = SyncRecord(
        key: 'k',
        t: 1,
        value: {
          'b': [2, 3],
          'a': 1,
        },
      );
      expect(a.hash, b.hash);
      expect(a.compareTo(b), 0);
    });

    test('the later time wins; equal times are decided by content', () {
      final old = SyncRecord(key: 'k', t: 1, value: 'z');
      final late = SyncRecord(key: 'k', t: 2, value: 'a');
      expect(late.beats(old.version), isTrue);
      expect(old.beats(late.version), isFalse);
      final x = SyncRecord(key: 'k', t: 5, value: 'x');
      final y = SyncRecord(key: 'k', t: 5, value: 'y');
      // Exactly one of them wins, the same one everywhere.
      expect(x.beats(y.version), isNot(y.beats(x.version)));
    });

    test('a tombstone differs from a live record with the same value', () {
      final live = SyncRecord(key: 'k', t: 1, value: const {});
      final gone = SyncRecord(key: 'k', t: 1, value: const {}, deleted: true);
      expect(live.hash, isNot(gone.hash));
    });

    test('watch and favourites data round-trip through records', () {
      var w = _progress(WatchData.empty, 1, 30, _t0);
      w = recordChannel(w, 'ch1', _t0);
      w = forgetChannel(w, 'ch1', _t0.add(const Duration(minutes: 1)));
      w = removeContinueSeries(w, 7, _t0);
      expect(
        WatchData.empty.withSyncRecords(w.syncRecords.values).syncRecords,
        w.syncRecords,
      );
      _category(laptop, 'c1', 'News');
      _add(laptop, 'c1', '101');
      final f = laptop.favourites;
      expect(
        FavouritesData.empty.withSyncRecords(f.syncRecords.values).syncRecords,
        f.syncRecords,
      );
    });

    test('the TMDB id is kept with progress and favourites', () {
      final p = updatedProgress(
        null,
        position: const Duration(minutes: 1),
        duration: null,
        now: _t0,
        tmdbId: '603',
      );
      final again = updatedProgress(
        p,
        position: const Duration(minutes: 2),
        duration: null,
        now: _t0,
      );
      expect(WatchProgress.fromJson(again.toJson(), _t0).tmdbId, '603');
      _category(laptop, 'c1', 'Films', kind: ContentKind.movie);
      laptop.favourites = setMembership(
        laptop.favourites,
        'c1',
        const ItemRef(ContentKind.movie, '9'),
        name: 'A film',
        member: true,
        now: _t0,
        tmdbId: '603',
      );
      final restored = FavouritesData.fromJson(
        jsonDecode(jsonEncode(laptop.favourites.toJson())),
      )!;
      expect(restored.itemsIn('c1').single.tmdbId, '603');
    });
  });

  group('clock', () {
    test('never gives out the same time twice', () {
      final clock = SyncClock(device: () => _t0);
      final a = clock.now();
      final b = clock.now();
      expect(b.isAfter(a), isTrue);
    });

    test(
      'a device whose clock is behind still wins after seeing a change',
      () async {
        phone.skew = const Duration(minutes: -10);
        laptop.watch = _progress(laptop.watch, 1, 50, laptop.now());
        await laptop.sync();
        _advance(const Duration(seconds: 30));
        await phone.sync();
        expect(phone.watch.movie(1)!.position, const Duration(minutes: 50));
        phone.watch = _progress(phone.watch, 1, 20, phone.now());
        await phone.sync();
        await laptop.sync();
        expect(laptop.watch.movie(1)!.position, const Duration(minutes: 20));
      },
    );

    test('a change after an observed time is later, whatever the clock', () {
      // 10 minutes behind and never calibrated.
      final clock = SyncClock(
        device: () => _t0.subtract(const Duration(minutes: 10)),
      );
      final seen = _t0.subtract(const Duration(minutes: 1));
      clock.observe(seen.millisecondsSinceEpoch);
      expect(clock.now().isAfter(seen), isTrue);
    });

    test('the offset to the server corrects the device time', () async {
      phone.skew = const Duration(hours: -2);
      await phone.engine().connect();
      expect(
        phone.now().difference(_serverNow).inMinutes.abs(),
        lessThanOrEqualTo(1),
      );
    });

    test('times far ahead of the clock are not observed', () {
      final clock = SyncClock(device: () => _t0);
      clock.observe(_t0.add(const Duration(days: 1)).millisecondsSinceEpoch);
      expect(clock.now().difference(_t0), lessThan(const Duration(seconds: 1)));
    });

    test('records dated far ahead are redated before they are sent', () async {
      laptop.watch = _progress(
        laptop.watch,
        1,
        30,
        _t0.add(const Duration(days: 30)),
      );
      await laptop.sync();
      final sent = backend.records(
        watchSpace(syncAccountId('salt-1', _config)),
      )[movieKey(1)]!;
      expect(
        sent.t,
        lessThan(_t0.add(const Duration(minutes: 1)).millisecondsSinceEpoch),
      );
      expect(laptop.watch.movie(1)!.position, const Duration(minutes: 30));
    });

    test('the backend refuses records dated far ahead of its clock', () {
      final far = _t0.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      expect(
        backend.push('settings', [SyncRecord(key: 'k', t: far)]),
        throwsA(
          isA<SyncException>().having((e) => e.kind, 'kind', SyncFailure.clock),
        ),
      );
    });

    test('round-trips through JSON', () {
      final clock = SyncClock(
        device: () => _t0,
        offset: const Duration(seconds: 3),
        last: 42,
      );
      final copy = SyncClock.fromJson(clock.toJson(), device: () => _t0);
      expect(copy.offset, const Duration(seconds: 3));
      expect(copy.last, 42);
    });
  });

  group('engine', () {
    test('progress, favourites and settings reach the other device', () async {
      laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
      _category(laptop, 'c1', 'News');
      _add(laptop, 'c1', '101');
      await laptop.sync();
      laptop.set('movieSort', 'name');
      await laptop.sync();
      await phone.sync();
      expect(phone.watch.movie(1)!.position, const Duration(minutes: 30));
      expect(phone.favourites.itemsIn('c1').single.item.id, '101');
      expect(phone.settings['movieSort'], 'name');
    });

    test('a later change wins on both devices', () async {
      laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
      await laptop.sync();
      await phone.sync();
      _advance(const Duration(minutes: 1));
      laptop.watch = _progress(laptop.watch, 1, 40, laptop.now());
      _advance(const Duration(minutes: 1));
      phone.watch = _progress(phone.watch, 1, 10, phone.now());
      await laptop.sync();
      await phone.sync();
      await laptop.sync();
      expect(laptop.watch.movie(1)!.position, const Duration(minutes: 10));
      expect(phone.watch.movie(1)!.position, const Duration(minutes: 10));
    });

    test('deletions travel as tombstones', () async {
      _category(laptop, 'c1', 'News');
      _add(laptop, 'c1', '101');
      _add(laptop, 'c1', '102');
      laptop.watch = recordChannel(laptop.watch, '101', laptop.now());
      laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
      await laptop.sync();
      await phone.sync();
      _advance(const Duration(minutes: 1));
      laptop.favourites = setMembership(
        laptop.favourites,
        'c1',
        const ItemRef(ContentKind.live, '102'),
        name: 'Channel 102',
        member: false,
        now: laptop.now(),
      );
      laptop.watch = forgetChannel(laptop.watch, '101', laptop.now());
      laptop.watch = removeContinueMovie(laptop.watch, 1, laptop.now());
      await laptop.sync();
      await phone.sync();
      expect(phone.favourites.itemsIn('c1').map((m) => m.item.id), ['101']);
      expect(phone.watch.channels['101']!.forgotten, isTrue);
      expect(continueMovies(phone.watch), isEmpty);

      _advance(const Duration(minutes: 1));
      phone.favourites = deleteCategory(
        phone.favourites,
        'c1',
        now: phone.now(),
      );
      await phone.sync();
      await laptop.sync();
      expect(laptop.favourites.category('c1'), isNull);
      expect(
        laptop.favourites.isFavourite(const ItemRef(ContentKind.live, '101')),
        isFalse,
      );
    });

    test('order resets and hidden categories sync', () async {
      const cats = [
        Category(id: 'a', name: 'Alpha'),
        Category(id: 'b', name: 'Beta'),
      ];
      laptop.favourites = moveProviderCategory(
        laptop.favourites,
        ContentKind.live,
        cats,
        'b',
        toIndex: 0,
        now: laptop.now(),
      );
      laptop.favourites = setCategoriesHidden(
        laptop.favourites,
        ContentKind.live,
        {'a'},
        hidden: true,
        now: laptop.now(),
      );
      await laptop.sync();
      await phone.sync();
      expect(phone.favourites.categoryOrder(ContentKind.live)!.ids, ['b', 'a']);
      expect(phone.favourites.hiddenIds(ContentKind.live), {'a'});
      _advance(const Duration(minutes: 1));
      phone.favourites = resetCategoryOrder(
        phone.favourites,
        ContentKind.live,
        now: phone.now(),
      );
      await phone.sync();
      await laptop.sync();
      expect(laptop.favourites.categoryOrder(ContentKind.live), isNull);
    });

    test('a second sync only pulls what changed', () async {
      for (var i = 0; i < 20; i++) {
        laptop.watch = _progress(laptop.watch, i, 30, laptop.now());
      }
      await laptop.sync();
      final first = await phone.sync();
      expect(
        first.spaces.values.map((r) => r.pulled).reduce((a, b) => a + b),
        greaterThanOrEqualTo(20),
      );
      laptop.watch = _progress(laptop.watch, 3, 31, laptop.now());
      await laptop.sync();
      final second = await phone.sync();
      final watch =
          second.spaces[watchSpace(syncAccountId('salt-1', _config))]!;
      expect(watch.pulled, 1);
      expect(watch.applied, 1);
      expect(phone.watch.movie(3)!.position, const Duration(minutes: 31));
    });

    test('pulls page by page', () async {
      for (var i = 0; i < 35; i++) {
        laptop.watch = _progress(laptop.watch, i, 30, laptop.now());
      }
      await laptop.sync();
      await phone.sync(pageLimit: 10);
      expect(phone.watch.items, hasLength(35));
    });

    test('pushes split by size stay under the limit', () async {
      _category(laptop, 'c1', 'Lots');
      final long = 'x' * 300;
      for (var i = 0; i < 5000; i++) {
        _add(laptop, 'c1', '$i', name: '$long $i');
      }
      await laptop.sync();
      final space = favouritesSpace(syncAccountId('salt-1', _config));
      final pushes = [
        for (final (s, records) in backend.pushes)
          if (s == space) records,
      ];
      expect(pushes.length, greaterThan(1));
      for (final records in pushes) {
        final body = utf8.encode(
          jsonEncode({
            'records': [for (final r in records) r.toJson()],
          }),
        );
        expect(body.length, lessThanOrEqualTo(syncMaxPushBytes));
        expect(records.length, lessThanOrEqualTo(syncMaxRecords));
      }
      expect(backend.records(space), hasLength(5001));
      await phone.sync();
      expect(phone.favourites.countIn('c1'), 5000);
    });

    test('a newer copy on the server replaces the pushed one', () async {
      laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
      await laptop.sync();
      // Another device pushes a newer copy straight to the backend.
      final space = watchSpace(syncAccountId('salt-1', _config));
      final newer = _progress(
        WatchData.empty,
        1,
        77,
        _t0.add(const Duration(minutes: 5)),
      );
      _advance(const Duration(minutes: 5));
      await backend.push(space, newer.syncRecords.values.toList());
      // An older local change, from before this device saw it.
      laptop.watch = _progress(
        laptop.watch,
        1,
        40,
        _t0.add(const Duration(minutes: 1)),
      );
      await laptop.sync();
      expect(laptop.watch.movie(1)!.position, const Duration(minutes: 77));
    });

    test('changes made offline are sent on the next sync', () async {
      await laptop.sync();
      backend.failure = const SyncException(SyncFailure.network);
      laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
      _category(laptop, 'c1', 'News');
      await expectLater(laptop.sync(), throwsA(isA<SyncException>()));
      backend.failure = null;
      final report = await laptop.sync();
      expect(report.pushed, greaterThanOrEqualTo(2));
      await phone.sync();
      expect(phone.watch.movie(1), isNotNull);
      expect(phone.favourites.category('c1'), isNotNull);
    });

    test('a sync repeated from an older state changes nothing', () async {
      laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
      await laptop.sync();
      final before = {...laptop.states.states};
      laptop.watch = _progress(laptop.watch, 2, 30, laptop.now());
      await laptop.sync();
      // As if the state of the last sync had not been saved.
      laptop.states.states
        ..clear()
        ..addAll(before);
      final watch = laptop.watch;
      await laptop.sync();
      expect(laptop.watch.syncRecords, watch.syncRecords);
      await phone.sync();
      expect(phone.watch.syncRecords, laptop.watch.syncRecords);
    });

    test(
      'a server restored from an older backup gets everything back',
      () async {
        laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
        await laptop.sync();
        laptop.watch = _progress(laptop.watch, 2, 30, laptop.now());
        _category(laptop, 'c1', 'News');
        await laptop.sync();
        // Back to the state after the first sync.
        backend.restore(3);
        final space = watchSpace(syncAccountId('salt-1', _config));
        expect(backend.records(space).keys, isNot(contains(movieKey(2))));
        await laptop.sync();
        expect(backend.records(space).keys, contains(movieKey(2)));
        await phone.sync();
        expect(phone.watch.movie(2), isNotNull);
        expect(phone.favourites.category('c1'), isNotNull);
        // No backup or first-sync merge again.
        expect(laptop.backups, 3);
      },
    );

    test('keys trimmed locally are not sent back or deleted', () async {
      for (var i = 0; i < maxChannelHistory + 5; i++) {
        laptop.watch = recordChannel(laptop.watch, 'ch$i', laptop.now());
      }
      await laptop.sync();
      final report = await laptop.sync();
      expect(report.pushed, 0);
    });
  });

  group('first sync', () {
    test('backs up once per space before anything changes', () async {
      await laptop.sync();
      expect(laptop.backups, 3);
      await laptop.sync();
      expect(laptop.backups, 3);
    });

    test('keeps everything both devices had', () async {
      laptop.watch = _progress(laptop.watch, 1, 30, laptop.now());
      _category(laptop, 'L', 'Sport');
      _add(laptop, 'L', '101');
      await laptop.sync();
      phone.watch = _progress(phone.watch, 2, 30, phone.now());
      _category(phone, 'P', 'Films', kind: ContentKind.movie);
      await phone.sync();
      await laptop.sync();
      for (final d in [laptop, phone]) {
        expect(d.watch.items.keys, containsAll([movieKey(1), movieKey(2)]));
        expect(d.favourites.category('L'), isNotNull);
        expect(d.favourites.category('P'), isNotNull);
      }
    });

    test('a watched mark on either device survives', () async {
      laptop.watch = markWatched(
        laptop.watch,
        [movieTarget(1)],
        watched: true,
        now: laptop.now(),
      );
      await laptop.sync();
      _advance(const Duration(minutes: 1));
      // Newer on the phone, but not watched there.
      phone.watch = _progress(phone.watch, 1, 5, phone.now());
      await phone.sync();
      await laptop.sync();
      for (final d in [laptop, phone]) {
        expect(d.watch.movie(1)!.watched, isTrue);
        expect(d.watch.movie(1)!.position, const Duration(minutes: 5));
      }
    });

    test('categories with the same kind and name are combined', () async {
      _category(laptop, 'L', 'Favourites');
      _add(laptop, 'L', '101');
      _add(laptop, 'L', '102');
      await laptop.sync();
      _category(phone, 'P', ' favourites ');
      _add(phone, 'P', '102');
      _add(phone, 'P', '103');
      // Same name, other kind: stays apart.
      _category(phone, 'M', 'Favourites', kind: ContentKind.movie);
      await phone.sync();
      await laptop.sync();
      for (final d in [laptop, phone]) {
        expect(d.favourites.category('P'), isNull);
        expect(d.favourites.category('M'), isNotNull);
        expect(d.favourites.itemsIn('L').map((m) => m.item.id), [
          '102',
          '101',
          '103',
        ]);
      }
    });

    test('the first device sets the settings; later ones take them', () async {
      laptop.set('movieSort', 'name');
      await laptop.sync();
      // The phone changed its own setting later, before sync was on.
      _advance(const Duration(minutes: 5));
      phone.set('movieSort', 'year');
      phone.set('subtitlesOn', false);
      await phone.sync();
      expect(phone.settings, {'subtitlesOn': true, 'movieSort': 'name'});
      // After the first sync, changes win as usual.
      _advance(const Duration(minutes: 1));
      phone.set('subtitlesOn', false);
      await phone.sync();
      await laptop.sync();
      expect(laptop.settings['subtitlesOn'], false);
    });

    test('settings this version does not know are ignored', () async {
      await backend.push(settingsSpace, [
        SyncRecord(key: 'setting:future', t: 1, value: 1),
      ]);
      await laptop.sync();
      expect(laptop.settings.containsKey('future'), isFalse);
    });
  });

  group('account id', () {
    test('is stable, salted and hides the login', () {
      final id = syncAccountId('salt-1', _config);
      expect(id, hasLength(32));
      expect(id, syncAccountId('salt-1', _config));
      expect(id, isNot(syncAccountId('salt-2', _config)));
      expect(id, isNot(contains('example')));
      expect(id, isNot(contains('user')));
      expect(id, isNot(providerKey(_config)));
      const newPassword = ProviderConfig.xtream(
        host: 'http://EXAMPLE.com:8080',
        username: 'user',
        password: 'other',
      );
      expect(syncAccountId('salt-1', newPassword), id);
      expect(isSyncSpace(watchSpace(id)), isTrue);
      expect(isSyncSpace(favouritesSpace(id)), isTrue);
    });
  });

  group('state', () {
    test('round-trips through a file', () async {
      final dir = await Directory.systemTemp.createTemp('sync_state');
      addTearDown(() => dir.delete(recursive: true));
      final store = JsonFileSyncStateStore(Directory('${dir.path}/sync'));
      expect(await store.load('settings'), isNull);
      await store.save(
        'settings',
        const SyncState(
          cursor: '12',
          shadow: {'a': SyncVersion(5, 'abc')},
          complete: true,
        ),
      );
      final back = (await store.load('settings'))!;
      expect(back.cursor, '12');
      expect(back.complete, isTrue);
      expect(back.shadow, {'a': const SyncVersion(5, 'abc')});
      await store.clear();
      expect(await store.load('settings'), isNull);
    });
  });

  group('server address', () {
    test('takes http and https, adds http to a bare host', () {
      expect(
        parseSyncServerAddress('192.0.2.10:8787').toString(),
        'http://192.0.2.10:8787',
      );
      expect(
        parseSyncServerAddress(' https://sync.example.com/ ').toString(),
        'https://sync.example.com',
      );
      expect(
        parseSyncServerAddress('https://example.com/sync').toString(),
        'https://example.com/sync',
      );
      expect(parseSyncServerAddress('ftp://example.com'), isNull);
      expect(parseSyncServerAddress('http://user:pass@example.com'), isNull);
      expect(parseSyncServerAddress(''), isNull);
    });
  });

  group('HTTP backend', () {
    const token = 'tvps_secret';

    HttpSyncBackend backendFor(MockClientHandler handler) => HttpSyncBackend(
      server: parseSyncServerAddress('https://sync.example.com/base')!,
      token: token,
      client: MockClient(handler),
    );

    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    Future<SyncFailure> failure(Future<void> Function() f) async {
      try {
        await f();
      } on SyncException catch (e) {
        expect(e.toString(), isNot(contains(token)));
        expect(e.toString(), isNot(contains('example')));
        return e.kind;
      }
      fail('no exception');
    }

    test('sends the token and reads info, pages and pushes', () async {
      final requests = <http.Request>[];
      final b = backendFor((r) async {
        requests.add(r);
        return switch (r.url.path) {
          '/base/v1/info' => json({
            'service': syncServiceName,
            'api': 1,
            'salt': 's',
            'serverTime': 5,
          }),
          '/base/v1/spaces/settings/changes' => json({
            'service': syncServiceName,
            'records': [
              {'k': 'a', 't': 1, 'v': 2},
            ],
            'cursor': '9',
            'more': false,
            'serverTime': 6,
          }),
          _ => json({'service': syncServiceName, 'stale': [], 'serverTime': 7}),
        };
      });
      expect((await b.info()).salt, 's');
      final page = await b.pull('settings', '3', limit: 10);
      expect(page.records.single.key, 'a');
      expect(page.cursor, '9');
      await b.push('settings', [SyncRecord(key: 'a', t: 1)]);
      expect(requests[1].url.queryParameters, {'since': '3', 'limit': '10'});
      expect(jsonDecode(requests[2].body), {
        'records': [
          {'k': 'a', 't': 1, 'v': null},
        ],
      });
      for (final r in requests) {
        expect(r.headers['Authorization'], 'Bearer $token');
      }
    });

    test('maps failures to kinds without the address or token', () async {
      expect(
        await failure(
          () => backendFor(
            (_) async => json({'service': syncServiceName}, 401),
          ).info(),
        ),
        SyncFailure.auth,
      );
      expect(
        await failure(
          () => backendFor((_) async => http.Response('<html>', 404)).info(),
        ),
        SyncFailure.notSyncServer,
      );
      expect(
        await failure(() => backendFor((_) async => json({'hello': 1})).info()),
        SyncFailure.notSyncServer,
      );
      expect(
        await failure(
          () => backendFor((_) async => http.Response('', 502)).info(),
        ),
        SyncFailure.server,
      );
      expect(
        await failure(
          () => backendFor(
            (_) async =>
                json({'service': syncServiceName, 'error': 'clock'}, 422),
          ).push('settings', const []),
        ),
        SyncFailure.clock,
      );
      expect(
        await failure(
          () => backendFor(
            (_) async => throw const SocketException('no route'),
          ).info(),
        ),
        SyncFailure.network,
      );
      expect(
        await failure(
          () => backendFor(
            (_) async => throw http.ClientException('failed'),
          ).info(),
        ),
        SyncFailure.network,
      );
    });
  });
}
