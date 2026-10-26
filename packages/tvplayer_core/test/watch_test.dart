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
  _groupMain();
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
      final target = movieTarget(201);
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
  _continueRemovalTests();

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

void _continueRemovalTests() {
  group('remove from continue watching', () {
    final started = WatchProgress(
      position: const Duration(minutes: 20),
      duration: const Duration(minutes: 90),
      updatedAt: _at(1),
    );

    test('removing a movie clears its resume position; undo restores it '
        'as a newer change', () {
      final data = WatchData.empty.withItems({movieKey(1): started});
      final removed = removeContinueMovie(data, 1, _at(2));
      expect(continueMovies(removed), isEmpty);
      expect(resumePosition(removed.movie(1)), isNull);
      expect(removed.movie(1)!.duration, started.duration);
      expect(removed.movie(1)!.updatedAt, _at(2));
      expect(continueMovies(data.merge(removed)), isEmpty);
      expect(removeContinueMovie(WatchData.empty, 1, _at(2)).items, isEmpty);

      final restored = restoreContinueMovie(removed, 1, started, _at(3));
      expect(resumePosition(restored.movie(1)), started.position);
      expect(restored.movie(1)!.updatedAt, _at(3));
      expect(continueMovies(removed.merge(restored)), hasLength(1));
    });

    test('removing a series hides it but keeps its episodes', () {
      var data = refreshSeries(
        _play(
          _watch(WatchData.empty, [(1, 1)], at: _at(1)),
          (1, 2),
          10,
          _at(2),
        ),
        _info,
      );
      final summary = data.series[7];
      data = removeContinueSeries(data, 7, _at(3));
      expect(continueSeries(data), isEmpty);
      expect(data.series[7], summary, reason: 'poster badge stays');
      expect(data.episode(_find(1, 1).id)!.watched, isTrue);
      expect(
        data.episode(_find(1, 2).id)!.position,
        const Duration(minutes: 10),
      );
      // A summary refresh (e.g. new episodes) doesn't bring it back.
      expect(continueSeries(refreshSeries(data, _info)), isEmpty);
    });

    test('a removed series comes back when an episode is played again', () {
      var data = refreshSeries(
        _play(WatchData.empty, (1, 1), 10, _at(1)),
        _info,
      );
      data = removeContinueSeries(data, 7, _at(2));
      data = refreshSeries(_play(data, (1, 1), 12, _at(3)), _info);
      expect([for (final (id, _) in continueSeries(data)) id], [7]);
    });

    test('undo brings a series back in its old place, also after a '
        'merge', () {
      var data =
          refreshSeries(
            _play(WatchData.empty, (1, 1), 10, _at(1)),
            _info,
          ).withSeries(
            8,
            SeriesProgress(
              nextEpisodeId: '1',
              watchedEpisodes: 0,
              totalEpisodes: 3,
              updatedAt: _at(0),
            ),
          );
      final removed = removeContinueSeries(data, 7, _at(2));
      expect([for (final (id, _) in continueSeries(removed)) id], [8]);
      final restored = restoreContinueSeries(removed, 7, _at(3));
      expect([for (final (id, _) in continueSeries(restored)) id], [7, 8]);
      expect(restoreContinueSeries(data, 7, _at(3)), same(data));

      // The newer choice wins, whichever copy it is in.
      expect(continueSeries(data.merge(removed)), hasLength(1));
      expect(continueSeries(removed.merge(data)), hasLength(1));
      expect(continueSeries(removed.merge(restored)), hasLength(2));
      expect(continueSeries(restored.merge(removed)), hasLength(2));
      expect(continueAll(removed).map((e) => e.updatedAt), [_at(0)]);
    });

    test('JSON round trip', () {
      final data = restoreContinueSeries(
        removeContinueSeries(
          removeContinueSeries(WatchData.empty, 7, _at(1)),
          8,
          _at(2),
        ),
        8,
        _at(3),
      );
      final read = WatchData.fromJson(data.toJson());
      expect(read.continueRemovals, data.continueRemovals);
      expect(read.continueRemovals[7], ContinueRemoval(_at(1)));
      expect(read.continueRemovals[8], ContinueRemoval(_at(3), removed: false));
    });
  });
}

/// A series variant: episodes of seasons 1 and 2 (with [extra] more in
/// season 2) and a special, with ids starting at [base].
SeriesInfo _variant(int seriesId, int base, {int extra = 0}) => SeriesInfo(
  series: Series(seriesId: seriesId, name: 'Variant $seriesId'),
  seasons: const [],
  episodes: [
    Episode(id: '${base + 1}', season: 0, episodeNumber: 1, title: 'Special'),
    for (var n = 1; n <= 3; n++)
      Episode(
        id: '${base + 10 + n}',
        season: 1,
        episodeNumber: n,
        title: 'S1E$n',
      ),
    for (var n = 1; n <= 2 + extra; n++)
      Episode(
        id: '${base + 20 + n}',
        season: 2,
        episodeNumber: n,
        title: 'S2E$n',
      ),
    // No episode number: never matched.
    Episode(id: '${base + 99}', season: 2, episodeNumber: 0, title: 'Extra'),
  ],
);

