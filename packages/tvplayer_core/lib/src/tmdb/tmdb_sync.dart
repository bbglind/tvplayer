import 'dart:async';
import 'dart:collection';

import 'rate_limiter.dart';
import 'title_match.dart';
import 'tmdb_client.dart';
import 'tmdb_models.dart';
import 'tmdb_store.dart';

/// What the background fetch is doing.
enum TmdbSyncState {
  /// Working through the titles without TMDB info.
  running,

  /// Every title has been looked up.
  upToDate,

  /// Paused by the user.
  paused,

  /// Paused because something is playing.
  pausedForPlayback,

  /// TMDB can't be reached; tried again shortly.
  waitingForNetwork,

  /// TMDB didn't accept the key; stopped.
  keyRejected,
}

/// Why the background fetch must not run, if it must not.
enum TmdbPause { user, playback }

/// How far the background fetch got.
final class TmdbProgress {
  const TmdbProgress(this.done, this.total, this.state);

  static const none = TmdbProgress(0, 0, TmdbSyncState.upToDate);

  /// Titles looked up (found or not), of [total].
  final int done;
  final int total;
  final TmdbSyncState state;

  @override
  bool operator ==(Object other) =>
      other is TmdbProgress &&
      other.done == done &&
      other.total == total &&
      other.state == state;

  @override
  int get hashCode => Object.hash(done, total, state);

  @override
  String toString() => 'TmdbProgress($done/$total, ${state.name})';
}

/// Something the app shows changed in the store.
sealed class TmdbEvent {
  const TmdbEvent();
}

final class TmdbProgressEvent extends TmdbEvent {
  const TmdbProgressEvent(this.progress);

  final TmdbProgress progress;
}

/// New or changed images of titles.
final class TmdbArtworkEvent extends TmdbEvent {
  const TmdbArtworkEvent(this.artwork);

  final List<TmdbArtwork> artwork;
}

/// A title search ended, or a match was removed.
final class TmdbMatchEvent extends TmdbEvent {
  const TmdbMatchEvent(this.kind, this.key, this.match);

  final TmdbKind kind;
  final String key;
  final TitleMatch? match;
}

/// The genres of a newly stored title.
final class TmdbGenresEvent extends TmdbEvent {
  const TmdbGenresEvent(this.genres);

  final Map<TmdbKey, List<String>> genres;
}

/// A stored title was fetched again and may have changed.
final class TmdbTitleEvent extends TmdbEvent {
  const TmdbTitleEvent(this.title);

  final TmdbTitle title;
}

/// The TMDB data the app uses: the background fetch and lookups that jump
/// ahead of it. [TmdbSync] in-process, [TmdbWorker] in a background
/// isolate.
abstract interface class TmdbBackend {
  Stream<TmdbEvent> get events;

  /// The titles of the catalogues: [wanted] (provider TMDB ids, the most
  /// wanted first) and [searches] (titles without one). Only those not
  /// yet stored are fetched.
  Future<void> setWork(List<TmdbKey> wanted, List<TitleSearch> searches);

  /// Pauses the background fetch for [pause], or lets it run (null).
  /// Lookups still work while paused.
  Future<void> setPause(TmdbPause? pause);

  /// Title [key] from the store, fetched now when missing (or refreshed
  /// in the background when old). Null when TMDB has none or it can't be
  /// fetched.
  Future<TmdbTitle?> title(TmdbKey key);

  /// The title [search] finds, searching now when it hasn't been yet.
  Future<TmdbKey?> resolve(TitleSearch search);

  /// Season [number] of series [tvId]; refreshed when [ongoing] and old.
  Future<TmdbSeason?> season(int tvId, int number, {bool ongoing = false});

  Future<TmdbPerson?> person(int id);

  /// Every stored title search outcome.
  Future<Map<(TmdbKind, String), TitleMatch>> matches();

  Future<Set<TmdbKey>> removedLinks();

  /// The poster and backdrop of every stored title.
  Future<List<TmdbArtwork>> artwork();

  /// Marks the title search [key] as a wrong match.
  Future<void> removeMatch(TmdbKind kind, String key);

  /// Stops using TMDB title [key] for provider titles with that id.
  Future<void> removeLink(TmdbKey key);

  Future<int> removedCount();

  /// Forgets every removed match and link.
  Future<void> allowMatchingAgain();

  /// The genre names of every stored title.
  Future<Map<TmdbKey, List<String>>> genres();

