import 'dart:convert';

import 'package:http/http.dart' as http;

import '../tmdb/rate_limiter.dart';
import '../util/json.dart';
import 'skip_api.dart';
import 'skip_segments.dart';

/// TheIntroDB (theintrodb.org): community intro, recap and credits times
/// by TMDB id (else IMDb id), season and episode; the episode's length
/// picks the matching release.
///
/// Its terms allow use from the user's own device only, and no lasting
/// copy: the app keeps its answers in memory for the session. An optional
/// key of the user's own (never one shipped with the app) raises the
/// daily limit.
final class IntroDbClient extends SkipHttpClient {
  IntroDbClient(
    super.client, {
    String? key,
    RateLimiter? limiter,
    super.timeout,
    super.maxRetries,
    super.maxRateLimitRetries,
    super.now,
    super.sleep,
  }) : _key = key,
       super(
         // 30 per 10 s are allowed without a key; stay well below.
         limiter:
             limiter ??
             RateLimiter(
               perSecond: 0.5,
               maxInFlight: 1,
               now: now,
               sleep: sleep,
             ),
       );

  static const _host = 'api.theintrodb.org';

  final String? _key;

  /// The daily allowance is used up: no more requests from this client.
  bool get exhausted => _exhausted;
  bool _exhausted = false;

  /// Series over their own daily allowance (by [_titleKey]).
  final _blockedTitles = <String>{};

  /// The series of the request in flight, for a per-title limit.
  String? _current;

  @override
  Set<int> get noDataStatuses => const {400, 404};

  @override
  void onRateLimited(http.Response response) {
    final code = switch (_decode(response.body)) {
      {'code': final String code} => code,
      _ => null,
    };
    switch (code) {
      case 'usage_limit_exceeded':
        _exhausted = true;
        throw const SkipException(SkipFailure.limitReached, 'Daily limit');
      case 'specific_media_usage_limit_exceeded':
        if (_current case final title?) _blockedTitles.add(title);
        throw const SkipException(SkipFailure.limitReached, 'Title limit');
    }
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  static String? _titleKey(SkipQuery q) => q.tmdbId != null
      ? 'tmdb:${q.tmdbId}'
      : q.imdbId != null
      ? 'imdb:${q.imdbId}'
      : null;

  /// Without a TMDB or IMDb id there is nothing to ask:
  /// [SkipSegments.none].
  @override
  Future<SkipSegments> lookup(SkipQuery query) async {
    final title = _titleKey(query);
    if (title == null) return SkipSegments.none;
    if (_exhausted || _blockedTitles.contains(title)) {
      throw const SkipException(SkipFailure.limitReached, 'Limit reached');
    }
    _current = title;
    final json = await getJson(
      Uri.https(_host, '/v4/media', {
        if (query.tmdbId case final id?)
          'tmdb_id': '$id'
        else
          'imdb_id': query.imdbId!,
        'season': '${query.season}',
        'episode': '${query.episode}',
        if (query.duration case final d?) 'duration_ms': '${d.inMilliseconds}',
      }),
      headers: {if (_key case final key?) 'Authorization': 'Bearer $key'},
    );
    return json == null ? SkipSegments.none : parse(json);
  }

  /// The first usable entry of each type. A null start is the beginning
  /// (intro, recap); a null end the end of the episode (credits). The
  /// length of TheIntroDB's copy (`group_duration_ms`), when sent, is the
  /// [SkipSegments.reference] the times are fitted from.
  static SkipSegments parse(Map<String, Object?> json) {
    SkipRange? first(String type, {required bool toEnd}) {
      for (final e in readList(json[type])) {
        final entry = readMap(e);
        if (entry == null) continue;
        final start = msOf(entry['start_ms']) ?? Duration.zero;
        final end = msOf(entry['end_ms']);
        if (end == null ? toEnd && start > Duration.zero : end > start) {
          return SkipRange(start, end);
        }
      }
      return null;
    }

    return SkipSegments(
      intro: first('intro', toEnd: false),
      recap: first('recap', toEnd: false),
      credits: first('credits', toEnd: true),
      reference: msOf(json['group_duration_ms']),
    );
  }
}
