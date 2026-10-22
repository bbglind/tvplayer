import '../util/json.dart';
import 'language.dart';
import 'media_track.dart';

/// The user's track settings. Languages are in order of preference, as any
/// form [Language.parse] understands (settings store ISO 639-1 codes).
final class TrackPreferences {
  const TrackPreferences({
    this.subtitleLanguages = defaultSubtitleLanguages,
    this.audioLanguages = const [],
    this.subtitlesOn = true,
  });

  static const defaultSubtitleLanguages = ['sv', 'en'];

  final List<String> subtitleLanguages;

  /// Empty: keep the stream's default audio.
  final List<String> audioLanguages;

  /// Whether to show subtitles when nothing else was chosen.
  final bool subtitlesOn;
}

/// A manual track choice, remembered for the rest of a series. Stored by
/// language rather than track id, since ids differ between episodes.
final class TrackMemory {
  const TrackMemory({
    this.audioLanguage,
    this.subtitlesOff = false,
    this.subtitleLanguage,
    this.subtitleSdh = false,
  });

  /// The memory of choosing [audio] and [subtitle] (null: off).
  factory TrackMemory.fromSelection({
    MediaTrack? audio,
    MediaTrack? subtitle,
  }) => TrackMemory(
    audioLanguage: audio?.language?.code,
    subtitlesOff: subtitle == null,
    subtitleLanguage: subtitle?.language?.code,
    subtitleSdh: subtitle?.isSdh ?? false,
  );

  factory TrackMemory.fromJson(Object? json) {
    final map = readMap(json) ?? const {};
    return TrackMemory(
      audioLanguage: readString(map['audio']),
      subtitlesOff: readBool(map['subOff']),
      subtitleLanguage: readString(map['sub']),
      subtitleSdh: readBool(map['sdh']),
    );
  }

  /// ISO 639-1 code; null when no language was recognised.
  final String? audioLanguage;
  final bool subtitlesOff;
  final String? subtitleLanguage;
  final bool subtitleSdh;

  Map<String, Object?> toJson() => {
    'audio': ?audioLanguage,
    if (subtitlesOff) 'subOff': true,
    'sub': ?subtitleLanguage,
    if (subtitleSdh) 'sdh': true,
  };

  @override
  bool operator ==(Object other) =>
      other is TrackMemory &&
      other.audioLanguage == audioLanguage &&
      other.subtitlesOff == subtitlesOff &&
      other.subtitleLanguage == subtitleLanguage &&
      other.subtitleSdh == subtitleSdh;

  @override
  int get hashCode =>
      Object.hash(audioLanguage, subtitlesOff, subtitleLanguage, subtitleSdh);
}

/// Tracks to select when playback starts.
final class TrackPick {
  const TrackPick({this.audioId, this.subtitleId});

  /// Audio track to select; null keeps the stream's default.
  final int? audioId;

  /// Subtitle track to select; null turns subtitles off.
  final int? subtitleId;

  @override
  String toString() => 'TrackPick(audio: $audioId, sub: $subtitleId)';
}

/// Chooses audio and subtitles from [tracks].
///
/// A remembered manual choice ([memory]) wins over [prefs]. Audio: the first
/// preferred language that has a track, avoiding audio description. Subtitles,
/// when on: the first preferred language that has a full (not forced) track,
/// preferring non-SDH unless SDH was chosen before. When subtitles are off,
/// or no preferred language is available, forced subtitles in the audio
/// language are still shown, since they translate foreign-language parts.
TrackPick pickTracks(
  List<MediaTrack> tracks,
  TrackPreferences prefs, {
  TrackMemory? memory,
}) {
  final audio = [
    for (final t in tracks)
      if (t.type == TrackType.audio) t,
  ];
  final subs = [
    for (final t in tracks)
      if (t.type == TrackType.subtitle) t,
  ];
  final full = [
    for (final t in subs)
      if (!t.isForced) t,
  ];

  final audioPick = _best(audio, [
    ?memory?.audioLanguage,
    ...prefs.audioLanguages,
  ], (t) => (t.visualImpaired ? 2 : 0) + (t.isDefault ? 0 : 1));
  final playingAudio =
      audioPick ??
      audio.where((t) => t.selected).firstOrNull ??
      audio.firstOrNull;
  final forced = _best(
    [
      for (final t in subs)
        if (t.isForced) t,
    ],
    [?playingAudio?.lang],
    (t) => t.isDefault ? 0 : 1,
  );
  TrackPick pick(MediaTrack? subtitle) =>
      TrackPick(audioId: audioPick?.id, subtitleId: (subtitle ?? forced)?.id);

  if (memory != null) {
    if (memory.subtitlesOff) return pick(null);
    final remembered = _best(full, [
      ?memory.subtitleLanguage,
    ], (t) => (t.isSdh == memory.subtitleSdh ? 0 : 2) + (t.isDefault ? 0 : 1));
    if (remembered != null) return pick(remembered);
  }
  if (!prefs.subtitlesOn) return pick(null);
  return pick(
    _best(
      full,
      prefs.subtitleLanguages,
      (t) => (t.isSdh ? 2 : 0) + (t.isDefault ? 0 : 1),
    ),
  );
}

/// The lowest-[score] track in the first of [languages] that any of
/// [candidates] is in; ties keep track order.
MediaTrack? _best(
  List<MediaTrack> candidates,
  List<String> languages,
  int Function(MediaTrack) score,
) {
  for (final language in languages) {
    MediaTrack? best;
    for (final t in candidates) {
      if (!Language.same(t.lang, language)) continue;
      if (best == null || score(t) < score(best)) best = t;
    }
    if (best != null) return best;
  }
  return null;
}

/// The subtitle track after [currentId] in [tracks], for a "cycle
/// subtitles" key: each subtitle track in order, then off (null), then the
/// first again.
int? nextSubtitleId(List<MediaTrack> tracks, int? currentId) {
  final ids = [
    for (final t in tracks)
      if (t.type == TrackType.subtitle) t.id,
  ];
  if (ids.isEmpty) return null;
  if (currentId == null) return ids.first;
  final i = ids.indexOf(currentId);
  return i < 0 || i == ids.length - 1 ? null : ids[i + 1];
}
