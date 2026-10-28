import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/service_credentials.dart';
import 'providers.dart';
import 'tmdb.dart';

/// Whether SkipDB / TheIntroDB are on in Settings › Services. Off until
/// the settings are read, so nothing is asked before.
final skipDbEnabledProvider = Provider<bool>(
  (ref) => ref.watch(
    appSettingsProvider.select((s) => s.value?.skipDbEnabled ?? false),
  ),
);

final introDbEnabledProvider = Provider<bool>(
  (ref) => ref.watch(
    appSettingsProvider.select((s) => s.value?.introDbEnabled ?? false),
  ),
);

/// The user's own TheIntroDB key (optional); null when none is saved.
final introDbKeyProvider = AsyncNotifierProvider<IntroDbKeyNotifier, String?>(
  IntroDbKeyNotifier.new,
);

class IntroDbKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() =>
      ref.watch(serviceCredentialsProvider).read(MetadataService.introDb);

  /// Saves the key in [text]. Throws [FormatException] when it can't be a
  /// key, or ProviderStorageException.
  Future<void> save(String text) async {
    final key = text.trim();
    if (key.isEmpty || key.contains(RegExp(r'\s'))) {
      throw const FormatException("That doesn't look like a TheIntroDB key.");
    }
    await ref
        .read(serviceCredentialsProvider)
        .write(MetadataService.introDb, key);
    state = AsyncData(key);
  }

  Future<void> remove() async {
    await ref.read(serviceCredentialsProvider).delete(MetadataService.introDb);
    state = const AsyncData(null);
  }
}

/// SkipDB over HTTP. Overridden in tests.
final skipDbApiProvider = Provider<SkipApi>(
  (ref) => SkipDbClient(ref.watch(httpClientProvider)),
);

/// TheIntroDB over HTTP, with the user's key when one is saved; a new key
/// starts a new client (and allowance). Overridden in tests.
final introDbApiProvider = Provider<SkipApi>(
  (ref) => IntroDbClient(
    ref.watch(httpClientProvider),
    key: ref.watch(introDbKeyProvider).value,
  ),
);

/// SkipDB's answers on disk, in the app support directory. Overridden in
/// tests.
final skipStoreProvider = FutureProvider<SkipStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  final store = SkipStore.open('${dir.path}/skip.sqlite');
  ref.onDispose(store.close);
  return store;
});

/// Checks a service ("Test connection"): null when it answers, else what
/// failed. Overridden in tests.
typedef SkipConnectionTester = Future<SkipFailure?> Function(
  SkipService service, {
  String? key,
});

enum SkipService { skipDb, introDb }

final skipConnectionTesterProvider = Provider<SkipConnectionTester>((ref) {
  final client = ref.watch(httpClientProvider);
  return (service, {key}) async {
    final SkipApi api = switch (service) {
      SkipService.skipDb => SkipDbClient(
        client,
        maxRetries: 0,
        maxRateLimitRetries: 0,
      ),
      SkipService.introDb => IntroDbClient(
        client,
        key: key,
        maxRetries: 0,
        maxRateLimitRetries: 0,
      ),
    };
    try {
      await api.lookup(SkipQuery.test);
      return null;
    } on SkipException catch (e) {
      return e.failure;
    }
  };
});

/// The result of "Test connection" in words.
String describeSkipTest(String name, SkipFailure? failure) => switch (failure) {
  null => 'Connected to $name.',
  SkipFailure.unauthorized =>
    "$name didn't accept this key. Check that you copied all of it.",
  SkipFailure.network =>
    "Couldn't reach $name. Check your internet connection.",
  SkipFailure.rateLimited || SkipFailure.limitReached =>
    '$name is busy or the daily limit is reached. '
        'Try again later.',
  SkipFailure.server || SkipFailure.refused =>
    "$name couldn't answer. "
        'Try again later.',
};

