/// Settings range of "Play next episode", in seconds before the end.
const playNextChoices = [15, 20, 30, 45, 60, 90, 120];

/// Default of "Play next episode".
const defaultPlayNextSeconds = 30;

/// Whole seconds until the next episode starts on its own, counted down
/// over the last [leadSeconds] of an episode of [duration] played to
/// [position]; null outside that window (or while the length is unknown).
/// It is the time left of the episode, so pausing pauses the countdown.
///
/// Episodes no longer than the window never count down: the card would
/// show from the start.
int? playNextCountdown({
  required Duration position,
  required Duration? duration,
  required int leadSeconds,
}) {
  if (duration == null || duration <= Duration(seconds: leadSeconds)) {
    return null;
  }
  final left = duration - position;
  if (left > Duration(seconds: leadSeconds)) return null;
  if (left <= Duration.zero) return 0;
  return (left.inMilliseconds / Duration.millisecondsPerSecond).ceil();
}

/// How long the next-episode card counts down once the credits start.
const creditsCountdownSeconds = 10;

/// Whole seconds until the next episode starts when an episode of
/// [duration] played to [position] has credits from [creditsStart]: the
/// card shows from there and counts down [creditsCountdownSeconds] of
/// playback from [countFrom] (default [creditsStart]; never past the
/// end). Null before the credits (or while the length is unknown);
/// pausing pauses it.
int? creditsCountdown({
  required Duration position,
  required Duration? duration,
  required Duration creditsStart,
  Duration? countFrom,
}) {
  if (duration == null || position < creditsStart) return null;
  final untilNext =
      (countFrom ?? creditsStart) +
      const Duration(seconds: creditsCountdownSeconds) -
      position;
  final untilEnd = duration - position;
  final left = untilNext < untilEnd ? untilNext : untilEnd;
  if (left <= Duration.zero) return 0;
  return (left.inMilliseconds / Duration.millisecondsPerSecond).ceil();
}

/// A position step larger than this (or backwards) is a seek.
const _seekStep = Duration(seconds: 3);

/// Follows the playing position of an episode with credits from
/// [creditsStart] and says the countdown ([update]): reached by playing,
/// it counts from the credits start; after a seek into or within the
/// credits (or starting there, or times arriving there) from where
/// playback landed, so the card shows its full countdown instead of the
/// next episode starting at once.
class CreditsCountdown {
  CreditsCountdown(this.creditsStart);

  final Duration creditsStart;

  Duration? _last;
  Duration? _from;

  /// The countdown at [position] of an episode of [duration] (see
  /// [creditsCountdown]).
  int? update(Duration position, Duration? duration) {
    final last = _last;
    _last = position;
    if (position < creditsStart) {
      _from = null;
    } else {
      final played =
          last != null && position >= last && position - last <= _seekStep;
      if (!played) {
        _from = position;
      } else {
        _from ??= creditsStart;
      }
    }
    return creditsCountdown(
      position: position,
      duration: duration,
      creditsStart: creditsStart,
      countFrom: _from,
    );
  }
}
