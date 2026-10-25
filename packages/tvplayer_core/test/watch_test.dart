import 'dart:io';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _t0 = DateTime.utc(2026, 1, 1, 20);

DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

Episode _ep(int season, int number) => Episode(
  id: '${season * 100 + number}',
  season: season,
  episodeNumber: number,
  title: 'S${season}E$number',
  duration: const Duration(minutes: 40),
);

/// Series 7: specials S0E1–2, season 1 with 3 episodes, season 2 with 2.
final _info = SeriesInfo(
  series: const Series(seriesId: 7, name: 'Test Series'),
  seasons: const [
    Season(seasonNumber: 0, name: 'Specials'),
    Season(seasonNumber: 1, name: 'Season 1'),
    Season(seasonNumber: 2, name: 'Season 2'),
  ],
  episodes: [
    _ep(0, 1),
    _ep(0, 2),
    _ep(1, 1),
    _ep(1, 2),
    _ep(1, 3),
    _ep(2, 1),
    _ep(2, 2),
  ],
);

Episode _find(int season, int number) => _info.episodes.firstWhere(
  (e) => e.season == season && e.episodeNumber == number,
);

WatchData _watch(
  WatchData data,
  List<(int, int)> episodes, {
  required DateTime at,
  bool watched = true,
}) => markWatched(
  data,
  episodeTargets(_info, [for (final (s, e) in episodes) _find(s, e)]),
  watched: watched,
  now: at,
);

WatchData _play(WatchData data, (int, int) episode, int minutes, DateTime at) {
  final e = _find(episode.$1, episode.$2);
  return data.withItems({
    episodeKey(e.id): updatedProgress(
      data.episode(e.id),
      position: Duration(minutes: minutes),
      duration: e.duration,
      now: at,
      seriesId: 7,
    ),
  });
}

