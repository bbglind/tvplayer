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
/// playback (never past the end). Null before the credits (or while the
/// length is unknown); pausing pauses it.
int? creditsCountdown({
  required Duration position,
  required Duration? duration,
  required Duration creditsStart,
}) {
  if (duration == null || position < creditsStart) return null;
  final untilNext =
      creditsStart +
      const Duration(seconds: creditsCountdownSeconds) -
      position;
  final untilEnd = duration - position;
  final left = untilNext < untilEnd ? untilNext : untilEnd;
  if (left <= Duration.zero) return 0;
  return (left.inMilliseconds / Duration.millisecondsPerSecond).ceil();
}
