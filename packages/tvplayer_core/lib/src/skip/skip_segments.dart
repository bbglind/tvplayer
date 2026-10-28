import '../util/json.dart';

/// The parts of an episode that can be skipped or that end it.
enum SkipType { intro, recap, credits }

/// A part of an episode, from [start] to [end]; a null [end] runs to the
/// end of the episode (credits).
final class SkipRange {
  const SkipRange(this.start, [this.end]);

  final Duration start;
  final Duration? end;

  /// [end], or [duration] when it runs to the end.
  Duration endIn(Duration duration) => end ?? duration;

  Map<String, Object?> toJson() => {
    'start': start.inMilliseconds,
    'end': ?end?.inMilliseconds,
  };

  static SkipRange? fromJson(Object? json) {
    final map = readMap(json);
    final start = readInt(map?['start']);
    if (start == null) return null;
    final end = readInt(map?['end']);
    return SkipRange(
      Duration(milliseconds: start),
      end == null ? null : Duration(milliseconds: end),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SkipRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SkipRange($start, $end)';
}

/// Shortest part that gets a button or starts the next episode.
const minSkipLength = Duration(seconds: 5);

/// Longest intro and recap taken as real (TheIntroDB's own limits).
const maxIntroLength = Duration(minutes: 3);
const maxRecapLength = Duration(minutes: 8);

/// Copies whose lengths differ by at most this much share their times
/// (SkipDB's own tolerance is about as much).
const skipFitTolerance = Duration(seconds: 15);

/// A copy shorter than the one the times are for by this ratio of the
/// lengths plays faster: film (23.976 fps) shown at 25 fps ("PAL
/// speed-up", 0.959), so all its times come that much earlier.
const palSpeedUpRatio = (min: 0.95, max: 0.965);

/// The intro, recap and credits times of one episode, as far as known.
final class SkipSegments {
  const SkipSegments({
    this.intro,
    this.recap,
    this.credits,
    this.reference,
    this.incomplete = false,
  });

  static const none = SkipSegments();

  final SkipRange? intro;
  final SkipRange? recap;
  final SkipRange? credits;

  /// The length of the copy the source's times were measured on, when
  /// known and not the one asked for (see [fittedTo]).
  final Duration? reference;

  /// Times in the answer were left out as unusable, so an empty answer
  /// doesn't mean "nothing known". Not stored, not compared.
  final bool incomplete;

  SkipRange? operator [](SkipType type) => switch (type) {
    SkipType.intro => intro,
    SkipType.recap => recap,
    SkipType.credits => credits,
  };

  bool get isEmpty => intro == null && recap == null && credits == null;

  /// The types without a time.
  Set<SkipType> get missing => {
    for (final t in SkipType.values)
      if (this[t] == null) t,
  };

  /// These times, with the ones missing taken from [other] (per type).
  SkipSegments fillFrom(SkipSegments other) => SkipSegments(
    intro: intro ?? other.intro,
    recap: recap ?? other.recap,
    credits: credits ?? other.credits,
    reference: reference ?? other.reference,
  );

  /// These times, measured on a copy of [from] (default [reference]),
  /// moved to a copy of [length]. Lengths within [skipFitTolerance]:
  /// unchanged. A sped-up copy ([palSpeedUpRatio]): every time scaled.
  /// Otherwise the copies are taken to differ at the end: intro and recap
  /// stay, the credits keep their distance from the end. The result has
  /// no [reference].
  SkipSegments fittedTo(Duration length, {Duration? from}) {
    final source = from ?? reference;
    if (source == null ||
        source <= Duration.zero ||
        (length - source).abs() <= skipFitTolerance) {
      return SkipSegments(intro: intro, recap: recap, credits: credits);
    }
    final ratio = length.inMicroseconds / source.inMicroseconds;
    if (ratio >= palSpeedUpRatio.min && ratio <= palSpeedUpRatio.max) {
      Duration scale(Duration d) => d * ratio;
      SkipRange? scaled(SkipRange? r) => r == null
          ? null
          : SkipRange(scale(r.start), r.end == null ? null : scale(r.end!));
      return SkipSegments(
        intro: scaled(intro),
        recap: scaled(recap),
        credits: scaled(credits),
      );
    }
    final shift = length - source;
    final c = credits;
    return SkipSegments(
      intro: intro,
      recap: recap,
      credits: c == null
          ? null
          : SkipRange(c.start + shift, c.end == null ? null : c.end! + shift),
    );
  }

  /// The times that make sense in an episode of [duration]: ends past the
  /// end are cut there; parts shorter than [minSkipLength], starting after
  /// the end, an intro longer than [maxIntroLength] or a recap longer than
  /// [maxRecapLength] are dropped, and so are credits that start in the
  /// first half (most likely wrong).
  SkipSegments sanitized(Duration duration) {
    SkipRange? check(SkipRange? r, {Duration? max, bool toEnd = false}) {
      if (r == null || r.start < Duration.zero || r.start >= duration) {
        return null;
      }
      final rawEnd = r.end;
      if (rawEnd == null && !toEnd) return null;
      final end = rawEnd == null || rawEnd > duration ? duration : rawEnd;
      final length = end - r.start;
      if (length < minSkipLength) return null;
      if (max != null && length > max) return null;
      return SkipRange(r.start, toEnd ? null : end);
    }

    final credits = check(this.credits, toEnd: true);
    return SkipSegments(
      intro: check(intro, max: maxIntroLength),
      recap: check(recap, max: maxRecapLength),
      credits: credits != null && credits.start * 2 >= duration
          ? credits
          : null,
    );
  }

  Map<String, Object?> toJson() => {
    'intro': ?intro?.toJson(),
    'recap': ?recap?.toJson(),
    'credits': ?credits?.toJson(),
    'reference': ?reference?.inMilliseconds,
  };

  static SkipSegments fromJson(Object? json) {
    final map = readMap(json);
    final reference = readInt(map?['reference']);
    return SkipSegments(
      intro: SkipRange.fromJson(map?['intro']),
      recap: SkipRange.fromJson(map?['recap']),
      credits: SkipRange.fromJson(map?['credits']),
      reference: reference == null ? null : Duration(milliseconds: reference),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SkipSegments &&
      other.intro == intro &&
      other.recap == recap &&
      other.credits == credits &&
      other.reference == reference;

  @override
  int get hashCode => Object.hash(intro, recap, credits, reference);

  @override
  String toString() =>
      'SkipSegments(intro: $intro, recap: $recap, '
      'credits: $credits, reference: $reference)';
}
