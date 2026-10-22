import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  group('Language.parse', () {
    test('Swedish in every form', () {
      for (final text in ['sv', 'swe', 'Swedish', 'Svenska', 'SVE', 'sv-SE']) {
        expect(Language.parse(text)?.code, 'sv', reason: text);
      }
    });

    test('English in every form', () {
      for (final text in [
        'en',
        'eng',
        'English',
        'ENGLISH',
        ' english ',
        'en-US',
        'en_GB',
      ]) {
        expect(Language.parse(text)?.code, 'en', reason: text);
      }
    });

    test('bibliographic and terminology ISO 639-2 codes', () {
      for (final (b, t, code) in [
        ('ger', 'deu', 'de'),
        ('fre', 'fra', 'fr'),
        ('dut', 'nld', 'nl'),
        ('cze', 'ces', 'cs'),
        ('gre', 'ell', 'el'),
        ('chi', 'zho', 'zh'),
        ('ice', 'isl', 'is'),
      ]) {
        expect(Language.parse(b)?.code, code, reason: b);
        expect(Language.parse(t)?.code, code, reason: t);
      }
    });

    test('names in English and in the language itself', () {
      expect(Language.parse('German')?.code, 'de');
      expect(Language.parse('Deutsch')?.code, 'de');
      expect(Language.parse('Suomi')?.code, 'fi');
      expect(Language.parse('Finnish')?.code, 'fi');
      expect(Language.parse('Français')?.code, 'fr');
      expect(Language.parse('Dansk')?.code, 'da');
    });

    test('Bokmål and Nynorsk count as Norwegian', () {
      for (final text in ['no', 'nor', 'nb', 'nob', 'nn', 'nno', 'Norsk']) {
        expect(Language.parse(text)?.code, 'no', reason: text);
      }
    });

    test('unknown, undetermined and empty give null', () {
      expect(Language.parse('und'), isNull);
      expect(Language.parse('xx'), isNull);
      expect(Language.parse(''), isNull);
      expect(Language.parse('   '), isNull);
      expect(Language.parse(null), isNull);
    });
  });

  test('Language.same', () {
    expect(Language.same('sv', 'Svenska'), isTrue);
    expect(Language.same('swe', 'Swedish'), isTrue);
    expect(Language.same('eng', 'en'), isTrue);
    expect(Language.same('ger', 'deu'), isTrue);
    expect(Language.same('sv', 'en'), isFalse);
    expect(Language.same('und', 'und'), isFalse);
    expect(Language.same(null, 'en'), isFalse);
  });

  test('display names', () {
    expect(Language.parse('swe')!.nativeName, 'Svenska');
    expect(Language.parse('swe')!.englishName, 'Swedish');
    expect(Language.parse('ger')!.iso639_2, 'deu');
  });

  test('every code and name is unambiguous', () {
    final seen = <String, String>{};
    for (final l in Language.all) {
      for (final key in [l.code, l.iso639_2, l.englishName, l.nativeName]) {
        final previous = seen[key.toLowerCase()];
        expect(
          previous == null || previous == l.code,
          isTrue,
          reason: '$key is used by $previous and ${l.code}',
        );
        seen[key.toLowerCase()] = l.code;
        expect(Language.parse(key), same(l));
      }
    }
  });
}
