import '../util/json.dart';
import 'language.dart';

enum TrackType { video, audio, subtitle }

/// One audio, subtitle or video track of the playing media, as listed in
/// mpv's `track-list` property.
final class MediaTrack {
  const MediaTrack({
    required this.id,
    required this.type,
    this.lang,
    this.title,
    this.codec,
    this.isDefault = false,
    this.forced = false,
    this.external = false,
    this.selected = false,
    this.hearingImpaired = false,
    this.visualImpaired = false,
    this.channels,
  });

  /// Parses one `track-list` entry; null for unknown types or a missing id.
  static MediaTrack? fromMpvJson(Map<String, Object?> json) {
    final id = readInt(json['id']);
    final type = switch (json['type']) {
      'video' => TrackType.video,
      'audio' => TrackType.audio,
      'sub' => TrackType.subtitle,
      _ => null,
    };
    if (id == null || type == null) return null;
    return MediaTrack(
      id: id,
      type: type,
      lang: readString(json['lang']),
      title: readString(json['title']),
      codec: readString(json['codec']),
      isDefault: readBool(json['default']),
      forced: readBool(json['forced']),
      external: readBool(json['external']),
      selected: readBool(json['selected']),
      hearingImpaired: readBool(json['hearing-impaired']),
      visualImpaired: readBool(json['visual-impaired']),
      channels: readInt(json['demux-channel-count']),
    );
  }

  /// mpv's id for the track, unique per type (`aid`/`sid` values).
  final int id;
  final TrackType type;

  /// Language tag as found in the file, e.g. `swe`, `en` or `English`.
  final String? lang;
  final String? title;
  final String? codec;
  final bool isDefault;

  /// Forced subtitles: only the parts in a foreign language.
  final bool forced;

  /// Loaded from a separate file (`sub-add`).
  final bool external;
  final bool selected;

  /// Subtitles for the deaf and hard of hearing (SDH).
  final bool hearingImpaired;

  /// Audio description for the visually impaired.
  final bool visualImpaired;
  final int? channels;

  Language? get language => Language.parse(lang);

  /// Whether this is SDH, by flag or by a title such as `English (SDH)`.
  bool get isSdh =>
      hearingImpaired || (title != null && _sdhPattern.hasMatch(title!));

  /// Whether the title marks it as forced, by flag or title.
  bool get isForced =>
      forced || (title != null && _forcedPattern.hasMatch(title!));

  @override
  String toString() => 'MediaTrack($type $id, $lang, $title)';
}

final _sdhPattern = RegExp(
  r'\b(sdh|cc|hearing[ -]impaired|hoh)\b',
  caseSensitive: false,
);
final _forcedPattern = RegExp(r'\bforced\b', caseSensitive: false);

/// Parses mpv's `track-list` property value. Unknown entries are skipped.
List<MediaTrack> parseMpvTrackList(Object? value) => readList(value)
    .map(readMap)
    .whereType<Map<String, Object?>>()
    .map(MediaTrack.fromMpvJson)
    .whereType<MediaTrack>()
    .toList();

/// Menu label of [track], e.g. `Svenska`, `English (SDH)` or
/// `Track 3 (Commentary)`.
///
/// The language's own name comes first; a title that only repeats the
/// language is dropped, and a title that already names it is shown as is.
String trackLabel(MediaTrack track) {
  final language = track.language;
  final title = track.title;
  final extras = <String>[];
  String base;
  if (language == null) {
    base = title ?? (track.lang?.toUpperCase() ?? 'Track ${track.id}');
  } else if (title == null || Language.parse(title) == language) {
    base = language.nativeName;
  } else if (_namesLanguage(title, language)) {
    base = title;
  } else {
    base = language.nativeName;
    extras.add(title);
  }
  final lower = base.toLowerCase() + extras.join(' ').toLowerCase();
  if (track.hearingImpaired && !_sdhPattern.hasMatch(lower)) extras.add('SDH');
  if (track.forced && !lower.contains('forced')) extras.add('forced');
  if (track.external && !lower.contains('external')) extras.add('external');
  return extras.isEmpty ? base : '$base (${extras.join(', ')})';
}

/// Labels for [tracks], made unique by adding the codec and channel count,
/// then the track number, where labels repeat.
Map<int, String> trackLabels(List<MediaTrack> tracks) {
  final labels = {for (final t in tracks) t.id: trackLabel(t)};
  void disambiguate(String Function(MediaTrack, String) extend) {
    final counts = <String, int>{};
    for (final l in labels.values) {
      counts[l] = (counts[l] ?? 0) + 1;
    }
    for (final t in tracks) {
      final label = labels[t.id]!;
      if (counts[label]! > 1) labels[t.id] = extend(t, label);
    }
  }

  disambiguate((t, l) {
    final details = [?t.codec, if (t.channels case final c?) _channelName(c)];
    return details.isEmpty ? l : '$l · ${details.join(' ')}';
  });
  disambiguate((t, l) => '$l · #${t.id}');
  return labels;
}

String _channelName(int channels) => switch (channels) {
  1 => 'mono',
  2 => 'stereo',
  6 => '5.1',
  8 => '7.1',
  _ => '${channels}ch',
};

bool _namesLanguage(String title, Language language) {
  final lower = title.toLowerCase();
  return lower.contains(language.englishName.toLowerCase()) ||
      lower.contains(language.nativeName.toLowerCase());
}
