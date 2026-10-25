import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  group('ParsedTitle', () {
    void expectParsed(
      String raw, {
      required String title,
      String? tag,
      int? year,
      String? country,
    }) {
      final p = ParsedTitle.parse(raw);
      expect(p.raw, raw);
      expect(p.title, title, reason: 'title of "$raw"');
      expect(p.tag, tag, reason: 'tag of "$raw"');
      expect(p.year, year, reason: 'year of "$raw"');
      expect(p.country, country, reason: 'country of "$raw"');
    }

    test('provider tags, years and countries', () {
      expectParsed(
        '4K-TOP - Lantern Harbour (2026)',
        title: 'Lantern Harbour',
        tag: '4K-TOP',
        year: 2026,
      );
      expectParsed(
        'NF-DO - Quiet Orchard',
        title: 'Quiet Orchard',
        tag: 'NF-DO',
      );
      expectParsed(
        'SC - The Paper Moth (2019)',
        title: 'The Paper Moth',
        tag: 'SC',
        year: 2019,
      );
      expectParsed(
        '4K-A+ - Copper Valley (2023) (US)',
        title: 'Copper Valley',
        tag: '4K-A+',
        year: 2023,
        country: 'US',
      );
      expectParsed(
        'EN - Northern Signal (UK) (2021)',
        title: 'Northern Signal',
        tag: 'EN',
        year: 2021,
        country: 'UK',
      );
      expectParsed('|EN| - Glass Tide', title: 'Glass Tide', tag: '|EN|');
    });

    test('no tag, no year', () {
      expectParsed('Plain Title', title: 'Plain Title');
      expectParsed('  Padded Title  ', title: 'Padded Title');
      expectParsed('', title: '');
    });

    test('titles containing " - " keep it', () {
      expectParsed(
        'Spider-Cat - Into the Yarn (2018)',
        title: 'Spider-Cat - Into the Yarn',
        year: 2018,
      );
      expectParsed(
        'EN - Murder - She Wrote It (1984)',
        title: 'Murder - She Wrote It',
        tag: 'EN',
        year: 1984,
      );
      // Lower-case letters: a title, not a tag.
      expectParsed('Mission - Possible', title: 'Mission - Possible');
      // A single letter is not a tag.
      expectParsed('M - Shadow City', title: 'M - Shadow City');
      // Too long for a tag.
      expectParsed('ABCDEFGHIJK - Something', title: 'ABCDEFGHIJK - Something');
      // No space after the dash.
      expectParsed('EN -Dashing', title: 'EN -Dashing');
    });

    test('titles starting with a number or year', () {
      // Digits only: never a tag.
      expectParsed('1917 - The Long Walk', title: '1917 - The Long Walk');
      expectParsed('2049 (2017)', title: '2049', year: 2017);
      expectParsed(
        'EN - 2001: A Space Trip (1968)',
        title: '2001: A Space Trip',
        tag: 'EN',
        year: 1968,
      );
      expectParsed(
        '(500) Days Later (2009)',
        title: '(500) Days Later',
        year: 2009,
      );
    });

    test('only a trailing year in parentheses counts', () {
      expectParsed('Year 2020 Reboot', title: 'Year 2020 Reboot');
      expectParsed('Old Tale (1066)', title: 'Old Tale (1066)');
      expectParsed('Season (2019) Extra', title: 'Season (2019) Extra');
      // Nothing left after removing it: kept.
      expectParsed('(2020)', title: '(2020)');
      expectParsed('EN - (US)', title: '(US)', tag: 'EN');
      // Lower-case: not a country.
      expectParsed('Tale (us)', title: 'Tale (us)');
    });

    test('withoutTag keeps year and country', () {
      expect(
        ParsedTitle.parse('4K-TOP - Lantern Harbour (2026) (US)').withoutTag,
        'Lantern Harbour (2026) (US)',
      );
      expect(ParsedTitle.withoutTagOf('Plain'), 'Plain');
    });

    test('models use the title year', () {
      expect(const Movie(streamId: 1, name: 'X - A (2020) (US)').year, 2020);
      expect(
        const Series(
          seriesId: 1,
          name: 'A (2020)',
          releaseDate: '2018-01-02',
        ).year,
        2018,
      );
    });
  });

  group('search', () {
    bool matches(String query, String name) =>
        SearchQuery(query).matches(SearchKey(name));

    test('normalises case, diacritics and punctuation', () {
      expect(normalizeForSearch('Crème Brûlée!'), 'creme brulee');
      expect(normalizeForSearch('Straße  Œuvre'), 'strasse oeuvre');
      expect(normalizeForSearch('Åsa & Øyvind'), 'asa oyvind');
      expect(normalizeForSearch('Café'), 'cafe');
      expect(normalizeForSearch('  --  '), '');
      expect(normalizeForSearch('Ελλάδα'), 'ελλάδα');
    });

    test('case- and diacritics-insensitive', () {
      expect(matches('NORDLJUS', 'Nordljus Stories'), isTrue);
      expect(matches('fjall', 'Fjäll Patrol'), isTrue);
      expect(matches('fjäll', 'Fjall Patrol'), isTrue);
      expect(matches('cafe', 'CAFÉ NOIR'), isTrue);
    });

    test('ignores the provider tag', () {
      expect(matches('top', '4K-TOP - Lantern Harbour'), isFalse);
      expect(matches('lantern', '4K-TOP - Lantern Harbour'), isTrue);
      expect(matches('en', 'EN - Glass Tide'), isFalse);
    });

    test('matches without spaces and words in any order', () {
      expect(matches('svt1', 'SVT 1 HD'), isTrue);
      expect(matches('svt 1', 'SVT1 HD'), isTrue);
      expect(matches('spiderman', 'Spider-Man Returns'), isTrue);
      expect(matches('returns spider', 'Spider-Man Returns'), isTrue);
      expect(matches('returns cat', 'Spider-Man Returns'), isFalse);
      expect(matches('2023', 'Copper Valley (2023)'), isTrue);
      expect(matches('', 'Anything'), isTrue);
      expect(matches('!!', 'Anything'), isTrue);
    });

    test('the index finds and ranks matches', () {
      final index = SearchIndex([
        'EN - The Harbour Watch', // 0: word start
        'Harbourside', // 1: prefix
        'NF-DO - Harbour', // 2: exact (tag ignored)
        'Arbour Day', // 3: no match
        'Old harbourmaster', // 4: word start
        'Ćharbour', // 5: contains (folded)
        'Harbour (2020)', // 6: prefix
      ]);
      expect(index.length, 7);
      expect(index.ranked(SearchQuery('HARBOUR')), [2, 1, 6, 0, 4, 5]);
      expect(index.ranked(SearchQuery('harbour'), within: [5, 4, 3]), [4, 5]);
      expect(index.ranked(SearchQuery('')), [0, 1, 2, 3, 4, 5, 6]);
      expect(index.titleYear(6), 2020);
      expect(index.titleYear(0), isNull);
      expect(index.sortKey(0), 'the harbour watch');
      expect(index.sortKey(2), 'harbour');
    });

    test('the index matches multi-word and spaceless queries', () {
      final index = SearchIndex([
        'SVT 1 HD',
        'SVT1 Extra',
        'TV 1 Sports',
        'Sports One',
        'One Sports Live',
      ]);
      List<int> hits(String q) {
        final flags = index.matching(SearchQuery(q));
        return [
          for (var i = 0; i < flags.length; i++)
            if (flags[i] == 1) i,
        ];
      }

      expect(hits('svt1'), [0, 1]);
      expect(hits('svt 1'), [0, 1]);
      expect(hits('sports one'), [3, 4]);
      expect(hits('one sports'), [3, 4]);
      expect(hits('hd'), [0]);
      expect(hits('nothing'), isEmpty);
    });

    test('the index is fast for large catalogues', () {
      final names = [
        for (var i = 0; i < 60000; i++)
          'TAG - Title number $i word${i % 97} (${1950 + i % 70})',
      ];
      final build = Stopwatch()..start();
      final index = SearchIndex(names);
      build.stop();
      final query = Stopwatch()..start();
      final found = index.ranked(SearchQuery('word5 number 12'));
      query.stop();
      expect(found, isNotEmpty);
      // Generous limits for slow CI machines and the JIT.
      expect(build.elapsedMilliseconds, lessThan(3000));
      expect(query.elapsedMilliseconds, lessThan(500));
    });
  });
}
