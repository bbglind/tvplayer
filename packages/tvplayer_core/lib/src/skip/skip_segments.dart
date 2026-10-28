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

/// The intro, recap and credits times of one episode, as far as known.
final class SkipSegments {
  const SkipSegments({this.intro, this.recap, this.credits});

  static const none = SkipSegments();

  final SkipRange? intro;
  final SkipRange? recap;
  final SkipRange? credits;

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
  );

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
  };

  static SkipSegments fromJson(Object? json) {
    final map = readMap(json);
    return SkipSegments(
      intro: SkipRange.fromJson(map?['intro']),
      recap: SkipRange.fromJson(map?['recap']),
      credits: SkipRange.fromJson(map?['credits']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SkipSegments &&
      other.intro == intro &&
      other.recap == recap &&
      other.credits == credits;

  @override
  int get hashCode => Object.hash(intro, recap, credits);

  @override
  String toString() =>
      'SkipSegments(intro: $intro, recap: $recap, '
      'credits: $credits)';
}