/// Finds the intro, recap and credits times of episodes.
final skipLookupProvider = Provider<SkipLookup>((ref) {
  final lookup = SkipLookup(ref);
  // Switched off: what TheIntroDB sent is forgotten too.
  ref.listen(introDbEnabledProvider, (_, on) {
    if (!on) lookup.forgetIntroDb();
  });
  // TMDB switched on or off: the ids may come from elsewhere now.
  ref.listen(tmdbBackendProvider, (_, _) => lookup.forgetIds());
  return lookup;
});

/// The series' ids the services know it by.
typedef SkipIds = ({String? imdbId, int? tmdbId});

/// Intro, recap and credits times of an episode: SkipDB first (kept on
/// disk), then TheIntroDB for the types SkipDB doesn't have (kept in
/// memory for this session only, as its terms ask). TheIntroDB's times
/// are moved to this copy's length from the length of its copy, else of
/// SkipDB's ([SkipSegments.fittedTo]); SkipDB's already are.
///
/// The series is asked for by its IMDb id (SkipDB needs one) and TMDB id,
/// from its TMDB title when TMDB is on, else from the provider's
/// details. Without either, or with both services off, nothing is asked.
/// Downloaded episodes only use what SkipDB's answer on disk has. Errors
/// are only logged by type; the player then has no times.
class SkipLookup {
  SkipLookup(this._ref);

  final Ref _ref;

  /// TheIntroDB's answers this session, oldest first.
  final _introDb = <String, SkipSegments>{};
  static const _introDbKept = 500;

  final _ids = <String, Future<SkipIds?>>{};
  final _inFlight = <String, Future<SkipSegments>>{};

  void forgetIntroDb() => _introDb.clear();

  void forgetIds() => _ids.clear();

  /// The times of [episode] of [series], for a copy of [duration] (sent
  /// to the services, which match their times to it). [downloaded]: the
  /// episode plays from its download; nothing is asked online.
  Future<SkipSegments> lookup(
    Series series,
    Episode episode, {
    Duration? duration,
    bool downloaded = false,
  }) {
    final key = [
      series.seriesId,
      series.name,
      episode.season,
      episode.episodeNumber,
      duration?.inSeconds,
      downloaded,
    ].join('|');
    return _inFlight[key] ??= _lookup(series, episode, duration, downloaded)
        .whenComplete(() {
          // Not `=> remove(key)`: that returns this future, and whenComplete
          // would wait for itself.
          _inFlight.remove(key);
        });
  }

  Future<SkipSegments> _lookup(
    Series series,
    Episode episode,
    Duration? duration,
    bool downloaded,
  ) async {
    final skipDbOn = _ref.read(skipDbEnabledProvider);
    final introDbOn = _ref.read(introDbEnabledProvider) && !downloaded;
    if (!skipDbOn && !introDbOn) return SkipSegments.none;
    final ids = await idsOf(series);
    if (ids == null) return SkipSegments.none;
    final query = SkipQuery(
      imdbId: ids.imdbId,
      tmdbId: ids.tmdbId,
      season: episode.season,
      episode: episode.episodeNumber,
      duration: duration,
    );
    var segments = SkipSegments.none;
    // SkipDB needs an IMDb id; without one only TheIntroDB is asked.
    if (skipDbOn && query.imdbId != null) {
      segments = await _fromSkipDb(query, downloaded);
    }
    // Asked again in case it was switched off meanwhile.
    if (introDbOn &&
        _ref.read(introDbEnabledProvider) &&
        segments.missing.isNotEmpty) {
      final introDb = await _fromIntroDb(query);
      segments = segments.fillFrom(
        duration == null
            ? introDb
            : introDb.fittedTo(
                duration,
                from: introDb.reference ?? segments.reference,
              ),
      );
    }
    return segments;
  }

