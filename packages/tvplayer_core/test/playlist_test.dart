import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _now = DateTime.utc(2026, 10, 26, 12);

DateTime _ago(Duration d) => _now.subtract(d);

PlaylistStatus _status(
  Map<PlaylistPart, PartStatus> parts, {
  AutoRefresh mode = AutoRefresh.daily,
}) => PlaylistStatus(autoRefresh: mode, parts: parts);

const _all = {
  PlaylistPart.channels,
  PlaylistPart.movies,
  PlaylistPart.series,
  PlaylistPart.guide,
};

void main() {
  group('dueParts', () {
    List<PlaylistPart> due(
      AutoRefresh mode,
      Map<PlaylistPart, PartStatus> parts, {
      Set<PlaylistPart> available = _all,
      bool atStart = false,
      DateTime? freshSince,
    }) => dueParts(
      mode: mode,
      status: _status(parts, mode: mode),
      available: available,
      now: _now,
      atStart: atStart,
      freshSince: freshSince,
    );

    PartStatus updated(Duration ago) => PartStatus(updatedAt: _ago(ago));

    test('off never refreshes, not even at start or without data', () {
      expect(due(AutoRefresh.off, {}, atStart: true), isEmpty);
      expect(
        due(AutoRefresh.off, {
          PlaylistPart.movies: updated(const Duration(days: 30)),
        }),
        isEmpty,
      );
    });

    test('on app start refreshes everything at start only', () {
      final fresh = {
        for (final p in _all) p: updated(const Duration(minutes: 5)),
      };
      expect(
        due(AutoRefresh.onStart, fresh, atStart: true),
        PlaylistPart.values,
      );
      expect(due(AutoRefresh.onStart, {}), isEmpty);
    });

    test('timed modes refresh parts whose interval has passed', () {
      final parts = {
        PlaylistPart.channels: updated(const Duration(hours: 5)),
        PlaylistPart.movies: updated(const Duration(hours: 6)),
        PlaylistPart.series: updated(const Duration(hours: 23, minutes: 59)),
        PlaylistPart.guide: updated(const Duration(days: 1)),
      };
      expect(due(AutoRefresh.every6Hours, parts), [
        PlaylistPart.movies,
        PlaylistPart.series,
        PlaylistPart.guide,
      ]);
      expect(due(AutoRefresh.daily, parts), [PlaylistPart.guide]);
    });

    test('parts never downloaded and a clock that went back are due', () {
      expect(
        due(AutoRefresh.daily, {
          PlaylistPart.movies: PartStatus(
            updatedAt: _now.add(const Duration(days: 2)),
          ),
        }),
        PlaylistPart.values,
      );
    });

    test('only available parts are due (M3U: channels, maybe a guide)', () {
      expect(due(AutoRefresh.daily, {}, available: {PlaylistPart.channels}), [
        PlaylistPart.channels,
      ]);
      expect(
        due(
          AutoRefresh.onStart,
          {},
          available: {PlaylistPart.channels, PlaylistPart.guide},
          atStart: true,
        ),
        [PlaylistPart.channels, PlaylistPart.guide],
      );
      expect(due(AutoRefresh.daily, {}, available: {}), isEmpty);
    });

    test('a failure waits an hour before the next automatic try', () {
      PartStatus failed(Duration ago) => PartStatus(
        updatedAt: _ago(const Duration(days: 3)),
        failedAt: _ago(ago),
        error: 'x',
      );
      expect(
        due(
          AutoRefresh.daily,
          {PlaylistPart.movies: failed(const Duration(minutes: 59))},
          available: {PlaylistPart.movies},
        ),
        isEmpty,
      );
      expect(
        due(
          AutoRefresh.daily,
          {PlaylistPart.movies: failed(autoRetryAfter)},
          available: {PlaylistPart.movies},
        ),
        [PlaylistPart.movies],
      );
      // A failure "in the future" (clock went back) doesn't block.
      expect(
        due(
          AutoRefresh.daily,
          {PlaylistPart.movies: failed(const Duration(hours: -2))},
          available: {PlaylistPart.movies},
        ),
        [PlaylistPart.movies],
      );
    });

    test('parts downloaded while starting are left alone', () {
      final started = _ago(const Duration(minutes: 1));
      final parts = {
        PlaylistPart.channels: PartStatus(updatedAt: _now),
        PlaylistPart.movies: updated(const Duration(days: 2)),
      };
      final available = {PlaylistPart.channels, PlaylistPart.movies};
      expect(
        due(
          AutoRefresh.onStart,
          parts,
          available: available,
          atStart: true,
          freshSince: started,
        ),
        [PlaylistPart.movies],
      );
      expect(
        due(
          AutoRefresh.daily,
          parts,
          available: available,
          atStart: true,
          freshSince: started,
        ),
        [PlaylistPart.movies],
      );
    });
  });

  group('PlaylistStatus', () {
    test('records successes and failures, keeping the last success', () {
      var status = PlaylistStatus.empty;
      expect(status.autoRefresh, AutoRefresh.daily);
      status = status.withPart(
        PlaylistPart.movies,
        status
            .part(PlaylistPart.movies)
            .succeeded(_ago(const Duration(days: 1))),
      );
      status = status.withPart(
        PlaylistPart.movies,
        status.part(PlaylistPart.movies).failedWith(_now, 'Server problem'),
      );
      final movies = status.part(PlaylistPart.movies);
      expect(movies.updatedAt, _ago(const Duration(days: 1)));
      expect(movies.failed, isTrue);
      expect(movies.error, 'Server problem');

      final ok = movies.succeeded(_now);
      expect(ok.failed, isFalse);
      expect(ok.error, isNull);
      expect(ok.updatedAt, _now);
    });

    test('seeding only fills a part nothing is known about', () {
      final status = PlaylistStatus.empty
          .withPart(PlaylistPart.guide, PartStatus(updatedAt: _now))
          .seeded(PlaylistPart.guide, _ago(const Duration(days: 5)))
          .seeded(PlaylistPart.movies, _ago(const Duration(days: 5)));
      expect(status.part(PlaylistPart.guide).updatedAt, _now);
      expect(
        status.part(PlaylistPart.movies).updatedAt,
        _ago(const Duration(days: 5)),
      );
    });

    test('JSON round trip', () {
      final status = PlaylistStatus(
        autoRefresh: AutoRefresh.every6Hours,
        parts: {
          PlaylistPart.channels: PartStatus(updatedAt: _now),
          PlaylistPart.guide: PartStatus(
            updatedAt: _ago(const Duration(days: 1)),
            failedAt: _now,
            error: "The provider didn't respond in time.",
          ),
        },
      );
      final back = PlaylistStatus.fromJson(status.toJson());
      expect(back.autoRefresh, AutoRefresh.every6Hours);
      expect(back.part(PlaylistPart.channels).updatedAt, _now);
      expect(back.part(PlaylistPart.guide).failedAt, _now);
      expect(
        back.part(PlaylistPart.guide).error,
        "The provider didn't respond in time.",
      );
      expect(back.part(PlaylistPart.movies).updatedAt, isNull);
    });

    test('lenient: unknown parts and modes are ignored', () {
      final back = PlaylistStatus.fromJson({
        'autoRefresh': 'hourly',
        'parts': {
          'radio': {'updated': 1},
          'movies': {'updated': 'soon'},
          'series': {'updated': _now.millisecondsSinceEpoch},
        },
      });
      expect(back.autoRefresh, AutoRefresh.defaultMode);
      expect(
        back.parts.keys,
        unorderedEquals(['movies', 'series'].map(PlaylistPart.byName)),
      );
      expect(back.part(PlaylistPart.movies).updatedAt, isNull);
      expect(back.part(PlaylistPart.series).updatedAt, _now);
      expect(PlaylistStatus.fromJson('nonsense').parts, isEmpty);
    });

    test('file store saves and loads; a broken file reads as empty', () async {
      final dir = await Directory.systemTemp.createTemp('playlist_status');
      addTearDown(() => dir.delete(recursive: true));
      final store = JsonFilePlaylistStatusStore(
        File('${dir.path}/playlist/key.json'),
      );
      expect((await store.load()).parts, isEmpty);
      await store.save(
        PlaylistStatus.empty
            .withAutoRefresh(AutoRefresh.off)
            .withPart(PlaylistPart.channels, PartStatus(updatedAt: _now)),
      );
      final loaded = await store.load();
      expect(loaded.autoRefresh, AutoRefresh.off);
      expect(loaded.part(PlaylistPart.channels).updatedAt, _now);

      await store.file.writeAsString('{not json');
      expect((await store.load()).autoRefresh, AutoRefresh.defaultMode);
    });
  });

  test('checkNotEmptied rejects only an emptied list', () {
    checkNotEmptied(before: 0, after: 0);
    checkNotEmptied(before: 10, after: 3);
    checkNotEmptied(before: 0, after: 3);
    expect(
      () => checkNotEmptied(before: 10, after: 0),
      throwsA(isA<EmptyResultException>()),
    );
  });

  group('failure kinds', () {
    const config = ProviderConfig.xtream(
      host: 'http://example.com',
      username: 'user',
      password: 'pass',
    );

    Future<Object> xtreamError(MockClientHandler handler) async {
      final client = XtreamClient(config, httpClient: MockClient(handler));
      try {
        await client.getLiveStreams();
      } catch (e) {
        return e;
      }
      fail('no error');
    }

    test('Xtream', () async {
      final server = await xtreamError((_) async => http.Response('', 502));
      expect(
        server,
        isA<XtreamException>()
            .having((e) => e.kind, 'kind', ProviderFailure.server)
            .having((e) => e.statusCode, 'status', 502),
      );
      expect(
        (await xtreamError((_) async => http.Response('', 404))
                as XtreamException)
            .kind,
        ProviderFailure.refused,
      );
      expect(
        (await xtreamError((_) async => http.Response('', 401))
                as XtreamException)
            .kind,
        ProviderFailure.auth,
      );
      expect(
        (await xtreamError((_) async => http.Response('<html>', 200))
                as XtreamException)
            .kind,
        ProviderFailure.invalidData,
      );
      expect(
        (await xtreamError((_) async => throw http.ClientException('refused'))
                as XtreamException)
            .kind,
        ProviderFailure.network,
      );
    });

    test('M3U', () async {
      Future<ProviderFailure> kind(MockClientHandler handler) async {
        final client = M3uClient(
          'http://example.com/list.m3u',
          httpClient: MockClient(handler),
        );
        try {
          await client.fetch();
        } on M3uException catch (e) {
          return e.kind;
        }
        fail('no error');
      }

      expect(
        await kind((_) async => http.Response('', 503)),
        ProviderFailure.server,
      );
      expect(
        await kind((_) async => http.Response('', 403)),
        ProviderFailure.refused,
      );
      expect(
        await kind((_) async => http.Response('<html></html>', 200)),
        ProviderFailure.invalidData,
      );
      expect(
        await kind((_) async => throw http.ClientException('refused')),
        ProviderFailure.network,
      );
    });
  });

  group('missingItems', () {
    final live = LiveCatalog(
      categories: const [],
      channels: const [
        LiveStream(id: '1', name: 'One'),
        LiveStream(id: '2', name: 'Two'),
      ],
    );
    final movies = VodCatalog.movies(
      categories: const [],
      items: const [Movie(streamId: 10, name: 'Kept')],
      fetchedAt: _now,
    );
    final series = VodCatalog.series(
      categories: const [],
      items: const [Series(seriesId: 20, name: 'Kept series')],
      fetchedAt: _now,
    );

    FavouritesData favourites() {
      var data = FavouritesData.empty;
      for (final kind in ContentKind.values) {
        final (next, category) = createCategory(
          data,
          kind: kind,
          name: 'Mine ${kind.name}',
          icon: 'star',
          now: _now,
        );
        data = next;
        for (final (id, name) in switch (kind) {
          ContentKind.live => [('1', 'One'), ('9', 'Gone channel')],
          ContentKind.movie => [('10', 'Kept'), ('11', 'Gone movie')],
          ContentKind.series => [('21', 'Gone series')],
        }) {
          data = setMembership(
            data,
            category!.id,
            ItemRef(kind, id),
            name: name,
            member: true,
            now: _now,
          );
        }
      }
      return data;
    }

    WatchData watch() {
      var data = WatchData.empty.withItems({
        movieKey(10): WatchProgress(
          position: const Duration(minutes: 20),
          duration: const Duration(minutes: 90),
          updatedAt: _now,
        ),
        movieKey(11): WatchProgress(
          position: const Duration(minutes: 20),
          duration: const Duration(minutes: 90),
          updatedAt: _now,
        ),
      });
      data = recordChannel(data, '2', _ago(const Duration(hours: 2)));
      data = recordChannel(data, '7', _ago(const Duration(hours: 1)));
      return data;
    }

    test('lists what the catalogues no longer have', () {
      final missing = missingItems(
        favourites: favourites(),
        watch: watch(),
        live: live,
        movies: movies,
        series: series,
      );
      expect(missing.favourites.map((m) => m.name), [
        'Gone channel',
        'Gone movie',
        'Gone series',
      ]);
      expect(missing.continueWatching, 1);
      expect(missing.recentChannels, 1);
      expect(missing.isEmpty, isFalse);
    });

    test('catalogues not loaded (or not offered, as on M3U) count nothing', () {
      final missing = missingItems(
        favourites: favourites(),
        watch: watch(),
        live: live,
      );
      expect(missing.favourites.map((m) => m.name), ['Gone channel']);
      expect(missing.continueWatching, 0);
      expect(missing.recentChannels, 1);
      expect(
        missingItems(favourites: favourites(), watch: watch()).isEmpty,
        isTrue,
      );
    });
  });
}
