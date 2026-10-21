import '../util/json.dart';

/// A single EPG programme. [start] and [stop] are in UTC.
final class EpgProgram {
  const EpgProgram({
    required this.channelId,
    required this.title,
    required this.start,
    required this.stop,
    this.description,
    this.category,
  });

  /// Parses an `epg_listings` entry of Xtream `get_short_epg`. Titles and
  /// descriptions are base64 encoded there. Returns null for entries without
  /// a usable time range.
  static EpgProgram? fromXtreamJson(Map<String, Object?> json) {
    final start =
        readEpochSeconds(json['start_timestamp']) ??
        _parsePanelTime(json['start']);
    final stop =
        readEpochSeconds(json['stop_timestamp']) ??
        _parsePanelTime(json['end'] ?? json['stop']);
    if (start == null || stop == null || stop.isBefore(start)) return null;
    return EpgProgram(
      channelId:
          readString(json['channel_id']) ?? readString(json['epg_id']) ?? '',
      title: readMaybeBase64(json['title']) ?? '',
      description: readMaybeBase64(json['description']),
      start: start,
      stop: stop,
    );
  }

  /// "YYYY-MM-DD HH:MM:SS" without zone information; interpreted as UTC.
  static DateTime? _parsePanelTime(Object? value) {
    final s = readString(value);
    if (s == null) return null;
    return DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z');
  }

  /// XMLTV channel id (`epg_channel_id` of a live channel).
  final String channelId;
  final String title;
  final String? description;
  final String? category;
  final DateTime start;
  final DateTime stop;

  Duration get duration => stop.difference(start);

  /// Whether the programme is airing at [time].
  bool isAiringAt(DateTime time) =>
      !time.isBefore(start) && time.isBefore(stop);

  @override
  String toString() =>
      'EpgProgram($channelId, $title, ${start.toIso8601String()})';
}