  /// Asks SkipDB for [episode] of [series] (when it is on) and keeps the
  /// answer, e.g. for a download, to be played offline.
  Future<void> storeSkipDb(Series series, Episode episode) async {
    if (!_ref.read(skipDbEnabledProvider)) return;
    final ids = await idsOf(series);
    final imdb = ids?.imdbId;
    if (imdb == null) return;
    await _fromSkipDb(
      SkipQuery(
        imdbId: imdb,
        season: episode.season,
        episode: episode.episodeNumber,
        duration: episode.duration,
      ),
      false,
    );
  }

  Future<SkipSegments> _fromSkipDb(SkipQuery q, bool downloaded) async {
    SkipStore? store;
    try {
      store = await _ref.read(skipStoreProvider.future);
    } catch (e) {
      debugPrint('Skip store: ${e.runtimeType}');
    }
    final now = DateTime.now().toUtc();
    final imdb = q.imdbId!;
    final stored = store?.get(
      imdb,
      q.season,
      q.episode,
      duration: q.duration,
      now: now,
      anyAge: downloaded,
    );
    if (stored != null || downloaded) return stored ?? SkipSegments.none;
    try {
      final segments = await _ref.read(skipDbApiProvider).lookup(q);
      // Times left out as unusable aren't "nothing known": ask again.
      if (segments.isEmpty && segments.incomplete) return segments;
      store?.put(
        imdb,
        q.season,
        q.episode,
        segments,
        duration: q.duration,
        at: now,
      );
      return segments;
    } on SkipException catch (e) {
      debugPrint('SkipDB: ${e.failure.name}');
      return SkipSegments.none;
    }
  }

  Future<SkipSegments> _fromIntroDb(SkipQuery q) async {
    final key = '${q.tmdbId ?? q.imdbId}|${q.season}|${q.episode}';
    if (_introDb.remove(key) case final kept?) {
      _introDb[key] = kept;
      return kept;
    }
    try {
      final segments = await _ref.read(introDbApiProvider).lookup(q);
      _introDb[key] = segments;
      if (_introDb.length > _introDbKept) _introDb.remove(_introDb.keys.first);
      return segments;
    } on SkipException catch (e) {
      debugPrint('TheIntroDB: ${e.failure.name}');
      return SkipSegments.none;
    }
  }

  /// The IMDb and TMDB ids of [series]: its TMDB title's (TMDB on), else
  /// the provider's; null without either.
  Future<SkipIds?> idsOf(Series series) =>
      _ids['${series.seriesId}|${series.name}'] ??= _findIds(series);

  Future<SkipIds?> _findIds(Series series) async {
    var imdb = imdbIdOrNull(series.imdbId);
    var tmdb = TmdbKey.fromProvider(TmdbKind.tv, series.tmdbId)?.id;
    TmdbBackend? backend;
    try {
      backend = await _ref.read(tmdbBackendProvider.future);
    } catch (e) {
      debugPrint('Skip ids: ${e.runtimeType}');
    }
    final state = _ref.read(tmdbMatchesProvider);
    if (backend != null && state.loaded) {
      final link = await findTmdbLink(
        seriesTmdbItem(series),
        state: state,
        tags: _ref.read(providerTagsProvider),
        backend: backend,
      );
      if (link == null) {
        // The user removed the provider's link: it is wrong.
        if (tmdb != null &&
            state.removed.contains(TmdbKey(TmdbKind.tv, tmdb))) {
          tmdb = null;
          imdb = null;
        }
      } else {
        tmdb = link.key.id;
        try {
          imdb = imdbIdOrNull((await backend.title(link.key))?.imdbId) ?? imdb;
        } catch (e) {
          debugPrint('Skip ids: ${e.runtimeType}');
        }
      }
    }
    if (imdb == null && tmdb == null) {
      // Not kept: TMDB may be switched on or find it later.
      _ids.remove('${series.seriesId}|${series.name}');
      return null;
    }
    return (imdbId: imdb, tmdbId: tmdb);
  }
}
