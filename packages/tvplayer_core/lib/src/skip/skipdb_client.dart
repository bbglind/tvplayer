import '../tmdb/rate_limiter.dart';
import '../util/json.dart';
import 'skip_api.dart';
import 'skip_segments.dart';

/// Lowest SkipDB confidence (0–1) taken as real.
const skipDbMinConfidence = 0.5;

/// SkipDB (skipdb.tv): community intro, recap and credits ("outro") times
/// by IMDb id, season and episode. Reading needs no key; the episode's
/// length is sent so SkipDB shifts its times to this copy.
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
        if (query.duration case final d?)
          'duration': (d.inMilliseconds / 1000).toStringAsFixed(1),
      }),
    );
    return json == null ? SkipSegments.none : parse(json);
  }

  /// The `segments` of an answer; null entries, unmatched ones
  /// (`out-of-range`) and ones below [skipDbMinConfidence] are left out.
  static SkipSegments parse(Map<String, Object?> json) {
    final segments = readMap(json['segments']);
    SkipRange? range(String type) {
      final s = readMap(segments?[type]);
      if (s == null || s['match'] == 'out-of-range') return null;
      if (s['confidence'] case final num c when c < skipDbMinConfidence) {
        return null;
      }
      final start = msOf(s['start_ms']);
      final end = msOf(s['end_ms']);
      if (start == null || end == null || end <= start) return null;
      return SkipRange(start, end);
    }

    return SkipSegments(
      intro: range('intro'),
      recap: range('recap'),
      credits: range('outro'),
    );
  }
}
