import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;

import 'package:http/http.dart' as http;

import '../util/json.dart';
import 'rate_limiter.dart';
import 'tmdb_credential.dart';
import 'tmdb_models.dart';

/// What went wrong talking to TMDB.
enum TmdbFailure {
  /// TMDB didn't accept the key (HTTP 401).
  unauthorized,

  /// TMDB couldn't be reached or didn't answer in time.
  network,

  /// TMDB kept asking to slow down (HTTP 429).
  rateLimited,

  /// No such title, season or person (HTTP 404).
  notFound,

  /// TMDB's server failed (HTTP 5xx) or sent something unreadable.
  server,

  /// Another refusal (HTTP 4xx).
  refused,
}

/// A TMDB request failed. [message] never contains the address or the key.
class TmdbException implements Exception {
  const TmdbException(this.failure, this.message);

  final TmdbFailure failure;
  final String message;

  @override
  String toString() => 'TmdbException(${failure.name}): $message';
}

/// The requests the app makes to TMDB. [TmdbClient] in the app, fakes in
/// tests.
abstract interface class TmdbApi {
  /// A movie or series with everything the app shows appended.
  Future<TmdbTitle> title(TmdbKey key);

  Future<TmdbSeason> season(int tvId, int number);

  Future<TmdbPerson> person(int id);

  /// The first page of results for [query], filtered by [year] when given.
  Future<List<TmdbSearchResult>> search(
    TmdbKind kind,
    String query, {
    int? year,
  });
}

/// [TmdbApi] over HTTP, in English (`en-US`), through a [RateLimiter].
///
/// Rate limits (HTTP 429) are waited out (`Retry-After`, else exponential
/// back-off) and so are server and network errors, a few times, before
/// failing.
class TmdbClient implements TmdbApi {
  TmdbClient(
    this._client,
    this._credential, {
    RateLimiter? limiter,
    this.timeout = const Duration(seconds: 20),
    this.maxRetries = 3,
    this.maxRateLimitRetries = 8,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _limiter = limiter ?? RateLimiter(now: now, sleep: sleep),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  static const _host = 'api.themoviedb.org';
  static const language = 'en-US';

  final http.Client _client;
  final TmdbCredential _credential;
  final RateLimiter _limiter;
  final Duration timeout;

  /// Retries after a network or server error.
  final int maxRetries;

  /// Retries after HTTP 429.
  final int maxRateLimitRetries;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  /// Checks the key with `/authentication`. Throws [TmdbException].
  Future<void> testConnection() => _get('/3/authentication', const {});

  @override
  Future<TmdbTitle> title(TmdbKey key) async {
    final json = await _get('/3/${key.kind.name}/${key.id}', {
      'append_to_response': switch (key.kind) {
        TmdbKind.movie => 'credits,recommendations,images',
        TmdbKind.tv => 'credits,recommendations,external_ids,images',
      },
      'include_image_language': 'null,en',
    });
    return TmdbTitle.fromJson(key.kind, json, fetchedAt: _now()) ??
        (throw const TmdbException(TmdbFailure.server, 'No id in answer'));
  }

  @override
  Future<TmdbSeason> season(int tvId, int number) async => TmdbSeason.fromJson(
    tvId,
    number,
    await _get('/3/tv/$tvId/season/$number', const {}),
    fetchedAt: _now(),
  );

  @override
  Future<TmdbPerson> person(int id) async =>
      TmdbPerson.fromJson(
        await _get('/3/person/$id', {'append_to_response': 'combined_credits'}),
        fetchedAt: _now(),
      ) ??
      (throw const TmdbException(TmdbFailure.server, 'No id in answer'));

  @override
  Future<List<TmdbSearchResult>> search(
    TmdbKind kind,
    String query, {
    int? year,
  }) async {
    final json = await _get('/3/search/${kind.name}', {
      'query': query,
      'include_adult': 'false',
      if (year != null)
        switch (kind) {
          TmdbKind.movie => 'year',
          TmdbKind.tv => 'first_air_date_year',
        }: '$year',
    });
    return [
      for (final r in readList(json['results']))
        if (readMap(r) case final r?) ?TmdbSearchResult.fromJson(kind, r),
    ];
  }

  Future<Map<String, Object?>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.https(_host, path, {
      'language': language,
      ...query,
      ..._credential.query,
    });
    var failures = 0;
    var limited = 0;
    while (true) {
      final http.Response response;
      try {
        response = await _limiter.run(
          () => _client.get(uri, headers: _headers).timeout(timeout),
        );
      } catch (e) {
        // Client exceptions quote the address, which may hold the key:
        // keep only the type.
        if (failures >= maxRetries) {
          throw TmdbException(
            TmdbFailure.network,
            e is TimeoutException
                ? 'No answer in time'
                : 'Could not connect (${e.runtimeType})',
          );
        }
        await _sleep(exponentialBackOff(failures++));
        continue;
      }
      final status = response.statusCode;
      if (status == 429) {
        if (limited >= maxRateLimitRetries) {
          throw const TmdbException(TmdbFailure.rateLimited, 'HTTP 429');
        }
        _limiter.backOff(
          _retryAfter(response.headers['retry-after']) ??
              exponentialBackOff(limited),
        );
        limited++;
        continue;
      }
      if (status >= 500) {
        if (failures >= maxRetries) {
          throw TmdbException(TmdbFailure.server, 'HTTP $status');
        }
        await _sleep(exponentialBackOff(failures++));
        continue;
      }
      if (status == 401) {
        throw const TmdbException(TmdbFailure.unauthorized, 'HTTP 401');
      }
      if (status == 404) {
        throw const TmdbException(TmdbFailure.notFound, 'HTTP 404');
      }
      if (status != 200) {
        throw TmdbException(TmdbFailure.refused, 'HTTP $status');
      }
      try {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json is Map) return json.cast<String, Object?>();
      } on FormatException {
        // Falls through.
      }
      throw const TmdbException(TmdbFailure.server, 'Unreadable answer');
    }
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    ..._credential.headers,
  };

  /// A `Retry-After` header: seconds, or an HTTP date.
  Duration? _retryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds.clamp(0, 3600));
    try {
      final wait = HttpDate.parse(value).difference(_now());
      return wait.isNegative ? Duration.zero : wait;
    } on FormatException {
      return null;
    } on HttpException {
      return null;
    }
  }
}