  /// The stored trending list.
  Future<TmdbTrendingList> trending();

  /// Fetches this week's trending movies and series and stores them in
  /// place of the old list, which is kept when any page fails. Throws
  /// [TmdbException].
  Future<TmdbTrendingList> refreshTrending();

  Future<void> close();
}

/// [TmdbBackend] working in the calling isolate: keeps the store filled
/// for the catalogues' titles, a few requests at a time (the client's
/// [RateLimiter] sets the pace).
class TmdbSync implements TmdbBackend {
  TmdbSync({
    required TmdbStore store,
    required TmdbApi api,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    this.workers = tmdbMaxInFlight,
  }) : _store = store,
       _api = api,
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  /// Titles TMDB didn't have, and searches without a match, are tried
  /// again after this.
  static const retryMissingAfter = Duration(days: 30);

  /// Titles older than this are fetched again when opened.
  static const refreshTitleAfter = Duration(days: 30);

  /// Seasons of ongoing series older than this are fetched again.
  static const refreshSeasonAfter = Duration(days: 7);
  static const refreshPersonAfter = Duration(days: 30);

  /// How long to wait for the network to come back before trying again.
  static const networkRetry = Duration(seconds: 30);

  /// A title is skipped for this run after this many failed attempts.
  static const maxAttempts = 3;

  /// Pages of the trending list fetched per kind (20 titles each).
  static const trendingPages = 3;

  final TmdbStore _store;
  final TmdbApi _api;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final int workers;

  final _events = StreamController<TmdbEvent>.broadcast();
  final _ids = ListQueue<TmdbKey>();
  final _searches = ListQueue<TitleSearch>();
  final _inFlight = <Object>{};
  final _attempts = <Object, int>{};
  final _fetching = <TmdbKey, Future<TmdbTitle?>>{};
  final _resolving = <TitleSearch, Future<TmdbKey?>>{};

  late final Map<(TmdbKind, String), TitleMatch> _matches = _store.matches();
  late final Set<TmdbKey> _removed = _store.removedLinks();

  TmdbPause? _pause;
  bool _keyRejected = false;
  DateTime? _networkUntil;
  int _total = 0;
  var _started = false;
  var _closed = false;
  Completer<void>? _wake;

  /// Null until first reported, so the first report always goes out.
  TmdbProgress? _progress;

  @override
  Stream<TmdbEvent> get events => _events.stream;

  TmdbProgress get progress => _progress ?? TmdbProgress.none;

  @override
  Future<void> setWork(List<TmdbKey> wanted, List<TitleSearch> searches) async {
    final cutoff = _now().subtract(retryMissingAfter);
    final known = _store.fetchedTitles(notFoundSince: cutoff);
    final ids = LinkedHashSet<TmdbKey>.of(
      wanted.where((k) => !_removed.contains(k)),
    );
    final active = LinkedHashSet<TitleSearch>.of(
      searches.where(
        (s) => _matches[(s.kind, s.key)]?.outcome != MatchOutcome.removed,
      ),
    );
    _total = ids.length + active.length;
    _ids
      ..clear()
      ..addAll(
        ids.where((k) => !known.containsKey(k) && !_inFlight.contains(k)),
      );
    _searches
      ..clear()
      ..addAll(
        active.where(
          (s) => !_searchDone(s, known, cutoff) && !_inFlight.contains(s),
        ),
      );
    _attempts.clear();
    _keyRejected = false;
    if (!_started) {
      _started = true;
      for (var i = 0; i < workers; i++) {
        unawaited(_work());
      }
    }
    _report();
    _wakeUp();
  }

  bool _searchDone(
    TitleSearch s,
    Map<TmdbKey, DateTime> known,
    DateTime cutoff,
  ) => switch (_matches[(s.kind, s.key)]) {
    TitleMatch(outcome: MatchOutcome.matched, :final tmdbId?) =>
      known.containsKey(TmdbKey(s.kind, tmdbId)),
    TitleMatch(outcome: MatchOutcome.noMatch, :final at) => at.isAfter(cutoff),
    TitleMatch(outcome: MatchOutcome.removed) => true,
    _ => false,
  };

  @override
  Future<void> setPause(TmdbPause? pause) async {
    _pause = pause;
    _report();
    _wakeUp();
  }

  void _wakeUp() {
    final wake = _wake;
    _wake = null;
    wake?.complete();
  }

