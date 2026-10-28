import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

Map<String, Object?> _json(String name) =>
    jsonDecode(fixture('tmdb/$name')) as Map<String, Object?>;

final _at = DateTime.utc(2026, 1, 1);

TmdbKey _movie(int id) => TmdbKey(TmdbKind.movie, id);

/// A [TmdbApi] answering from memory, counting requests.
class _FakeApi implements TmdbApi {
  final asked = <String>[];
  final missing = <TmdbKey>{};
  final searchResults = <String, List<TmdbSearchResult>>{};
  TmdbFailure? failWith;

  /// When set, title requests wait for it.
  Completer<void>? gate;

  @override
  Future<TmdbTitle> title(TmdbKey key) async {
    asked.add('$key');
    await gate?.future;
    if (failWith case final f?) throw TmdbException(f, 'fake');
    if (missing.contains(key)) {
      throw const TmdbException(TmdbFailure.notFound, 'fake');
    }
    return TmdbTitle(
      key: key,
      fetchedAt: _at,
      title: 'Title $key',
      posterPath: '/${key.id}.jpg',
    );
  }

  @override
  Future<TmdbSeason> season(int tvId, int number) async {
    asked.add('season $tvId/$number');
    return TmdbSeason.fromJson(
      tvId,
      number,
      _json('season.json'),
      fetchedAt: _at,
    );
  }

  @override
  Future<TmdbPerson> person(int id) async {
    asked.add('person $id');
    return TmdbPerson.fromJson(_json('person.json'), fetchedAt: _at)!;
  }

