import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';

void main() {
  test('track defaults: Swedish then English subtitles, on', () {
    const settings = AppSettings();
    expect(settings.subtitleLanguages, ['sv', 'en']);
    expect(settings.audioLanguages, isEmpty);
    expect(settings.subtitlesOn, isTrue);
    expect(AppSettings.fromJson({}).subtitleLanguages, ['sv', 'en']);
  });

  test('track settings round-trip through JSON', () {
    const settings = AppSettings(
      subtitleLanguages: ['en'],
      audioLanguages: ['sv', 'en'],
      subtitlesOn: false,
    );
    final back = AppSettings.fromJson(settings.toJson());
    expect(back.subtitleLanguages, ['en']);
    expect(back.audioLanguages, ['sv', 'en']);
    expect(back.subtitlesOn, isFalse);
    expect(back.trackPreferences.audioLanguages, ['sv', 'en']);
  });

  test('languages are normalised, deduplicated and unknown ones dropped', () {
    final settings = AppSettings.fromJson({
      'subtitleLanguages': ['swe', 'Svenska', 'English', 'klingon', 3],
      'audioLanguages': 'not a list',
    });
    expect(settings.subtitleLanguages, ['sv', 'en']);
    expect(settings.audioLanguages, isEmpty);
  });
}
