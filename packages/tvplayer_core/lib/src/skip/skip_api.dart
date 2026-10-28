import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate, HttpException;

import 'package:http/http.dart' as http;

import '../tmdb/rate_limiter.dart';
import 'skip_segments.dart';

/// The episode to look up: the series by its IMDb and/or TMDB id, the
/// season and episode number, and the length of the copy that plays
/// (so the services can match or shift their times to it).
final class SkipQuery {
  const SkipQuery({
    this.imdbId,
    this.tmdbId,
    required this.season,
    required this.episode,
    this.duration,
  });

  final String? imdbId;
  final int? tmdbId;
  final int season;
  final int episode;
  final Duration? duration;

  /// A public example title ("Test connection"): S01E01 of the series in
  /// SkipDB's API documentation.
  static const test = SkipQuery(
    imdbId: 'tt0903747',
    tmdbId: 1396,
    season: 1,
    episode: 1,
  );

  /// Never the ids: [toString] can end up in logs.
  @override
  String toString() => 'SkipQuery(<redacted>)';
}

/// What went wrong asking a skip-times service.
enum SkipFailure {
  /// The service didn't accept the key (HTTP 401/403).
  unauthorized,

  /// It couldn't be reached or didn't answer in time.
  network,

  /// It kept asking to slow down (HTTP 429).
  rateLimited,

  /// The daily allowance is used up; no more requests until it resets.
  limitReached,

  /// Its server failed (HTTP 5xx) or sent something unreadable.
  server,

  /// Another refusal (HTTP 4xx).
  refused,
}

/// A skip-times request failed. [message] never contains the address,
/// the ids or the key.
class SkipException implements Exception {
  const SkipException(this.failure, this.message);

  final SkipFailure failure;
  final String message;

  @override
  String toString() => 'SkipException(${failure.name}): $message';
}

/// A service with intro, recap and credits times. [SkipSegments.none]
/// when it has none for the episode; throws [SkipException].
abstract interface class SkipApi {
  Future<SkipSegments> lookup(SkipQuery query);
}

/// The HTTP part shared by the clients: one rate-limited GET with retries
/// after HTTP 429 (`Retry-After`) and a network or server error.
abstract base class SkipHttpClient implements SkipApi {
  SkipHttpClient(
    this._client, {
    required RateLimiter limiter,
    this.timeout = const Duration(seconds: 10),
    this.maxRetries = 1,
    this.maxRateLimitRetries = 2,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _limiter = limiter,
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  final http.Client _client;
  final RateLimiter _limiter;
  final Duration timeout;
  final int maxRetries;
  final int maxRateLimitRetries;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  /// Statuses that mean "nothing known about this episode".
  Set<int> get noDataStatuses => const {404};

  /// Called with each HTTP 429 before it is waited out; throws to stop.
  void onRateLimited(http.Response response) {}

  /// The decoded answer, or null for one of [noDataStatuses].
  Future<Map<String, Object?>?> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    var failures = 0;
    var limited = 0;
    while (true) {
      final http.Response response;
      try {
        response = await _limiter.run(
          () => _client
              .get(uri, headers: {'Accept': 'application/json', ...headers})
              .timeout(timeout),
        );
      } catch (e) {
        // Client exceptions quote the address: keep only the type.
        if (failures >= maxRetries) {
          throw SkipException(
            SkipFailure.network,
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
        onRateLimited(response);
        if (limited >= maxRateLimitRetries) {
          throw const SkipException(SkipFailure.rateLimited, 'HTTP 429');
        }
        _limiter.backOff(
          retryAfter(response.headers['retry-after']) ??
              exponentialBackOff(limited),
        );
        limited++;
        continue;
      }
      if (status >= 500) {
        if (failures >= maxRetries) {
          throw SkipException(SkipFailure.server, 'HTTP $status');
        }
        await _sleep(exponentialBackOff(failures++));
        continue;
      }
      if (noDataStatuses.contains(status)) return null;
      if (status == 401 || status == 403) {
        throw SkipException(SkipFailure.unauthorized, 'HTTP $status');
      }
      if (status != 200) {
        throw SkipException(SkipFailure.refused, 'HTTP $status');
      }
      try {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json is Map) return json.cast<String, Object?>();
      } on FormatException {
        // Falls through.
      }
      throw const SkipException(SkipFailure.server, 'Unreadable answer');
    }
  }

  /// A `Retry-After` header: seconds, or an HTTP date; at most an hour
  /// (a longer wait isn't worth holding a lookup for).
  Duration? retryAfter(String? value) {
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

  /// Never the key: [toString] can end up in logs.
  @override
  String toString() => '$runtimeType(<redacted>)';
}

/// A time in milliseconds from JSON, or null.
Duration? msOf(Object? value) => value is num && value.isFinite
    ? Duration(milliseconds: value.round())
    : null;

final _imdbId = RegExp(r'^tt\d{5,}$');

/// [value] when it is an IMDb title id (`tt` and digits), else null.
String? imdbIdOrNull(String? value) {
  final id = value?.trim();
  return id != null && _imdbId.hasMatch(id) ? id : null;
}
