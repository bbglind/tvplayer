import '../tmdb/rate_limiter.dart';
import '../util/json.dart';
import 'skip_api.dart';
import 'skip_segments.dart';

/// Lowest SkipDB confidence (0–1) taken as real.
const skipDbMinConfidence = 0.5;

/// SkipDB (skipdb.tv): community intro, recap and credits ("outro") times
/// by IMDb id, season and episode. Reading needs no key; the episode's
/// length is sent so SkipDB shifts its times to this copy. It only does
/// that for lengths close to its own; for others ("out-of-range") the
/// times are moved here ([SkipSegments.fittedTo]).
///
/// Its data is licensed under ODbL 1.0 and must be attributed (Settings ›
/// About).
final class SkipDbClient extends SkipHttpClient {
  SkipDbClient(
    super.client, {
    RateLimiter? limiter,
    super.timeout,
    super.maxRetries,
    super.maxRateLimitRetries,
    super.now,
    super.sleep,
  }) : super(
         // 120 a minute are allowed; a player needs far fewer.
         limiter:
             limiter ??
             RateLimiter(perSecond: 1, maxInFlight: 1, now: now, sleep: sleep),
       );

  static const _host = 'api.skipdb.tv';

  /// Without an IMDb id there is nothing to ask: [SkipSegments.none].
  @override
  Future<SkipSegments> lookup(SkipQuery query) async {
    final imdb = query.imdbId;
    if (imdb == null) return SkipSegments.none;
    final json = await getJson(
      Uri.https(_host, '/api/segments', {
        'imdb_id': imdb,
        'season': '${query.season}',
        'episode': '${query.episode}',
        if (query.duration case final d?) ...{
          'duration': (d.inMilliseconds / 1000).toStringAsFixed(1),
          'adjust': 'conservative',
        },
      }),
    );
    return json == null ? SkipSegments.none : parse(json, query.duration);
  }

  /// The `segments` of an answer for a copy of [duration]. Times SkipDB
  /// couldn't match to it (`out-of-range`, for its copy of [duration]
  /// minus `offset_ms`) are fitted to it; that length is the result's
  /// [SkipSegments.reference]. Null entries, ones below
  /// [skipDbMinConfidence], unusable ones and credits that end early
  /// ([SkipSegments.creditsEndEarly]) are left out
  /// ([SkipSegments.incomplete]).
  static SkipSegments parse(Map<String, Object?> json, Duration? duration) {
    final segments = readMap(json['segments']);
    var incomplete = false;
    Duration? reference;
    SkipRange? range(String type, {required bool outOfRange}) {
      final s = readMap(segments?[type]);
      if (s == null || (s['match'] == 'out-of-range') != outOfRange) {
        return null;
      }
      SkipRange? usable() {
        if (s['confidence'] case final num c when c < skipDbMinConfidence) {
          return null;
        }
        final start = msOf(s['start_ms']);
        final end = msOf(s['end_ms']);
        if (start == null || end == null || end <= start) return null;
        if (outOfRange) {
          final offset = msOf(s['offset_ms']);
          if (duration == null || offset == null) return null;
          reference ??= duration - offset;
        }
        return SkipRange(start, end);
      }

      final r = usable();
      if (r == null) incomplete = true;
      return r;
    }

    SkipSegments read({required bool outOfRange}) => SkipSegments(
      intro: range('intro', outOfRange: outOfRange),
      recap: range('recap', outOfRange: outOfRange),
      credits: range('outro', outOfRange: outOfRange),
    );

    final matched = read(outOfRange: false);
    final far = read(outOfRange: true);
    final fitted = duration == null
        ? far
        : far.fittedTo(duration, from: reference);
    final all = matched.fillFrom(fitted);
    // Left out here, TheIntroDB is asked for the credits instead.
    final early = duration != null && all.creditsEndEarly(duration);
    return SkipSegments(
      intro: all.intro,
      recap: all.recap,
      credits: early ? null : all.credits,
      reference: reference,
      incomplete: incomplete || early,
    );
  }
}
