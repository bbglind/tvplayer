import 'package:timezone/timezone.dart' as tz;

/// Timing rules of replay (catch-up) and pausing live TV.
abstract final class ReplayTiming {
  /// Behind live by at most this much counts as live: reaching the end of
  /// the archive then switches to the live stream.
  static const liveThreshold = Duration(seconds: 10);

  /// How far the live picture is taken to lag the clock: pausing live TV
  /// resumes this much before the moment of the pause, so a little is
  /// repeated rather than skipped.
  static const liveDelay = Duration(seconds: 15);

  /// Longest stretch requested from the archive in one go.
  static const maxRequest = Duration(hours: 6);

  /// The end of the archive reached again this soon after loading it means
  /// there is nothing more to load: go live instead of loading again.
  static const reloadGuard = Duration(seconds: 2);

  /// While behind live the seek bar reaches back at least this far.
  static const behindLiveSpan = Duration(hours: 2);
}

/// Why a programme can't be replayed.
enum ReplayBlock {
  /// The channel keeps no archive.
  noArchive,

  /// It started before the archive window.
  tooOld,

  /// The provider's listing says the archive doesn't have it.
  notArchived,

  /// It hasn't started yet.
  future,
}

/// The archive of a channel that keeps [days] days of programmes.
///
/// Times are real instants (UTC): for guide programmes, apply the guide's
/// shift first (`GuideTime.adjust`).
final class ReplayWindow {
  const ReplayWindow(this.days);

  final int days;

  bool get available => days > 0;

  /// The earliest moment that can still be replayed at [now].
  DateTime earliest(DateTime now) => now.subtract(Duration(days: days));

  /// Whether [instant] can be played from the archive at [now].
  bool contains(DateTime instant, DateTime now) =>
      available && !instant.isBefore(earliest(now)) && instant.isBefore(now);

  /// Why a programme starting at [start] can't be replayed at [now], or
  /// null when it can. [archived] is the provider's own flag, if any.
  ReplayBlock? check({
    required DateTime start,
    required DateTime now,
    bool? archived,
  }) {
    if (!start.isBefore(now)) return ReplayBlock.future;
    if (!available) return ReplayBlock.noArchive;
    if (start.isBefore(earliest(now))) return ReplayBlock.tooOld;
    if (archived == false) return ReplayBlock.notArchived;
    return null;
  }
}

/// A replay start as the provider wants it: whole minutes, written in the
/// provider's time zone as `YYYY-MM-DD:HH-MM`.
final class TimeshiftStart {
  const TimeshiftStart._(this.floored, this.offset, this.text);

  /// The start for playing from [instant], with [server] the zone the
  /// provider reads start times in. Daylight saving changes are applied.
  factory TimeshiftStart.at(DateTime instant, tz.Location server) {
    final ms = instant.toUtc().millisecondsSinceEpoch;
    const minute = Duration.millisecondsPerMinute;
    final floored = DateTime.fromMillisecondsSinceEpoch(
      ms - ms % minute,
      isUtc: true,
    );
    final local = tz.TZDateTime.from(floored, server);
    String two(int n) => n.toString().padLeft(2, '0');
    return TimeshiftStart._(
      floored,
      Duration(milliseconds: ms % minute),
      '${local.year}-${two(local.month)}-${two(local.day)}'
      ':${two(local.hour)}-${two(local.minute)}',
    );
  }

  /// The instant the stream starts at: the requested one, down to the
  /// minute.
  final DateTime floored;

  /// How far into the stream the requested instant is.
  final Duration offset;

  /// The start as written in the URL.
  final String text;

  @override
  String toString() => 'TimeshiftStart($text)';
}

/// The minutes to request from [start] at [now]: everything recorded so
/// far (plus a minute), at most [ReplayTiming.maxRequest].
int timeshiftMinutes(DateTime start, DateTime now) {
  final recorded = now.difference(start).inSeconds;
  final minutes = (recorded / 60).ceil() + 1;
  return minutes.clamp(1, ReplayTiming.maxRequest.inMinutes);
}

/// Maps positions in a loaded archive stream that starts at [fileStart] to
/// clock time and back.
final class ReplayTimeline {
  const ReplayTimeline(this.fileStart);

  final DateTime fileStart;

  /// The moment shown at stream [position].
  DateTime clockAt(Duration position) => fileStart.add(position);

  /// The stream position of [instant].
  Duration positionOf(DateTime instant) => instant.difference(fileStart);

  /// Whether [instant] is inside the loaded stream of [length], so a seek
  /// can stay in it. False when the length is unknown.
  bool contains(DateTime instant, Duration? length) =>
      length != null &&
      !instant.isBefore(fileStart) &&
      instant.isBefore(fileStart.add(length));
}

/// How far [position] (a clock instant) is behind live at [now]; never
/// negative.
Duration behindLive(DateTime position, DateTime now) {
  final behind = now.difference(position);
  return behind.isNegative ? Duration.zero : behind;
}

/// What to do when playback reaches the end of a loaded archive stream.
enum EndOfArchive {
  /// Close enough to live, or nothing more came: play the live stream.
  goLive,

  /// Load the archive again from the position reached.
  reload,
}

/// The step at the end of a loaded archive stream, at clock [position] and
/// [now]. [loadedAt] is when the stream was loaded; reaching its end again
/// right away means the archive has nothing more.
EndOfArchive atEndOfArchive({
  required DateTime position,
  required DateTime now,
  DateTime? loadedAt,
}) {
  if (behindLive(position, now) <= ReplayTiming.liveThreshold) {
    return EndOfArchive.goLive;
  }
  if (loadedAt != null && now.difference(loadedAt) < ReplayTiming.reloadGuard) {
    return EndOfArchive.goLive;
  }
  return EndOfArchive.reload;
}

/// The stretch of clock time the replay seek bar covers.
///
/// A programme that has ended covers itself. While the programme at the
/// playing position is still on (behind live), from its start, or
/// [ReplayTiming.behindLiveSpan] ago if earlier, up to [now]. Without a
/// programme, the span before [now] or from [position] if earlier. Never
/// before [earliest] (the start of the archive).
({DateTime from, DateTime to}) replaySeekRange({
  required DateTime position,
  required DateTime now,
  required DateTime earliest,
  DateTime? programStart,
  DateTime? programStop,
}) {
  if (programStart != null &&
      programStop != null &&
      !programStop.isAfter(now)) {
    return (from: programStart, to: programStop);
  }
  var from = now.subtract(ReplayTiming.behindLiveSpan);
  final start = programStart ?? position;
  if (start.isBefore(from)) from = start;
  if (from.isBefore(earliest)) from = earliest;
  return (from: from, to: now);
}

/// [name] without the provider's replay mark, for channels where the app
/// shows its own: a last word of at most 4 characters without letters or
/// digits (`◉`, `[*]`), and the word `◉` anywhere.
String withoutReplayMark(String name) {
  var words = name.trim().split(_spaces);
  if (words.length > 1 && _isMark(words.last)) {
    words = words.sublist(0, words.length - 1);
  }
  if (words.length > 1) {
    words = [
      for (final w in words)
        if (w != _ring) w,
    ];
  }
  return words.join(' ');
}

const _ring = '◉';
final _spaces = RegExp(r'\s+');
final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isMark(String word) =>
    word.runes.length <= 4 && !_letterOrDigit.hasMatch(word);
