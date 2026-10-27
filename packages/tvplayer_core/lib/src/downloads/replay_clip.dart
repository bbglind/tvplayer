import '../live/replay.dart';

/// The stretch of a channel's archive saved for a past programme: from a
/// little before its start to a little after its end.
final class ReplayClip {
  const ReplayClip(this.from, this.to);

  /// The clip of a programme from [start] to [stop] (real instants: apply
  /// the guide's shift first). [startMargin] and [endMargin] widen it;
  /// [adjust] moves the whole clip, for an archive whose times are off
  /// (zero for now). The start never reaches before what [window] still
  /// keeps at [now].
  factory ReplayClip.forProgramme({
    required DateTime start,
    required DateTime stop,
    required Duration startMargin,
    required Duration endMargin,
    required ReplayWindow window,
    required DateTime now,
    Duration adjust = Duration.zero,
  }) {
    var from = start.toUtc().subtract(startMargin).add(adjust);
    final to = stop.toUtc().add(endMargin).add(adjust);
    final earliest = window.earliest(now).toUtc();
    if (window.available && from.isBefore(earliest)) from = earliest;
    return ReplayClip(from, to.isAfter(from) ? to : from);
  }

  final DateTime from;
  final DateTime to;

  Duration get length => to.difference(from);

  /// Whether the whole clip is in the archive at [now]: its end has
  /// passed.
  bool isReady(DateTime now) => !now.isBefore(to);
}

/// Margins and the safety limit of saving programmes.
abstract final class RecordingDefaults {
  static const startMargin = Duration(minutes: 2);
  static const endMargin = Duration(minutes: 15);
  static const maxLength = Duration(hours: 4);
}

/// When a recording started at [start] stops by itself: at the end of the
/// programme on then ([programmeEnd], real instant) plus [endMargin], but
/// never later than [maxLength] after the start. Without a programme (no
/// guide) it is [maxLength].
DateTime recordingEnd({
  required DateTime start,
  required DateTime? programmeEnd,
  required Duration endMargin,
  required Duration maxLength,
}) {
  final cap = start.add(maxLength);
  if (programmeEnd == null) return cap;
  final end = programmeEnd.add(endMargin);
  if (!end.isAfter(start)) return cap;
  return end.isBefore(cap) ? end : cap;
}
