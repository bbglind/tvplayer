import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

MediaTrack _audio(
  int id,
  String? lang, {
  bool isDefault = false,
  bool selected = false,
  bool visualImpaired = false,
  String? title,
}) => MediaTrack(
  id: id,
  type: TrackType.audio,
  lang: lang,
  title: title,
  isDefault: isDefault,
  selected: selected,
  visualImpaired: visualImpaired,
);

MediaTrack _sub(
  int id,
  String? lang, {
  String? title,
  bool forced = false,
  bool sdh = false,
  bool isDefault = false,
}) => MediaTrack(
  id: id,
  type: TrackType.subtitle,
  lang: lang,
  title: title,
  forced: forced,
  hearingImpaired: sdh,
  isDefault: isDefault,
);

void main() {
  group('parseMpvTrackList', () {
    test('reads mpv track-list entries', () {
      final tracks = parseMpvTrackList([
        {'id': 1, 'type': 'video', 'codec': 'h264', 'selected': true},
        {
          'id': 1,
          'type': 'audio',
          'lang': 'swe',
          'codec': 'aac',
          'default': true,
          'selected': true,
          'demux-channel-count': 2,
        },
        {
          'id': 2,
          'type': 'sub',
          'lang': 'eng',
          'title': 'English (SDH)',
          'forced': false,
          'hearing-impaired': true,
          'external': false,
        },
        {'id': 3, 'type': 'sub', 'lang': 'swe', 'codec': 'dvb_teletext'},
        {'type': 'sub'}, // No id.
        {'id': 9, 'type': 'data'}, // Unknown type.
        'garbage',
      ]);
      expect(tracks, hasLength(4));
      expect(tracks[0].type, TrackType.video);
      final audio = tracks[1];
      expect(audio.type, TrackType.audio);
      expect(audio.language?.code, 'sv');
      expect(audio.isDefault, isTrue);
      expect(audio.selected, isTrue);
      expect(audio.channels, 2);
      final sdh = tracks[2];
      expect(sdh.type, TrackType.subtitle);
      expect(sdh.hearingImpaired, isTrue);
      expect(sdh.isSdh, isTrue);
      expect(tracks[3].codec, 'dvb_teletext');
    });

    test('non-lists give no tracks', () {
      expect(parseMpvTrackList(null), isEmpty);
      expect(parseMpvTrackList('x'), isEmpty);
    });
  });

  group('trackLabel', () {
    test('uses the language name, in the language itself', () {
      expect(trackLabel(_sub(1, 'swe')), 'Svenska');
      expect(trackLabel(_sub(1, 'sv')), 'Svenska');
      expect(trackLabel(_sub(1, 'eng')), 'English');
    });

    test('keeps a title that names the language', () {
      expect(
        trackLabel(_sub(1, 'eng', title: 'English (SDH)')),
        'English (SDH)',
      );
      expect(trackLabel(_sub(1, 'swe', title: 'Svenska')), 'Svenska');
      expect(trackLabel(_sub(1, 'swe', title: 'Swedish')), 'Svenska');
    });

    test('adds other titles and flags in brackets', () {
      expect(trackLabel(_sub(1, 'eng', title: 'SDH')), 'English (SDH)');
      expect(trackLabel(_sub(1, 'eng', sdh: true)), 'English (SDH)');
      expect(trackLabel(_sub(1, 'eng', forced: true)), 'English (forced)');
      expect(
        trackLabel(_audio(1, 'eng', title: 'Commentary')),
        'English (Commentary)',
      );
    });

    test('falls back to the title, the raw tag or the number', () {
      expect(trackLabel(_sub(4, null, title: 'Director cut')), 'Director cut');
      expect(trackLabel(_sub(4, 'xyz')), 'XYZ');
      expect(trackLabel(_sub(4, null)), 'Track 4');
    });

    test('trackLabels makes repeated labels unique', () {
      final labels = trackLabels([
        const MediaTrack(
          id: 1,
          type: TrackType.audio,
          lang: 'eng',
          codec: 'ac3',
          channels: 6,
        ),
        const MediaTrack(
          id: 2,
          type: TrackType.audio,
          lang: 'eng',
          codec: 'aac',
          channels: 2,
        ),
        _audio(3, 'swe'),
        _audio(4, 'swe'),
      ]);
      expect(labels, {
        1: 'English · ac3 5.1',
        2: 'English · aac stereo',
        3: 'Svenska · #3',
        4: 'Svenska · #4',
      });
    });
  });

  group('pickTracks', () {
    const prefs = TrackPreferences();

    test('default prefers Swedish, then English subtitles', () {
      final tracks = [_audio(1, 'eng'), _sub(1, 'eng'), _sub(2, 'swe')];
      expect(pickTracks(tracks, prefs).subtitleId, 2);
      expect(
        pickTracks([_audio(1, 'eng'), _sub(1, 'eng')], prefs).subtitleId,
        1,
      );
    });

    test('matches languages written in any form', () {
      final tracks = [_sub(1, 'English'), _sub(2, 'Svenska')];
      expect(
        pickTracks(
          tracks,
          const TrackPreferences(subtitleLanguages: ['eng']),
        ).subtitleId,
        1,
      );
      expect(pickTracks(tracks, prefs).subtitleId, 2);
    });

    test('no preferred language available: subtitles off', () {
      final tracks = [_audio(1, 'fre'), _sub(1, 'fre'), _sub(2, 'ger')];
      expect(pickTracks(tracks, prefs).subtitleId, isNull);
    });

    test('prefers full subtitles over SDH and forced, then default', () {
      final tracks = [
        _sub(1, 'swe', forced: true),
        _sub(2, 'swe', sdh: true),
        _sub(3, 'swe'),
        _sub(4, 'swe', isDefault: true),
      ];
      expect(pickTracks(tracks, prefs).subtitleId, 4);
      expect(
        pickTracks(tracks.sublist(0, 2), prefs).subtitleId,
        2,
        reason: 'SDH beats forced-only',
      );
    });

    test('a title saying SDH or forced counts like the flag', () {
      final tracks = [
        _sub(1, 'eng', title: 'English (SDH)'),
        _sub(2, 'eng', title: 'English Forced'),
        _sub(3, 'eng', title: 'English'),
      ];
      expect(pickTracks(tracks, prefs).subtitleId, 3);
    });

    test('subtitles off by default still shows forced ones in the audio '
        'language', () {
      const off = TrackPreferences(subtitlesOn: false);
      final tracks = [
        _audio(1, 'eng', selected: true),
        _sub(1, 'swe'),
        _sub(2, 'eng', forced: true),
      ];
      expect(pickTracks(tracks, off).subtitleId, 2);
      expect(pickTracks(tracks.sublist(0, 2), off).subtitleId, isNull);
    });

    test('audio follows preferences and avoids audio description', () {
      final tracks = [
        _audio(1, 'eng', isDefault: true),
        _audio(2, 'swe', visualImpaired: true),
        _audio(3, 'swe'),
      ];
      expect(
        pickTracks(
          tracks,
          const TrackPreferences(audioLanguages: ['sv', 'en']),
        ).audioId,
        3,
      );
      // No audio preference: keep the stream's default.
      expect(pickTracks(tracks, prefs).audioId, isNull);
      // Preferred language missing: keep the default too.
      expect(
        pickTracks(
          tracks,
          const TrackPreferences(audioLanguages: ['fi']),
        ).audioId,
        isNull,
      );
    });

    test('a remembered choice wins over the settings', () {
      final tracks = [
        _audio(1, 'eng'),
        _audio(2, 'swe'),
        _sub(1, 'swe'),
        _sub(2, 'eng'),
        _sub(3, 'eng', sdh: true),
      ];
      expect(
        pickTracks(
          tracks,
          prefs,
          memory: const TrackMemory(subtitleLanguage: 'en'),
        ).subtitleId,
        2,
      );
      expect(
        pickTracks(
          tracks,
          prefs,
          memory: const TrackMemory(subtitleLanguage: 'en', subtitleSdh: true),
        ).subtitleId,
        3,
      );
      expect(
        pickTracks(
          tracks,
          prefs,
          memory: const TrackMemory(subtitlesOff: true),
        ).subtitleId,
        isNull,
      );
      final pick = pickTracks(
        tracks,
        const TrackPreferences(audioLanguages: ['en']),
        memory: const TrackMemory(audioLanguage: 'sv', subtitlesOff: true),
      );
      expect(pick.audioId, 2);
    });

    test('a remembered language missing in this episode falls back to the '
        'settings', () {
      final tracks = [_sub(1, 'eng'), _sub(2, 'swe')];
      expect(
        pickTracks(
          tracks,
          prefs,
          memory: const TrackMemory(subtitleLanguage: 'fi'),
        ).subtitleId,
        2,
      );
    });

    test('teletext subtitles on live TV are picked like any other', () {
      final tracks = [
        _audio(1, 'swe', selected: true),
        const MediaTrack(
          id: 1,
          type: TrackType.subtitle,
          lang: 'swe',
          codec: 'dvb_teletext',
        ),
      ];
      expect(pickTracks(tracks, prefs).subtitleId, 1);
    });
  });

  group('TrackMemory', () {
    test('from a selection, by language', () {
      final memory = TrackMemory.fromSelection(
        audio: _audio(1, 'eng'),
        subtitle: _sub(5, 'Svenska', sdh: true),
      );
      expect(memory.audioLanguage, 'en');
      expect(memory.subtitleLanguage, 'sv');
      expect(memory.subtitleSdh, isTrue);
      expect(memory.subtitlesOff, isFalse);
      expect(TrackMemory.fromSelection(subtitle: null).subtitlesOff, isTrue);
    });

    test('JSON round trip', () {
      const memory = TrackMemory(
        audioLanguage: 'en',
        subtitleLanguage: 'sv',
        subtitleSdh: true,
      );
      expect(TrackMemory.fromJson(memory.toJson()), memory);
      const off = TrackMemory(subtitlesOff: true);
      expect(TrackMemory.fromJson(off.toJson()), off);
    });
  });

  test('nextSubtitleId cycles through tracks, then off', () {
    final tracks = [_audio(1, 'eng'), _sub(3, 'swe'), _sub(5, 'eng')];
    expect(nextSubtitleId(tracks, null), 3);
    expect(nextSubtitleId(tracks, 3), 5);
    expect(nextSubtitleId(tracks, 5), isNull);
    expect(nextSubtitleId(tracks, 99), isNull);
    expect(nextSubtitleId([_audio(1, 'eng')], null), isNull);
  });
}