void main() {
  group('progress', () {
    test('becomes watched at 90 % and stays watched', () {
      const duration = Duration(minutes: 100);
      var p = updatedProgress(
        null,
        position: const Duration(minutes: 89),
        duration: duration,
        now: _t0,
      );
      expect(p.watched, isFalse);
      expect(p.fraction, closeTo(0.89, 0.001));
      p = updatedProgress(
        p,
        position: const Duration(minutes: 90),
        duration: duration,
        now: _t0,
      );
      expect(p.watched, isTrue);
      // Watching again from the start doesn't unmark it.
      p = updatedProgress(
        p,
        position: const Duration(minutes: 5),
        duration: null,
        now: _t0,
      );
      expect(p.watched, isTrue);
      expect(p.duration, duration, reason: 'keeps the known duration');
    });

    test('without a duration it never becomes watched by itself', () {
      final p = updatedProgress(
        null,
        position: const Duration(hours: 3),
        duration: null,
        now: _t0,
      );
      expect(p.watched, isFalse);
      expect(p.fraction, isNull);
    });

    test('resume position', () {
      WatchProgress p(int seconds, {bool watched = false}) => WatchProgress(
        position: Duration(seconds: seconds),
        duration: const Duration(minutes: 90),
        watched: watched,
        updatedAt: _t0,
      );
      expect(resumePosition(null), isNull);
      expect(resumePosition(p(5)), isNull, reason: 'barely started');
      expect(resumePosition(p(600)), const Duration(seconds: 600));
      expect(resumePosition(p(600, watched: true)), isNull);
      expect(isInProgress(p(600)), isTrue);
      expect(isInProgress(p(600, watched: true)), isFalse);
    });

    test('marking by hand', () {
      final key = movieKey(201);
      var data = WatchData.empty.withItems({
        key: WatchProgress(
          position: const Duration(minutes: 30),
          duration: const Duration(minutes: 90),
          updatedAt: _t0,
        ),
      });
      final target = (key: key, seriesId: null, duration: null);
      data = markWatched(data, [target], watched: true, now: _at(1));
      expect(data.movie(201)!.watched, isTrue);
      expect(data.movie(201)!.duration, const Duration(minutes: 90));
      expect(data.movie(201)!.updatedAt, _at(1));
      data = markWatched(data, [target], watched: false, now: _at(2));
      expect(data.movie(201)!.watched, isFalse);
      expect(data.movie(201)!.position, Duration.zero);
    });
  });

  group('seasons', () {
    test('tabs: seasons with episodes in order, specials last', () {
      expect(seasonTabs(_info), const [
        SeasonTab(1, 'Season 1'),
        SeasonTab(2, 'Season 2'),
        SeasonTab(0, 'Specials'),
      ]);
      expect(seasonTabs(_info).last.isSpecials, isTrue);
    });

    test('tabs skip seasons without episodes and fix missing names', () {
      final info = SeriesInfo(
        series: const Series(seriesId: 1, name: 'x'),
        seasons: const [
          Season(seasonNumber: 1, name: ''),
          Season(seasonNumber: 3, name: 'Season 3'),
          Season(seasonNumber: 2, name: 'Season 5'),
        ],
        episodes: [_ep(2, 1), _ep(1, 1)],
      );
      expect(seasonTabs(info), const [
        SeasonTab(1, 'Season 1'),
        SeasonTab(2, 'Season 2'),
      ]);
    });

    test('progress counts watched episodes per season', () {
      var data = _watch(WatchData.empty, [(1, 1), (1, 3)], at: _t0);
      data = _play(data, (1, 2), 10, _at(1)); // Started, not watched.
      expect(seasonProgress(_info, 1, data), const SeasonProgress(2, 3));
      expect(seasonProgress(_info, 1, data).label, '2/3');
      expect(seasonProgress(_info, 1, data).complete, isFalse);
      expect(seasonProgress(_info, 2, data), const SeasonProgress(0, 2));
      expect(seasonProgress(_info, 0, data), const SeasonProgress(0, 2));

      data = _play(data, (1, 2), 38, _at(2)); // 95 %: watched.
      expect(seasonProgress(_info, 1, data).complete, isTrue);
      expect(seasonProgress(_info, 1, data).label, '3/3');
    });

    test('marking a whole season watched and unwatched', () {
      final season = _info.episodesForSeason(2);
      var data = markWatched(
        WatchData.empty,
        episodeTargets(_info, season),
        watched: true,
        now: _t0,
      );
      expect(seasonProgress(_info, 2, data).complete, isTrue);
      expect(seasonProgress(_info, 1, data), const SeasonProgress(0, 3));
      expect(data.episode('201')!.seriesId, 7);
      data = markWatched(
        data,
        episodeTargets(_info, season),
        watched: false,
        now: _at(1),
      );
      expect(seasonProgress(_info, 2, data), const SeasonProgress(0, 2));
    });

    test('an empty season is never complete', () {
      expect(const SeasonProgress(0, 0).complete, isFalse);
    });
  });

  group('next episode', () {
    test('episodeAfter follows season order and crosses seasons', () {
      expect(episodeAfter(_info, _find(1, 1))?.id, _find(1, 2).id);
      expect(episodeAfter(_info, _find(1, 3))?.id, _find(2, 1).id);
      expect(episodeAfter(_info, _find(2, 2)), isNull);
      // Specials only lead to the next special.
      expect(episodeAfter(_info, _find(0, 1))?.id, _find(0, 2).id);
      expect(episodeAfter(_info, _find(0, 2)), isNull);
    });

    test('upNext: nothing played yet', () {
      expect(upNext(_info, WatchData.empty), isNull);
      expect(initialSeason(_info, WatchData.empty), 1);
    });

    test('upNext: the episode in progress', () {
      final data = _play(WatchData.empty, (1, 2), 10, _t0);
      expect(upNext(_info, data)?.id, _find(1, 2).id);
    });

    test('upNext: after finishing one, the next unwatched one', () {
      var data = _watch(WatchData.empty, [(2, 1)], at: _t0); // Seen before.
      data = _play(data, (1, 3), 39, _at(1)); // Finishes season 1.
      // S2E1 is already watched, so S2E2 is next; its season opens.
      expect(upNext(_info, data)?.id, _find(2, 2).id);
      expect(initialSeason(_info, data), 2);
    });

    test('upNext: after the last episode, the first one skipped', () {
      var data = _watch(WatchData.empty, [(1, 1), (1, 3), (2, 1)], at: _t0);
      data = _watch(data, [(2, 2)], at: _at(1));
      expect(upNext(_info, data)?.id, _find(1, 2).id);
    });

    test('upNext: everything watched', () {
      final data = _watch(WatchData.empty, [
        (1, 1),
        (1, 2),
        (1, 3),
        (2, 1),
        (2, 2),
      ], at: _t0);
      expect(upNext(_info, data), isNull);
      expect(initialSeason(_info, data), 1);
    });

    test('upNext: an episode marked unwatched by hand', () {
      var data = _watch(WatchData.empty, [(1, 1), (1, 2)], at: _t0);
      data = _watch(data, [(1, 1)], at: _at(1), watched: false);
      expect(upNext(_info, data)?.id, _find(1, 1).id);
    });
  });

  group('series summary and continue watching', () {
    test('summary points at the next unwatched episode, not the finished '
        'one', () {
      final data = _play(WatchData.empty, (1, 1), 40, _at(5));
      final summary = summarizeSeries(_info, data)!;
      expect(summary.nextEpisodeId, _find(1, 2).id);
      expect(summary.nextSeason, 1);
      expect(summary.nextEpisodeNumber, 2);
      expect(summary.nextTitle, 'S1E2');
      expect(summary.watchedEpisodes, 1);
      expect(summary.totalEpisodes, 5, reason: 'specials not counted');
      expect(summary.finished, isFalse);
      expect(summary.updatedAt, _at(5));
    });

    test('summary of an untouched series is null', () {
      expect(summarizeSeries(_info, WatchData.empty), isNull);
      expect(refreshSeries(WatchData.empty, _info), same(WatchData.empty));
    });

    test('finished series drop out of continue watching', () {
      var data = _watch(WatchData.empty, [
        (1, 1),
        (1, 2),
        (1, 3),
        (2, 1),
        (2, 2),
      ], at: _t0);
      data = refreshSeries(data, _info);
      expect(data.series[7]!.finished, isTrue);
      expect(data.series[7]!.fraction, 1);
      expect(continueSeries(data), isEmpty);
    });

    test('refreshSeries is a no-op when nothing changed', () {
      final data = refreshSeries(
        _play(WatchData.empty, (1, 1), 10, _t0),
        _info,
      );
      expect(refreshSeries(data, _info), same(data));
    });

    test('continue watching lists are newest first', () {
      var data = WatchData.empty.withItems({
        movieKey(1): WatchProgress(
          position: const Duration(minutes: 20),
          duration: const Duration(minutes: 90),
          updatedAt: _at(1),
        ),
        movieKey(2): WatchProgress(
          position: const Duration(minutes: 20),
          duration: const Duration(minutes: 90),
          updatedAt: _at(3),
        ),
        // Watched and barely started movies are left out.
        movieKey(3): WatchProgress(
          position: const Duration(minutes: 89),
          duration: const Duration(minutes: 90),
          watched: true,
          updatedAt: _at(4),
        ),
        movieKey(4): WatchProgress(
          position: const Duration(seconds: 3),
          updatedAt: _at(5),
        ),
      });
      expect([for (final (id, _) in continueMovies(data)) id], [2, 1]);

      data = data
          .withSeries(
            1,
            SeriesProgress(
              nextEpisodeId: '1',
              watchedEpisodes: 1,
              totalEpisodes: 3,
              updatedAt: _at(1),
            ),
          )
          .withSeries(
            2,
            SeriesProgress(
              nextEpisodeId: '9',
              watchedEpisodes: 0,
              totalEpisodes: 3,
              updatedAt: _at(2),
            ),
          );
      expect([for (final (id, _) in continueSeries(data)) id], [2, 1]);
    });
  });

  _channelHistoryTests();

  group('storage', () {
    WatchData sample() => _play(WatchData.empty, (1, 1), 10, _t0)
        .withItems({
          movieKey(201): WatchProgress(
            position: const Duration(minutes: 89),
            duration: const Duration(minutes: 90),
            watched: true,
            updatedAt: _at(1),
          ),
        })
        .withTracks(
          7,
          SeriesTracks(const TrackMemory(subtitleLanguage: 'sv'), _at(2)),
        )
        .let((d) => refreshSeries(d, _info));

    void expectSame(WatchData a, WatchData b) {
      expect(a.items, b.items);
      expect(a.series, b.series);
      expect(a.seriesTracks.keys, b.seriesTracks.keys);
      for (final key in a.seriesTracks.keys) {
        expect(a.seriesTracks[key]!.memory, b.seriesTracks[key]!.memory);
        expect(a.seriesTracks[key]!.updatedAt, b.seriesTracks[key]!.updatedAt);
      }
    }

    test('JSON round trip', () {
      final data = sample();
      expectSame(WatchData.fromJson(data.toJson()), data);
    });

    test('unreadable records are skipped', () {
      final data = WatchData.fromJson({
        'version': 1,
        'records': [
          {
            'k': 'movie:1',
            't': 1000,
            'v': {'pos': 5000},
          },
          {'k': 'series:abc', 't': 1000, 'v': {}},
          {'k': 'nocolon', 't': 1000},
          {'k': 'movie:2'},
          'garbage',
        ],
      });
      expect(data.items.keys, ['movie:1']);
      expect(data.movie(1)!.position, const Duration(seconds: 5));
      expect(WatchData.fromJson('nonsense').items, isEmpty);
    });

    test('merge keeps the newer record of each key', () {
      final a = WatchData.empty.withItems({
        movieKey(1): WatchProgress(position: Duration.zero, updatedAt: _at(1)),
        movieKey(2): WatchProgress(
          position: const Duration(minutes: 5),
          updatedAt: _at(5),
        ),
      });
      final b = WatchData.empty.withItems({
        movieKey(1): WatchProgress(
          position: const Duration(minutes: 7),
          updatedAt: _at(2),
        ),
        movieKey(2): WatchProgress(position: Duration.zero, updatedAt: _at(3)),
        movieKey(3): WatchProgress(position: Duration.zero, updatedAt: _at(1)),
      });
      final merged = a.merge(b);
      expect(merged.movie(1)!.position, const Duration(minutes: 7));
      expect(merged.movie(2)!.position, const Duration(minutes: 5));
      expect(merged.items, hasLength(3));
      expect(b.merge(a).items, merged.items, reason: 'order does not matter');
    });

    test('file store saves and loads, and starts empty', () async {
      final dir = await Directory.systemTemp.createTemp('watch_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = JsonFileWatchStore(File('${dir.path}/sub/watch.json'));
      expect((await store.load()).items, isEmpty);
      final data = sample();
      await store.save(data);
      expectSame(await store.load(), data);

      await File('${dir.path}/sub/watch.json').writeAsString('{broken');
      expect((await store.load()).items, isEmpty);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

void _channelHistoryTests() {
  group('channel history', () {
    test('newest first, at most 20, watching again moves to the front', () {
      var data = WatchData.empty;
      for (var i = 0; i < 25; i++) {
        data = recordChannel(data, 'ch$i', _at(i));
      }
      data = recordChannel(data, 'ch10', _at(30));
      final recent = recentChannels(data);
      expect(recent, hasLength(maxChannelHistory));
      expect(recent.first, ('ch10', _at(30)));
      expect(recent[1].$1, 'ch24');
      expect(recent.map((r) => r.$1), isNot(contains('ch0')));
    });

    test('forgetting survives a merge with an older copy', () {
      final watched = recordChannel(WatchData.empty, 'a', _at(1));
      final forgotten = forgetChannel(watched, 'a', _at(2));
      expect(recentChannels(forgotten), isEmpty);
      expect(recentChannels(watched.merge(forgotten)), isEmpty);
      expect(recentChannels(forgotten.merge(watched)), isEmpty);
      // Watching it again brings it back.
      expect(recentChannels(recordChannel(forgotten, 'a', _at(3))), [
        ('a', _at(3)),
      ]);
    });

    test('JSON round trip', () {
      final data = forgetChannel(
        recordChannel(recordChannel(WatchData.empty, 'a', _at(1)), 'b', _at(2)),
        'a',
        _at(3),
      );
      expect(WatchData.fromJson(data.toJson()).channels, data.channels);
    });
  });
}