WatchData _playIn(
  WatchData data,
  SeriesInfo info,
  Episode e, {
  required int minutes,
  required DateTime at,
}) => data.withItems({
  episodeKey(e.id): updatedProgress(
    data.episode(e.id),
    position: Duration(minutes: minutes),
    duration: const Duration(minutes: 40),
    now: at,
    seriesId: info.series.seriesId,
    season: e.season,
    episode: e.episodeNumber,
  ),
});

Episode _episodeOf(SeriesInfo info, int season, int number) => info.episodes
    .firstWhere((e) => e.season == season && e.episodeNumber == number);

void _groupMain() {
  // NF (series 1) and EN (series 2) are variants; EN has one more episode.
  final nf = _variant(1, 1000);
  final en = _variant(2, 2000, extra: 1);

  group('series variants', () {
    test('episodes match by season and episode number', () {
      var data = WatchData.empty;
      data = _playIn(data, nf, _episodeOf(nf, 1, 1), minutes: 39, at: _at(1));
      data = _playIn(data, nf, _episodeOf(nf, 1, 2), minutes: 12, at: _at(2));
      final view = EpisodeGroupView(data, 2, [1]);
      expect(view.progress(_episodeOf(en, 1, 1))!.watched, isTrue);
      final e2 = view.progress(_episodeOf(en, 1, 2))!;
      expect(e2.position, const Duration(minutes: 12));
      expect(resumePosition(e2), const Duration(minutes: 12));
      expect(view.sourceOf(_episodeOf(en, 1, 2)), 1);
      expect(view.progress(_episodeOf(en, 1, 3)), isNull);
      // Without the group: nothing.
      expect(data.episode(_episodeOf(en, 1, 1).id), isNull);
    });

    test('the newest position wins; watched anywhere stays watched', () {
      var data = WatchData.empty;
      data = _playIn(data, nf, _episodeOf(nf, 1, 1), minutes: 39, at: _at(1));
      data = _playIn(data, en, _episodeOf(en, 1, 1), minutes: 5, at: _at(2));
      final view = EpisodeGroupView(data, 2, [1]);
      final p = view.progress(_episodeOf(en, 1, 1))!;
      expect(p.watched, isTrue);
      expect(p.position, const Duration(minutes: 5));
      expect(view.sourceOf(_episodeOf(en, 1, 1)), isNull);
    });

    test('unmatched episodes keep their own state', () {
      var data = WatchData.empty;
      data = _playIn(data, nf, _episodeOf(nf, 2, 0), minutes: 39, at: _at(1));
      data = _playIn(data, nf, _episodeOf(nf, 0, 1), minutes: 39, at: _at(2));
      // A record from before season and episode were kept.
      data = data.withItems({
        episodeKey('1013'): WatchProgress(
          position: const Duration(minutes: 39),
          duration: const Duration(minutes: 40),
          watched: true,
          seriesId: 1,
          updatedAt: _at(3),
        ),
      });
      final view = EpisodeGroupView(data, 2, [1]);
      expect(view.progress(_episodeOf(en, 2, 0)), isNull);
      // Specials match only on the same numbers.
      expect(view.progress(_episodeOf(en, 0, 1))!.watched, isTrue);
      expect(view.progress(_episodeOf(en, 1, 3)), isNull);
      // Until the NF page fills them in.
      data = refreshSeries(data, nf);
      expect(data.episode('1013')!.season, 1);
      expect(data.episode('1013')!.episode, 3);
      expect(
        EpisodeGroupView(data, 2, [1]).progress(_episodeOf(en, 1, 3))!.watched,
        isTrue,
      );
    });

    test('variants with different episode counts', () {
      var data = WatchData.empty;
      for (final e in nf.episodes.where((e) => e.season > 0)) {
        data = _playIn(data, nf, e, minutes: 39, at: _at(e.episodeNumber));
      }
      final view = EpisodeGroupView(data, 2, [1]);
      expect(seasonProgress(en, 1, data, group: view).label, '3/3');
      expect(seasonProgress(en, 2, data, group: view).label, '2/4');
      // EN's extra episode is next.
      expect(upNext(en, data, group: view)!.id, _episodeOf(en, 2, 3).id);
      final summary = summarizeSeries(en, data, group: view)!;
      expect(summary.watchedEpisodes, 5);
      expect(summary.totalEpisodes, 7);
    });

    test('next up continues from another variant', () {
      var data = WatchData.empty;
      data = _playIn(data, nf, _episodeOf(nf, 1, 1), minutes: 39, at: _at(1));
      data = _playIn(data, nf, _episodeOf(nf, 1, 2), minutes: 39, at: _at(2));
      final view = EpisodeGroupView(data, 2, [1]);
      expect(upNext(en, data), isNull);
      expect(upNext(en, data, group: view)!.id, _episodeOf(en, 1, 3).id);
      expect(initialSeason(en, data, group: view), 1);
      data = refreshSeries(data, en, variants: [1]);
      expect(data.series[2]!.nextEpisodeId, _episodeOf(en, 1, 3).id);
      expect(data.series[2]!.updatedAt, _at(2));
    });

    test('marking a season marks it in every variant, also unwatched', () {
      var data = WatchData.empty;
      data = _playIn(data, nf, _episodeOf(nf, 1, 1), minutes: 39, at: _at(1));
      data = _playIn(data, nf, _episodeOf(nf, 1, 2), minutes: 20, at: _at(2));
      var view = EpisodeGroupView(data, 2, [1]);
      final season = en.episodesForSeason(1);
      data = markWatched(
        data,
        groupEpisodeTargets(en, season, view),
        watched: true,
        now: _at(3),
      );
      expect(data.episode(_episodeOf(nf, 1, 2).id)!.watched, isTrue);
      view = EpisodeGroupView(data, 1, [2]);
      expect(seasonProgress(nf, 1, data, group: view).label, '3/3');

      data = markWatched(
        data,
        groupEpisodeTargets(en, season, EpisodeGroupView(data, 2, [1])),
        watched: false,
        now: _at(4),
      );
      view = EpisodeGroupView(data, 1, [2]);
      expect(seasonProgress(nf, 1, data, group: view).label, '0/3');
      expect(data.episode(_episodeOf(nf, 1, 1).id)!.watched, isFalse);
      // The marked records keep their numbers.
      expect(data.episode(_episodeOf(en, 1, 3).id)!.episode, 3);
    });

    test('continue watching shows one card per group', () {
      var data = WatchData.empty;
      data = _playIn(data, nf, _episodeOf(nf, 1, 1), minutes: 10, at: _at(1));
      data = refreshSeries(data, nf);
      data = _playIn(data, en, _episodeOf(en, 1, 1), minutes: 12, at: _at(2));
      data = refreshSeries(data, en);
      final third = _variant(3, 3000);
      data = _playIn(
        data,
        third,
        _episodeOf(third, 1, 1),
        minutes: 5,
        at: _at(0),
      );
      data = refreshSeries(data, third);
      List<int> groupOf(int id) => id == 3 ? [3] : [1, 2];
      expect(continueSeries(data).map((e) => e.$1), [2, 1, 3]);
      expect(continueSeriesGroups(data, groupOf).map((e) => e.$1), [2, 3]);
      // Removing every variant removes the card.
      for (final id in [1, 2]) {
        data = removeContinueSeries(data, id, _at(5));
      }
      expect(continueSeriesGroups(data, groupOf).map((e) => e.$1), [3]);
    });
  });

  group('movie variants', () {
    WatchData started(WatchData data, int id, int minutes, int at) =>
        data.withItems({
          movieKey(id): updatedProgress(
            data.movie(id),
            position: Duration(minutes: minutes),
            duration: const Duration(minutes: 90),
            now: _at(at),
          ),
        });

    test('the group takes the newest position; watched if any is', () {
      var data = started(WatchData.empty, 1, 30, 1);
      data = started(data, 2, 50, 2);
      final g = movieGroupProgress(data, [1, 2, 3])!;
      expect(g.from, 2);
      expect(g.progress.position, const Duration(minutes: 50));
      expect(g.progress.watched, isFalse);
      data = started(data, 3, 89, 0);
      expect(movieGroupProgress(data, [1, 2, 3])!.progress.watched, isTrue);
      expect(movieGroupProgress(data, [4]), isNull);
    });

    test('continue watching: one per group, none when one is watched', () {
      var data = started(WatchData.empty, 1, 30, 1);
      data = started(data, 2, 50, 2);
      data = started(data, 5, 10, 3);
      List<int> groupOf(int id) => id == 5 ? [5] : [1, 2, 3];
      expect(continueMovieGroups(data, groupOf).map((e) => e.$1), [5, 2]);
      data = markWatched(data, [movieTarget(3)], watched: true, now: _at(4));
      expect(continueMovieGroups(data, groupOf).map((e) => e.$1), [5]);
    });
  });

  group('last played', () {
    test('the newest start wins; round-trips and merges', () {
      var data = recordPlayed(WatchData.empty, movieKey(1), _at(1));
      data = recordPlayed(data, movieKey(2), _at(2));
      data = recordPlayed(data, seriesKey(7), _at(3));
      expect(lastPlayed(data, [movieKey(1), movieKey(2)]), movieKey(2));
      expect(lastPlayed(data, [movieKey(3)]), isNull);
      final back = WatchData.fromJson(data.toJson());
      expect(back.played, data.played);
      final other = recordPlayed(WatchData.empty, movieKey(1), _at(9));
      expect(
        lastPlayed(back.merge(other), [movieKey(1), movieKey(2)]),
        movieKey(1),
      );
    });

    test('episode numbers round-trip; old records have none', () {
      final p = WatchProgress(
        position: Duration.zero,
        updatedAt: _t0,
        seriesId: 1,
        season: 2,
        episode: 3,
      );
      final back = WatchProgress.fromJson(p.toJson(), _t0);
      expect(back, p);
      final old = WatchProgress.fromJson({'pos': 1, 'series': 1}, _t0);
      expect(old.season, isNull);
      expect(old.episode, isNull);
    });
  });
}