  TmdbSyncState get _state {
    if (_keyRejected) return TmdbSyncState.keyRejected;
    final pending = _ids.length + _searches.length + _inFlight.length;
    if (pending == 0) return TmdbSyncState.upToDate;
    if (_pause == TmdbPause.user) return TmdbSyncState.paused;
    if (_pause == TmdbPause.playback) return TmdbSyncState.pausedForPlayback;
    if (_networkUntil case final until? when until.isAfter(_now())) {
      return TmdbSyncState.waitingForNetwork;
    }
    return TmdbSyncState.running;
  }

  void _report() {
    final pending = _ids.length + _searches.length + _inFlight.length;
    final progress = TmdbProgress(
      (_total - pending).clamp(0, _total),
      _total,
      _state,
    );
    if (progress == _progress) return;
    _progress = progress;
    if (!_events.isClosed) _events.add(TmdbProgressEvent(progress));
  }

  /// One of [workers] loops taking titles off the queues.
  Future<void> _work() async {
    while (!_closed) {
      if (_networkUntil case final until? when until.isAfter(_now())) {
        await _sleep(until.difference(_now()));
        _report();
        continue;
      }
      final Object? item = _pause != null || _keyRejected
          ? null
          : _ids.isNotEmpty
          ? _ids.removeFirst()
          : _searches.isNotEmpty
          ? _searches.removeFirst()
          : null;
      if (item == null) {
        await (_wake ??= Completer<void>()).future;
        continue;
      }
      _inFlight.add(item);
      try {
        switch (item) {
          case TmdbKey key:
            await _fetchTitle(key, background: true);
          case TitleSearch search:
            await _resolve(search, background: true);
        }
        _attempts.remove(item);
      } on TmdbException catch (e) {
        _failed(item, e);
      } finally {
        _inFlight.remove(item);
        _report();
      }
    }
  }

  void _failed(Object item, TmdbException e) {
    switch (e.failure) {
      case TmdbFailure.unauthorized:
        _keyRejected = true;
        _requeue(item, first: true);
      case TmdbFailure.network:
        _networkUntil = _now().add(networkRetry);
        _requeue(item, first: true);
      case _:
        final attempts = _attempts[item] = (_attempts[item] ?? 0) + 1;
        // Left for the next run (restart or playlist refresh).
        if (attempts < maxAttempts) _requeue(item, first: false);
    }
  }

  void _requeue(Object item, {required bool first}) {
    switch (item) {
      case TmdbKey key:
        first ? _ids.addFirst(key) : _ids.addLast(key);
      case TitleSearch search:
        first ? _searches.addFirst(search) : _searches.addLast(search);
    }
  }

  Future<TmdbTitle?> _fetchTitle(TmdbKey key, {bool background = false}) =>
      _fetching[key] ??= _fetchTitleNow(key, background: background)
          .whenComplete(() {
            // A block body: returning the removed future would make it wait
            // for itself.
            _fetching.remove(key);
          });

  Future<TmdbTitle?> _fetchTitleNow(
    TmdbKey key, {
    required bool background,
  }) async {
    _ids.remove(key);
    try {
      final title = await _api.title(key);
      _store.putTitle(title);
      _emit(
        TmdbArtworkEvent([
          (key: key, poster: title.posterPath, backdrop: title.backdropPath),
        ]),
      );
      _emit(
        TmdbGenresEvent({
          key: [for (final g in title.genres) g.name]..sort(),
        }),
      );
      return title;
    } on TmdbException catch (e) {
      if (e.failure == TmdbFailure.notFound) {
        _store.putNotFound(key, _now());
        return null;
      }
      if (background) rethrow;
      return null;
    }
  }

