import '../util/json.dart';

/// A live TV channel from an Xtream panel.
final class LiveChannel {
  const LiveChannel({
    required this.streamId,
    required this.name,
    this.number,
    this.logoUrl,
    this.epgChannelId,
    this.categoryId,
    this.categoryIds = const [],
    this.hasArchive = false,
    this.archiveDays,
    this.added,
  });

  /// Parses a `get_live_streams` entry; returns null when the stream id is
  /// missing or invalid.
  static LiveChannel? fromJson(Map<String, Object?> json) {
    final streamId = readInt(json['stream_id']);
    if (streamId == null) return null;
    return LiveChannel(
      streamId: streamId,
      name: readString(json['name']) ?? '',
      number: readInt(json['num']),
      logoUrl: readString(json['stream_icon']),
      epgChannelId: readString(json['epg_channel_id']),
      categoryId: readString(json['category_id']),
      categoryIds: readStringList(json['category_ids']),
      hasArchive: readBool(json['tv_archive']),
      archiveDays: readInt(json['tv_archive_duration']),
      added: readEpochSeconds(json['added']),
    );
  }

  final int streamId;
  final String name;
  final int? number;
  final String? logoUrl;

  /// The XMLTV channel id used to match EPG data.
  final String? epgChannelId;
  final String? categoryId;
  final List<String> categoryIds;

  /// Whether catch-up (timeshift) is available.
  final bool hasArchive;
  final int? archiveDays;
  final DateTime? added;

  @override
  String toString() => 'LiveChannel($streamId, $name)';
}