  @override
  Future<List<TmdbSearchResult>> search(
    TmdbKind kind,
    String query, {
    int? year,
  }) async {
    asked.add('search $query ${year ?? '-'}');
    return searchResults[query] ?? const [];
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('TmdbStore', () {
    late TmdbStore store;
    setUp(() => store = TmdbStore.inMemory());
    tearDown(() => store.close());

    test('keeps a title with genres, cast and recommendations', () {
      final movie = TmdbTitle.fromJson(
        TmdbKind.movie,
        _json('movie.json'),
        fetchedAt: _at,
      )!;
      store.putTitle(movie);
      final back = store.title(movie.key)!;
      expect(back.title, 'Example Movie');
      expect(back.fetchedAt, _at);
      expect(back.vote, 7.8);
      expect(back.imdbId, 'tt0000001');
      expect(back.genreText, 'Crime, Drama');
      expect(back.cast.map((c) => c.character), ['Hero', 'Villain']);
      expect(back.recommendations, movie.recommendations);
      expect(store.artwork().single.backdrop, '/backdrop-plain-high.jpg');
    });

    test('titles TMDB lacks are kept apart, and retried after a while', () {
      store.putNotFound(_movie(5), _at);
      expect(store.title(_movie(5)), isNull);
      expect(
        store.fetchedTitles(
          notFoundSince: _at.subtract(const Duration(days: 1)),
        ),
        contains(_movie(5)),
      );
      expect(
        store.fetchedTitles(notFoundSince: _at.add(const Duration(days: 1))),
        isEmpty,
      );
    });

    test('keeps seasons, people, matches and removed links', () {
      store.putSeason(
        TmdbSeason.fromJson(2001, 1, _json('season.json'), fetchedAt: _at),
      );
      expect(store.season(2001, 1)!.episode(1)!.name, 'Pilot');
      expect(store.season(2001, 2), isNull);
      store.putPerson(
        TmdbPerson.fromJson(_json('person.json'), fetchedAt: _at)!,
      );
      expect(store.person(501)!.credits, hasLength(2));
      store.putMatch(
        TmdbKind.movie,
        'a|2019',
        TitleMatch(MatchOutcome.matched, _at, 9),
      );
      store.putMatch(
        TmdbKind.movie,
        'b|2019',
        TitleMatch(MatchOutcome.removed, _at),
      );
      store.removeLink(_movie(7), _at);
      expect(store.matches()[(TmdbKind.movie, 'a|2019')]!.tmdbId, 9);
      expect(store.removedLinks(), {_movie(7)});
      expect(store.removedCount(), 2);
      store.allowMatchingAgain();
      expect(store.removedCount(), 0);
      expect(store.matches().keys, [(TmdbKind.movie, 'a|2019')]);
    });

    test('a database file is reopened with its data', () {
      final dir = Directory.systemTemp.createTempSync('tmdb_store');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/tmdb.sqlite';
      TmdbStore.open(path)
        ..putTitle(TmdbTitle(key: _movie(1), fetchedAt: _at, title: 'Kept'))
        ..close();
      final again = TmdbStore.open(path);
      expect(again.title(_movie(1))!.title, 'Kept');
      again.close();
    });
  });

  group('TmdbSync', () {
    late TmdbStore store;
    late _FakeApi api;
    late TmdbSync sync;
    late List<TmdbProgress> progress;

    setUp(() {
      store = TmdbStore.inMemory();
      api = _FakeApi();
      sync = TmdbSync(store: store, api: api, now: () => _at, workers: 2);
      progress = [];
      sync.events.listen((e) {
        if (e is TmdbProgressEvent) progress.add(e.progress);
      });
    });
    tearDown(() async {
      await sync.close();
      store.close();
    });

    test('fetches each wanted title once and reports progress', () async {
      await sync.setWork([_movie(1), _movie(2), _movie(1)], const []);
      await _settle();
      expect(api.asked..sort(), ['movie/1', 'movie/2']);
      expect(progress.last, const TmdbProgress(2, 2, TmdbSyncState.upToDate));
      expect(store.title(_movie(2))!.posterPath, '/2.jpg');
    });

    test('only titles not stored yet are fetched (restart, refresh)', () async {
      store.putTitle(TmdbTitle(key: _movie(1), fetchedAt: _at));
      await sync.setWork([_movie(1), _movie(2)], const []);
      await _settle();
      expect(api.asked, ['movie/2']);
      expect(progress.last.done, 2);
    });

    test('titles TMDB lacks are stored as such and not asked again', () async {
      api.missing.add(_movie(3));
      await sync.setWork([_movie(3)], const []);
      await _settle();
      await sync.setWork([_movie(3)], const []);
      await _settle();
      expect(api.asked, ['movie/3']);
    });

    test('pauses and resumes', () async {
      await sync.setPause(TmdbPause.playback);
      await sync.setWork([_movie(1), _movie(2)], const []);
      await _settle();
      expect(api.asked, isEmpty);
      expect(progress.last.state, TmdbSyncState.pausedForPlayback);
      await sync.setPause(TmdbPause.user);
      expect(progress.last.state, TmdbSyncState.paused);
      await sync.setPause(null);
      await _settle();
      expect(api.asked, hasLength(2));
    });

    test('a title opened while paused is fetched at once', () async {
      await sync.setPause(TmdbPause.playback);
      await sync.setWork([_movie(1), _movie(2)], const []);
      final title = await sync.title(_movie(2));
      expect(title!.title, 'Title movie/2');
      expect(api.asked, ['movie/2']);
      expect(sync.progress.done, 1);
      // Stored now: no second request.
      await sync.title(_movie(2));
      expect(api.asked, ['movie/2']);
    });

    test('stops when the key is rejected', () async {
      api.failWith = TmdbFailure.unauthorized;
      await sync.setWork([_movie(1), _movie(2)], const []);
      await _settle();
      expect(progress.last.state, TmdbSyncState.keyRejected);
      expect(api.asked.length, lessThanOrEqualTo(2));
    });

    test(
      'finds titles without an id by searching, then fetches them',
      () async {
        api.searchResults['Example Movie'] = const [
          TmdbSearchResult(
            TmdbKey(TmdbKind.movie, 1001),
            title: 'Example Movie',
            year: 2019,
          ),
        ];
        final search = TitleSearch.of(
          TmdbKind.movie,
          'Example Movie (2019)',
          ProviderTags.empty,
        )!;
        final events = <TmdbMatchEvent>[];
        sync.events.listen((e) {
          if (e is TmdbMatchEvent) events.add(e);
        });
        await sync.setWork(const [], [search]);
        await _settle();
        expect(api.asked, ['search Example Movie 2019', 'movie/1001']);
        expect(events.single.match!.tmdbId, 1001);
        expect(
          store.matches()[(TmdbKind.movie, search.key)]!.outcome,
          MatchOutcome.matched,
        );
        expect(await sync.resolve(search), const TmdbKey(TmdbKind.movie, 1001));
      },
    );

    test(
      'an unsure search is stored as no match and retried without the year',
      () async {
        final search = TitleSearch(TmdbKind.movie, 'x|2019', 'X', 2019);
        await sync.setWork(const [], [search]);
        await _settle();
        expect(api.asked, ['search X 2019', 'search X -']);
        expect(
          store.matches()[(TmdbKind.movie, 'x|2019')]!.outcome,
          MatchOutcome.noMatch,
        );
        expect(await sync.resolve(search), isNull);
        expect(api.asked, hasLength(2));
      },
    );

    test('a removed match is never searched again until allowed', () async {
      final search = TitleSearch(TmdbKind.movie, 'x|2019', 'X', 2019);
      await sync.removeMatch(TmdbKind.movie, 'x|2019');
      await sync.setWork(const [], [search]);
      await _settle();
      expect(await sync.resolve(search), isNull);
      expect(api.asked, isEmpty);
      expect(sync.progress.total, 0);
      await sync.allowMatchingAgain();
      await sync.setWork(const [], [search]);
      await _settle();
      expect(api.asked, isNotEmpty);
    });

    test('a removed link is left out of the work', () async {
      await sync.removeLink(_movie(1));
      await sync.setWork([_movie(1), _movie(2)], const []);
      await _settle();
      expect(api.asked, ['movie/2']);
      expect(await sync.removedCount(), 1);
      expect(await sync.removedLinks(), {_movie(1)});
    });

    test('seasons and people are fetched once and kept', () async {
      expect((await sync.season(2001, 1))!.episodes, hasLength(2));
      await sync.season(2001, 1);
      expect((await sync.person(501))!.name, 'Actor One');
      await sync.person(501);
      expect(api.asked, ['season 2001/1', 'person 501']);
    });

    test('seasons of ongoing series are refreshed when old', () async {
      var now = _at;
      final s = TmdbSync(store: store, api: api, now: () => now);
      await s.season(2001, 1, ongoing: true);
      now = now.add(const Duration(days: 8));
      await s.season(2001, 1);
      await s.season(2001, 1, ongoing: true);
      expect(api.asked, ['season 2001/1', 'season 2001/1']);
      await s.close();
    });
  });

  test('TmdbWorker runs the store in a background isolate', () async {
    final dir = Directory.systemTemp.createTempSync('tmdb_worker');
    addTearDown(() => dir.deleteSync(recursive: true));
    final worker = await TmdbWorker.spawn(
      databasePath: '${dir.path}/tmdb.sqlite',
      credential: TmdbCredential.parse('0123456789abcdef0123456789abcdef')!,
    );
    final progress = worker.events.whereType<TmdbProgressEvent>().first.then(
      (e) => e.progress,
    );
    await worker.setWork(const [], const []);
    expect((await progress).state, TmdbSyncState.upToDate);
    await worker.removeMatch(TmdbKind.tv, 'some show|');
    expect(await worker.removedCount(), 1);
    expect(
      (await worker.matches())[(TmdbKind.tv, 'some show|')]!.outcome,
      MatchOutcome.removed,
    );
    expect(await worker.artwork(), isEmpty);
    await worker.close();
  });
}

extension<T> on Stream<T> {
  Stream<S> whereType<S>() => where((e) => e is S).cast<S>();
}
