import 'skip_segments.dart';

/// How long the skip button stands out after playback reaches a part.
const skipProminentFor = Duration(seconds: 10);

/// The button goes this long before the part ends (a skip would do
/// nothing).
const skipHideBefore = Duration(seconds: 1);

/// Times that arrive while a part already plays bring it out only if
/// this much of it is left.
const skipLateMinimum = Duration(seconds: 5);

/// A position step larger than this (or backwards) is a seek, not
/// playback.
const _seekStep = Duration(seconds: 3);

/// The skip button to show: for [type] (intro or recap), jumping to
/// [target]. [prominent]: shown on its own, even with the controls
/// hidden; otherwise only together with them.
final class SkipPrompt {
  const SkipPrompt(this.type, this.target, {required this.prominent});

  final SkipType type;
  final Duration target;
  final bool prominent;

  @override
  bool operator ==(Object other) =>
      other is SkipPrompt &&
      other.type == type &&
      other.target == target &&
      other.prominent == prominent;

  @override
  int get hashCode => Object.hash(type, target, prominent);

  @override
  String toString() => 'SkipPrompt(${type.name}, $target, $prominent)';
}

/// Follows the playing position of one episode and says which skip
/// button shows ([update]).
///
/// The button shows from the start of an intro or recap until
/// [skipHideBefore] its end. When playback reaches the start (or starts
/// there, or the times arrive with at least [skipLateMinimum] left) it
/// stands out for [skipProminentFor] of playback, once per part; after
/// a seek into the middle, or after that, it shows with the controls.
class SkipTracker {
  /// Times sanitized for the episode's length (see
  /// [SkipSegments.sanitized]).
  SkipSegments get segments => _segments;
  SkipSegments _segments = SkipSegments.none;

  Duration? _last;

  /// The first position seen: where playback started (or resumed).
  Duration? _first;

  /// Where each part's prominent phase ends (playing position).
  final _prominentUntil = <SkipType, Duration>{};

  /// Parts whose prominent phase was given (or passed up after a seek).
  final _done = <SkipType>{};

  static const _types = [SkipType.recap, SkipType.intro];

  /// New times, e.g. when the lookup comes back during playback.
  void setSegments(SkipSegments segments) {
    _segments = segments;
    final position = _last;
    if (position == null) return;
    for (final type in _types) {
      final r = segments[type];
      if (r == null || _done.contains(type)) continue;
      if (position >= r.start && position < r.end!) {
        _done.add(type);
        // Played from before the part (not resumed in its middle).
        final watched = _first! <= r.start + _seekStep;
        if (watched && r.end! - position >= skipLateMinimum) {
          _prominentUntil[type] = position + skipProminentFor;
        }
      }
    }
  }

  /// The button at [position], or null.
  SkipPrompt? update(Duration position) {
    final last = _last;
    _last = position;
    _first ??= position;
    final played =
        last != null && position >= last && position - last <= _seekStep;
    // A seek ends any prominent phase.
    if (last != null && !played) _prominentUntil.clear();
    for (final type in _types) {
      final r = _segments[type];
      if (r == null) continue;
      final end = r.end!;
      if (position < r.start || position >= end - skipHideBefore) continue;
      if (!_done.contains(type)) {
        _done.add(type);
        // Reached by playing, or playback starts at the part's start.
        final entered = played
            ? last < r.start
            : last == null && position - r.start <= _seekStep;
        if (entered) {
          _prominentUntil[type] = position + skipProminentFor;
        }
      }
      final until = _prominentUntil[type];
      return SkipPrompt(
        type,
        end,
        prominent: until != null && position < until && position >= r.start,
      );
    }
    return null;
  }
}