  void _emit(TmdbEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<TmdbTitle?> title(TmdbKey key) async {
    final stored = _store.title(key);
    if (stored != null) {
      if (_now().difference(stored.fetchedAt) > refreshTitleAfter) {
        unawaited(
          _fetchTitle(key).then((t) {
            if (t != null) _emit(TmdbTitleEvent(t));
          }),
        );
      }
      return stored;
    }
    final known = _store.fetchedTitles(
      notFoundSince: _now().subtract(retryMissingAfter),
    );
    if (known.containsKey(key)) return null;
    final title = await _fetchTitle(key);
    _report();
    return title;
  }

  Future<TmdbKey?> _resolve(TitleSearch s, {bool background = false}) =>
      _resolving[s] ??= _resolveNow(s, background: background).whenComplete(() {
        _resolving.remove(s);
      });

  Future<TmdbKey?> _resolveNow(
    TitleSearch s, {
    required bool background,
  }) async {
    _searches.remove(s);
    final known = _matches[(s.kind, s.key)];
    final now = _now();
    switch (known) {
      case TitleMatch(outcome: MatchOutcome.removed):
        return null;
      case TitleMatch(outcome: MatchOutcome.matched, :final tmdbId?):
        final key = TmdbKey(s.kind, tmdbId);
        if (_store.title(key) == null) {
          await (background ? _fetchTitle(key, background: true) : title(key));
        }
        return key;
      case TitleMatch(outcome: MatchOutcome.noMatch, :final at)
          when now.difference(at) < retryMissingAfter:
        return null;
      case _:
    }
    try {
      var pick = pickMatch(
        s.title,
        s.year,
        await _api.search(s.kind, s.title, year: s.year),
      );
      // TMDB's year filter is exact; release years often differ by one.
      if (pick == null && s.year != null) {
        pick = pickMatch(s.title, s.year, await _api.search(s.kind, s.title));
      }
      final match = pick == null
          ? TitleMatch(MatchOutcome.noMatch, now)
          : TitleMatch(MatchOutcome.matched, now, pick.key.id);
      _store.putMatch(s.kind, s.key, match);
      _matches[(s.kind, s.key)] = match;
      if (pick != null) {
        await (background
            ? _fetchTitle(pick.key, background: true)
            : _fetchTitle(pick.key));
      }
      _emit(TmdbMatchEvent(s.kind, s.key, match));
      return pick?.key;
    } on TmdbException {
      if (background) rethrow;
      return null;
    }
  }

  @override
  Future<TmdbKey?> resolve(TitleSearch search) async {
    final key = await _resolve(search);
    _report();
    return key;
  }

  @override
  Future<TmdbSeason?> season(
    int tvId,
    int number, {
    bool ongoing = false,
  }) async {
    final stored = _store.season(tvId, number);
    if (stored != null &&
        !(ongoing &&
            _now().difference(stored.fetchedAt) > refreshSeasonAfter)) {
      return stored;
    }
    try {
      final season = await _api.season(tvId, number);
      _store.putSeason(season);
      return season;
    } on TmdbException {
      return stored;
    }
  }

  @override
  Future<TmdbPerson?> person(int id) async {
    final stored = _store.person(id);
    if (stored != null &&
        _now().difference(stored.fetchedAt) <= refreshPersonAfter) {
      return stored;
    }
    try {
      final person = await _api.person(id);
      _store.putPerson(person);
      return person;
    } on TmdbException {
      return stored;
    }
  }

  @override
  Future<Map<(TmdbKind, String), TitleMatch>> matches() async =>
      Map.of(_matches);

  @override
  Future<Set<TmdbKey>> removedLinks() async => Set.of(_removed);

  @override
  Future<List<TmdbArtwork>> artwork() async => _store.artwork();

  @override
  Future<void> removeMatch(TmdbKind kind, String key) async {
    final match = TitleMatch(MatchOutcome.removed, _now());
    _store.putMatch(kind, key, match);
    _matches[(kind, key)] = match;
    _emit(TmdbMatchEvent(kind, key, match));
  }

  @override
  Future<void> removeLink(TmdbKey key) async {
    _store.removeLink(key, _now());
    _removed.add(key);
    _ids.remove(key);
    _report();
  }

  @override
  Future<int> removedCount() async => _store.removedCount();

  @override
  Future<void> allowMatchingAgain() async {
    _store.allowMatchingAgain();
    _removed.clear();
    _matches.removeWhere((_, m) => m.outcome == MatchOutcome.removed);
  }

  @override
  Future<Map<TmdbKey, List<String>>> genres() async => _store.genreNames();

  @override
  Future<TmdbTrendingList> trending() async => _store.trending();

  @override
  Future<TmdbTrendingList> refreshTrending() async {
    final titles = <TmdbTrending>[];
    for (final kind in TmdbKind.values) {
      for (var page = 1; page <= trendingPages; page++) {
        titles.addAll(await _api.trending(kind, page: page));
      }
    }
    _store.putTrending(titles, _now());
    return _store.trending();
  }

  @override
  Future<void> close() async {
    _closed = true;
    _wakeUp();
    await _events.close();
  }
}
