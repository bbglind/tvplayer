import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

void main() {
  group('SkipSegments', () {
    test('fills the missing types from another source', () {
      final skipDb = SkipSegments(intro: SkipRange(s(10), s(70)));
      final introDb = SkipSegments(
        intro: SkipRange(s(0), s(60)),
        recap: SkipRange(s(0), s(10)),
        credits: SkipRange(s(2500)),
      );
      final merged = skipDb.fillFrom(introDb);
      expect(merged.intro, SkipRange(s(10), s(70)));
      expect(merged.recap, SkipRange(s(0), s(10)));
      expect(merged.credits, SkipRange(s(2500)));
      expect(skipDb.missing, {SkipType.recap, SkipType.credits});
    });

    test('drops times that make no sense for the length', () {
      final d = s(2700);
      SkipSegments clean(SkipSegments x) => x.sanitized(d);
      // Too short, too long, past the end.
      expect(clean(SkipSegments(intro: SkipRange(s(10), s(14)))).intro, isNull);
      expect(clean(SkipSegments(intro: SkipRange(s(0), s(181)))).intro, isNull);
      expect(
        clean(SkipSegments(recap: SkipRange(s(0), s(480)))).recap,
        SkipRange(s(0), s(480)),
      );
      expect(clean(SkipSegments(recap: SkipRange(s(0), s(481)))).recap, isNull);
      expect(
        clean(SkipSegments(intro: SkipRange(s(2700), s(2760)))).intro,
        isNull,
      );
      // Intro/recap need an end; credits run to the end.
      expect(clean(SkipSegments(intro: SkipRange(s(0)))).intro, isNull);
      expect(
        clean(SkipSegments(credits: SkipRange(s(2600), s(2800)))).credits,
        SkipRange(s(2600)),
      );
      // Credits in the first half are taken as wrong.
      expect(
        clean(SkipSegments(credits: SkipRange(s(1300), s(1400)))).credits,
        isNull,
      );
      expect(
        clean(SkipSegments(credits: SkipRange(s(1350)))).credits,
        SkipRange(s(1350)),
      );
      expect(clean(SkipSegments(credits: SkipRange(s(2697)))).credits, isNull);
    });

    test('round-trips through JSON', () {
      final x = SkipSegments(
        intro: SkipRange(s(1), s(61)),
        credits: SkipRange(s(2500)),
        reference: s(2640),
      );
      expect(SkipSegments.fromJson(jsonDecode(jsonEncode(x.toJson()))), x);
    });

    group('fittedTo', () {
      final times = SkipSegments(
        recap: SkipRange(s(0), s(60)),
        intro: SkipRange(s(100), s(160)),
        credits: SkipRange(s(2560), s(2640)),
        reference: s(2640),
      );

      test('close lengths: unchanged, without the reference', () {
        final f = times.fittedTo(s(2652));
        expect(f.intro, times.intro);
        expect(f.credits, times.credits);
        expect(f.reference, isNull);
        expect(times.fittedTo(s(2000), from: s(2010)).credits, times.credits);
        expect(
          SkipSegments(intro: times.intro).fittedTo(s(2000)).intro,
          times.intro,
        );
      });

      test('a sped-up (PAL) copy: every time scaled', () {
        // 2640 s at 25 fps instead of 23.976: 2532 s.
        final f = times.fittedTo(s(2532));
        const r = 2532 / 2640;
        expect(f.recap, SkipRange(s(0), s(60) * r));
        expect(f.intro, SkipRange(s(100) * r, s(160) * r));
        expect(f.credits, SkipRange(s(2560) * r, s(2532)));
      });

      test('other lengths: credits keep their distance from the end', () {
        final f = times.fittedTo(s(2580));
        expect(f.intro, times.intro);
        expect(f.recap, times.recap);
        expect(f.credits, SkipRange(s(2500), s(2580)));
        final longer = times.fittedTo(s(2700));
        expect(longer.credits, SkipRange(s(2620), s(2700)));
        expect(
          SkipSegments(
            credits: SkipRange(s(2500)),
          ).fittedTo(s(2400), from: s(2600)).credits,
          SkipRange(s(2300)),
        );
      });
    });
  });

  group('SkipTracker', () {
    final intro = SkipSegments(intro: SkipRange(s(60), s(150)));

    test('stands out for 10 s of playback from the start, then not', () {
      final t = SkipTracker()..setSegments(intro);
      expect(t.update(s(58)), isNull);
      expect(t.update(s(59.5)), isNull);
      final p = t.update(s(60.2));
      expect(p, SkipPrompt(SkipType.intro, s(150), prominent: true));
      for (var p = 61.0; p <= 70; p += 0.5) {
        expect(t.update(s(p))!.prominent, isTrue);
      }
      expect(t.update(s(70.3))!.prominent, isFalse);
      for (var p = 71.0; p < 149; p += 2) {
        expect(t.update(s(p))!.prominent, isFalse);
      }
      expect(t.update(s(148.9))!.prominent, isFalse);
      expect(t.update(s(149.1)), isNull);
    });

    test('a part at the very start stands out', () {
      final t = SkipTracker()
        ..setSegments(SkipSegments(recap: SkipRange(s(0), s(40))));
      expect(t.update(s(0.1))!.prominent, isTrue);
      expect(t.update(s(0.1))!.type, SkipType.recap);
    });

    test('seeking or resuming into the middle shows it with the controls', () {
      final seek = SkipTracker()..setSegments(intro);
      seek.update(s(10));
      expect(seek.update(s(100))!.prominent, isFalse);

      final resume = SkipTracker()..setSegments(intro);
      expect(resume.update(s(90))!.prominent, isFalse);
    });

    test('stands out once per part', () {
      final t = SkipTracker()..setSegments(intro);
      t.update(s(59));
      expect(t.update(s(61))!.prominent, isTrue);
      t.update(s(30)); // seek back
      t.update(s(59));
      expect(t.update(s(61))!.prominent, isFalse);
    });

    test('times arriving late stand out if enough of the part is left', () {
      final t = SkipTracker();
      t.update(s(50));
      t.update(s(52));
      t.update(s(54));
      for (var p = 56; p <= 100; p += 2) {
        t.update(s(p));
      }
      t.setSegments(intro);
      expect(t.update(s(101))!.prominent, isTrue);

      final short = SkipTracker();
      for (var p = 50; p <= 146; p += 2) {
        short.update(s(p));
      }
      short.setSegments(intro);
      expect(short.update(s(147))!.prominent, isFalse);

      // Resumed in the middle: not prominent either.
      final resumed = SkipTracker();
      resumed.update(s(100));
      resumed.update(s(101));
      resumed.setSegments(intro);
      expect(resumed.update(s(102))!.prominent, isFalse);
    });
  });

  group('creditsCountdown', () {
    int? at(num position, {num credits = 2600, num? duration = 2700}) =>
        creditsCountdown(
          position: s(position),
          duration: duration == null ? null : s(duration),
          creditsStart: s(credits),
        );

    test('counts 10 s of playback from the credits start', () {
      expect(at(2599.9), isNull);
      expect(at(2600), 10);
      expect(at(2605.5), 5);
      expect(at(2610), 0);
      expect(at(2650), 0);
      expect(at(2600, duration: null), isNull);
    });

    test('never past the end', () {
      expect(at(2695, credits: 2694), 5);
    });

    test('counts from a later point when given', () {
      expect(
        creditsCountdown(
          position: s(2640),
          duration: s(2700),
          creditsStart: s(2600),
          countFrom: s(2636),
        ),
        6,
      );
    });
  });

  group('CreditsCountdown', () {
    test('played into the credits: from their start', () {
      final c = CreditsCountdown(s(2600));
      expect(c.update(s(2598), s(2700)), isNull);
      expect(c.update(s(2599.5), s(2700)), isNull);
      expect(c.update(s(2600.5), s(2700)), 10);
      expect(c.update(s(2603), s(2700)), 7);
      expect(c.update(s(2605), s(2700)), 5);
      expect(c.update(s(2608), s(2700)), 2);
      expect(c.update(s(2610), s(2700)), 0);
    });

    test('a seek into or within the credits: from where it landed', () {
      final c = CreditsCountdown(s(2600));
      expect(c.update(s(100), s(2700)), isNull);
      expect(c.update(s(2640), s(2700)), 10);
      expect(c.update(s(2642.5), s(2700)), 8);
      expect(c.update(s(2645), s(2700)), 5);
      // Further on while counting: a full countdown again.
      expect(c.update(s(2660), s(2700)), 10);
      // Back before the credits and played in: from their start.
      expect(c.update(s(2590), s(2700)), isNull);
      expect(c.update(s(2599), s(2700)), isNull);
      expect(c.update(s(2601), s(2700)), 9);
    });

    test('starting, or times arriving, in the credits: full countdown', () {
      expect(CreditsCountdown(s(2600)).update(s(2650), s(2700)), 10);
      expect(CreditsCountdown(s(2600)).update(s(2695), s(2700)), 5);
      expect(CreditsCountdown(s(2600)).update(s(2650), null), isNull);
    });
  });

  group('SkipDbClient', () {
    test('asks by IMDb id with the length and reads the segments', () async {
      late Uri asked;
      final client = SkipDbClient(
        MockClient((request) async {
          asked = request.url;
          return http.Response(
            jsonEncode({
              'segments': {
                'intro': {
                  'start_ms': 61000,
                  'end_ms': 121000,
                  'match': 'shifted',
                  'confidence': 0.9,
                },
                'recap': null,
                'outro': {
                  'start_ms': 2500000,
                  'end_ms': 2580000,
                  'match': 'exact',
                  'confidence': 0.8,
                },
                'preview': null,
              },
            }),
            200,
          );
        }),
        limiter: RateLimiter(perSecond: 1000),
        sleep: (_) async {},
      );
      final segments = await client.lookup(
        SkipQuery(
          imdbId: 'tt0000001',
          season: 2,
          episode: 3,
          duration: s(2600.25),
        ),
      );
      expect(asked.host, 'api.skipdb.tv');
      expect(asked.path, '/api/segments');
      expect(asked.queryParameters, {
        'imdb_id': 'tt0000001',
        'season': '2',
        'episode': '3',
        'duration': '2600.3',
        'adjust': 'conservative',
      });
      expect(segments.intro, SkipRange(s(61), s(121)));
      expect(segments.recap, isNull);
      expect(segments.credits, SkipRange(s(2500), s(2580)));
    });

    test('leaves out weak and unusable times', () {
      final parsed = SkipDbClient.parse({
        'segments': {
          'intro': {'start_ms': 0, 'end_ms': 50000, 'confidence': 0.2},
          'outro': {
            'start_ms': 1,
            'end_ms': 2,
            'match': 'out-of-range',
            'confidence': 1,
          },
          'recap': {'start_ms': 0, 'end_ms': 0},
        },
      }, s(2600));
      expect(parsed.isEmpty, isTrue);
      expect(parsed.incomplete, isTrue);
      final none = SkipDbClient.parse({
        'segments': {'intro': null, 'outro': null},
      }, s(2600));
      expect(none.isEmpty, isTrue);
      expect(none.incomplete, isFalse);
    });

    test('times for another length (out-of-range) are fitted', () {
      Map<String, Object?> seg(int start, int end) => {
        'start_ms': start,
        'end_ms': end,
        'match': 'out-of-range',
        'confidence': 0.6,
        'offset_ms': -60000,
      };
      final parsed = SkipDbClient.parse({
        'segments': {
          'intro': seg(100000, 160000),
          'outro': seg(2560000, 2640000),
        },
      }, s(2580));
      // Its copy: 2580 + 60 = 2640 s; not sped up, so the credits keep
      // their distance from the end and the intro stays.
      expect(parsed.reference, s(2640));
      expect(parsed.intro, SkipRange(s(100), s(160)));
      expect(parsed.credits, SkipRange(s(2500), s(2580)));
      expect(parsed.incomplete, isFalse);
      // No offset: unusable.
      final noOffset = SkipDbClient.parse({
        'segments': {
          'intro': {...seg(100000, 160000)}..remove('offset_ms'),
        },
      }, s(2580));
      expect(noOffset.intro, isNull);
      expect(noOffset.incomplete, isTrue);
    });

    test('no IMDb id, 404: nothing; never the address in errors', () async {
      var calls = 0;
      final client = SkipDbClient(
        MockClient((_) async {
          calls++;
          return http.Response('', calls == 1 ? 404 : 418);
        }),
        limiter: RateLimiter(perSecond: 1000),
        sleep: (_) async {},
      );
      expect(
        await client.lookup(const SkipQuery(season: 1, episode: 1)),
        SkipSegments.none,
      );
      expect(calls, 0);
      const q = SkipQuery(imdbId: 'tt0000001', season: 1, episode: 1);
      expect(await client.lookup(q), SkipSegments.none);
      final error = await client
          .lookup(q)
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<SkipException>());
      expect('$error', isNot(contains('tt0000001')));
      expect('$error', isNot(contains('skipdb')));
      expect('$q', isNot(contains('tt0000001')));
    });

    test('waits out a 429 and tries again', () async {
      var calls = 0;
      final client = SkipDbClient(
        MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('', 429, headers: {'retry-after': '0'})
              : http.Response('{"segments": {}}', 200);
        }),
        limiter: RateLimiter(perSecond: 1000),
        sleep: (_) async {},
      );
      await client.lookup(
        const SkipQuery(imdbId: 'tt0000001', season: 1, episode: 1),
      );
      expect(calls, 2);
    });

    test('network errors name only the type', () async {
      final client = SkipDbClient(
        MockClient(
          (request) async => throw http.ClientException('failed', request.url),
        ),
        maxRetries: 0,
        limiter: RateLimiter(perSecond: 1000),
        sleep: (_) async {},
      );
      final error = await client
          .lookup(const SkipQuery(imdbId: 'tt0000001', season: 1, episode: 1))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<SkipException>());
      expect((error as SkipException).failure, SkipFailure.network);
      expect('$error', isNot(contains('http')));
    });
  });

  group('IntroDbClient', () {
    test('asks by TMDB id with the length and the user key', () async {
      late http.Request asked;
      final client = IntroDbClient(
        MockClient((request) async {
          asked = request;
          return http.Response(
            jsonEncode({
              'tvdb_id': 1,
              'group_duration_ms': 2600000,
              'intro': [
                {'start_ms': null, 'end_ms': 45000},
              ],
              'recap': [
                {'start_ms': 0, 'end_ms': 0},
                {'start_ms': 50000, 'end_ms': 80000},
              ],
              'credits': [
                {'start_ms': 2500000, 'end_ms': null},
              ],
            }),
            200,
          );
        }),
        key: 'user-key',
        limiter: RateLimiter(perSecond: 1000),
        sleep: (_) async {},
      );
      final segments = await client.lookup(
        SkipQuery(
          imdbId: 'tt0000001',
          tmdbId: 7,
          season: 1,
          episode: 2,
          duration: s(2610),
        ),
      );
      expect(asked.url.host, 'api.theintrodb.org');
      expect(asked.url.path, '/v4/media');
      expect(asked.url.queryParameters, {
        'tmdb_id': '7',
        'season': '1',
        'episode': '2',
        'duration_ms': '2610000',
      });
      expect(asked.headers['Authorization'], 'Bearer user-key');
      expect(segments.intro, SkipRange(s(0), s(45)));
      expect(segments.recap, SkipRange(s(50), s(80)));
      expect(segments.credits, SkipRange(s(2500)));
      expect('$client', isNot(contains('user-key')));
    });

    test('IMDb id without a TMDB id; no key header without a key', () async {
      late http.Request asked;
      final client = IntroDbClient(
        MockClient((request) async {
          asked = request;
          return http.Response('{}', 200);
        }),
        limiter: RateLimiter(perSecond: 1000),
        sleep: (_) async {},
      );
      await client.lookup(
        const SkipQuery(imdbId: 'tt0000001', season: 1, episode: 1),
      );
      expect(asked.url.queryParameters['imdb_id'], 'tt0000001');
      expect(asked.url.queryParameters.containsKey('tmdb_id'), isFalse);
      expect(asked.headers.containsKey('Authorization'), isFalse);
    });

    test('the length of its copy is the reference', () {
      final json = {
        'group_duration_ms': 2600000,
        'credits': [
          {'start_ms': 2500000},
        ],
      };
      final parsed = IntroDbClient.parse(json);
      expect(parsed.credits, SkipRange(s(2500)));
      expect(parsed.reference, s(2600));
      expect(parsed.fittedTo(s(2400)).credits, SkipRange(s(2300)));
      expect(IntroDbClient.parse({}).reference, isNull);
    });

    test(
      'a daily limit stops all requests; a title limit that title',
      () async {
        var calls = 0;
        var code = 'specific_media_usage_limit_exceeded';
        final client = IntroDbClient(
          MockClient((_) async {
            calls++;
            return http.Response(
              jsonEncode({'code': code, 'retry_after_seconds': 3600}),
              429,
              headers: {'retry-after': '3600'},
            );
          }),
          limiter: RateLimiter(perSecond: 1000),
          sleep: (_) async {},
        );
        const a = SkipQuery(tmdbId: 1, season: 1, episode: 1);
        const b = SkipQuery(tmdbId: 2, season: 1, episode: 1);
        Future<SkipFailure?> failure(SkipQuery q) => client
            .lookup(q)
            .then<SkipFailure?>(
              (_) => null,
              onError: (Object e) => (e as SkipException).failure,
            );
        expect(await failure(a), SkipFailure.limitReached);
        expect(await failure(a), SkipFailure.limitReached);
        expect(calls, 1);
        code = 'usage_limit_exceeded';
        expect(await failure(b), SkipFailure.limitReached);
        expect(client.exhausted, isTrue);
        expect(
          await failure(const SkipQuery(tmdbId: 3, season: 1, episode: 1)),
          SkipFailure.limitReached,
        );
        expect(calls, 2);
      },
    );

    test('400 and 404 are "nothing known"; 401 a refused key', () async {
      var status = 404;
      final client = IntroDbClient(
        MockClient((_) async => http.Response('{}', status)),
        limiter: RateLimiter(perSecond: 1000),
        sleep: (_) async {},
      );
      const q = SkipQuery(tmdbId: 1, season: 1, episode: 1);
      expect(await client.lookup(q), SkipSegments.none);
      status = 400;
      expect(await client.lookup(q), SkipSegments.none);
      status = 401;
      await expectLater(
        client.lookup(q),
        throwsA(
          isA<SkipException>().having(
            (e) => e.failure,
            'failure',
            SkipFailure.unauthorized,
          ),
        ),
      );
    });
  });

  group('SkipStore', () {
    final now = DateTime.utc(2026, 10, 1);
    final times = SkipSegments(intro: SkipRange(s(10), s(70)));

    test('keeps answers for their TTL and length', () {
      final store = SkipStore.inMemory();
      addTearDown(store.close);
      store.put('tt1', 1, 1, times, duration: s(2600), at: now);
      store.put('tt1', 1, 2, SkipSegments.none, duration: s(2600), at: now);
      SkipSegments? get(int e, {Duration? d, int days = 0, bool any = false}) =>
          store.get(
            'tt1',
            1,
            e,
            duration: d ?? s(2600),
            now: now.add(Duration(days: days)),
            anyAge: any,
          );
      expect(get(1), times);
      expect(get(1, d: s(2601.9)), times);
      expect(get(1, d: s(2602.1)), isNull);
      expect(get(1, days: 30), times);
      expect(get(1, days: 31), isNull);
      expect(get(2), SkipSegments.none);
      expect(get(2, days: 4), isNull);
      expect(get(1, days: 400, d: s(10), any: true), times);
      expect(get(3), isNull);
    });

    test('one answer per length; downloads take the closest', () {
      final store = SkipStore.inMemory();
      addTearDown(store.close);
      final other = SkipSegments(intro: SkipRange(s(20), s(80)));
      store
        ..put('tt1', 1, 1, times, duration: s(2600), at: now)
        ..put('tt1', 1, 1, SkipSegments.none, duration: s(2400), at: now)
        ..put('tt1', 1, 1, other, at: now);
      SkipSegments? get(Duration? d, {bool any = false}) =>
          store.get('tt1', 1, 1, duration: d, now: now, anyAge: any);
      expect(get(s(2600)), times);
      expect(get(s(2400)), SkipSegments.none);
      expect(get(null), other);
      expect(get(s(2500)), isNull);
      expect(get(s(2550), any: true), times);
      expect(get(s(2420), any: true), SkipSegments.none);
    });

    test('a store of the first version starts again', () {
      final dir = Directory.systemTemp.createTempSync('skip_store');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/skip.sqlite';
      final old = sqlite3.open(path)
        ..execute('''
          CREATE TABLE skipdb_segment (
            imdb_id TEXT NOT NULL, season INTEGER NOT NULL,
            episode INTEGER NOT NULL, duration_ms INTEGER,
            found INTEGER NOT NULL, fetched_at INTEGER NOT NULL,
            segments_json TEXT NOT NULL,
            PRIMARY KEY (imdb_id, season, episode)
          ) WITHOUT ROWID''')
        ..execute(
          "INSERT INTO skipdb_segment VALUES ('tt1', 1, 1, 2600000, 0, "
          "${now.millisecondsSinceEpoch}, '{}')",
        )
        ..userVersion = 1;
      old.close();
      final store = SkipStore.open(path);
      addTearDown(store.close);
      expect(store.get('tt1', 1, 1, duration: s(2600), now: now), isNull);
      store.put('tt1', 1, 1, times, duration: s(2600), at: now);
      expect(store.get('tt1', 1, 1, duration: s(2600), now: now), times);
    });
  });
}
