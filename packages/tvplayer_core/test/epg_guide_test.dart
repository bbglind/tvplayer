import 'dart:convert';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

EpgProgram _p(String channel, String title, int startHour, int stopHour) =>
    EpgProgram(
      channelId: channel,
      title: title,
      start: DateTime.utc(2026, 1, 1, startHour),
      stop: DateTime.utc(2026, 1, 1, stopHour),
    );

LiveStream _ch(String name, [String? epgId]) =>
    LiveStream(id: name, name: name, epgChannelId: epgId);

final _fetched = DateTime.utc(2026, 1, 1);

void main() {
  group('normalizeChannelName', () {
    test('ignores case, spaces and punctuation', () {
      expect(normalizeChannelName('Kanal 5'), 'kanal5');
      expect(normalizeChannelName('  KANAL-5 '), 'kanal5');
      expect(normalizeChannelName('Discovery Channel'), 'discoverychannel');
    });

    test('removes country prefixes', () {
      for (final name in [
        'SE: Kanal 5',
        'SE:Kanal 5',
        'SE | Kanal 5',
        'SE| Kanal 5',
        '|SE| Kanal 5',
        '[SE] Kanal 5',
        '(SE) Kanal 5',
        'SE - Kanal 5',
        'UK: Kanal 5',
      ]) {
        expect(normalizeChannelName(name), 'kanal5', reason: name);
      }
    });

    test('removes quality tags', () {
      for (final name in [
        'Kanal 5 HD',
        'Kanal 5 FHD',
        'Kanal 5 UHD',
        'Kanal 5 4K',
        'Kanal 5 HEVC',
        'Kanal 5 (HD)',
        'Kanal 5 1080p',
        'SE: Kanal 5 FHD',
      ]) {
        expect(normalizeChannelName(name), 'kanal5', reason: name);
      }
    });

    test('keeps tags that are part of a word', () {
      expect(normalizeChannelName('Shadow TV'), 'shadowtv');
      expect(normalizeChannelName('HDTV Plus'), 'hdtvplus');
    });

    test('keeps non-ASCII letters', () {
      expect(normalizeChannelName('SE: Näringsliv HD'), 'näringsliv');
    });
  });

  group('matching', () {
    final guide = EpgGuide(
      programs: {
        'kanal5.example': [_p('kanal5.example', 'K5 Show', 10, 11)],
        'svt1.example': [_p('svt1.example', 'SVT1 Show', 10, 11)],
        'dup1.example': [_p('dup1.example', 'Dup A', 10, 11)],
        'dup2.example': [_p('dup2.example', 'Dup B', 10, 11)],
      },
      displayNames: {
        'kanal5.example': ['Kanal 5'],
        'svt1.example': ['SVT1', 'SVT 1 HD'],
        'dup1.example': ['Duplicate'],
        'dup2.example': ['Duplicate HD'],
        'empty.example': ['Empty Channel'],
      },
      fetchedAt: _fetched,
    );

    String? titleFor(LiveStream c) => guide.programsFor(c).firstOrNull?.title;

    test('by exact EPG id', () {
      expect(titleFor(_ch('Anything', 'kanal5.example')), 'K5 Show');
    });

    test('by EPG id ignoring case and spaces', () {
      expect(titleFor(_ch('Anything', ' KANAL5.Example ')), 'K5 Show');
    });

    test('by name when the channel has no EPG id', () {
      expect(titleFor(_ch('SE: Kanal 5 HD')), 'K5 Show');
      expect(titleFor(_ch('SE: Kanal 5 HD', '')), 'K5 Show');
    });

    test('by name when the EPG id finds nothing', () {
      expect(titleFor(_ch('|SE| SVT 1 FHD', 'unknown.example')), 'SVT1 Show');
    });

    test('EPG id wins over name', () {
      expect(titleFor(_ch('Kanal 5', 'svt1.example')), 'SVT1 Show');
    });

    test('ambiguous names match nothing', () {
      expect(titleFor(_ch('Duplicate')), isNull);
    });

    test('channels without programmes are not matched by name', () {
      expect(guide.resolve(name: 'Empty Channel'), isNull);
    });

    test('no match at all', () {
      expect(titleFor(_ch('Unknown')), isNull);
      expect(guide.resolve(), isNull);
    });
  });

  group('now and next', () {
    final guide = EpgGuide(
      programs: {
        'a': [
          _p('a', 'Third', 14, 15),
          _p('a', 'First', 10, 11),
          _p('a', 'Second', 11, 12),
        ],
      },
      fetchedAt: _fetched,
    );
    final channel = _ch('A', 'a');
    String? title(EpgProgram? p) => p?.title;

    test('during a programme', () {
      final r = guide.nowAndNext(channel, DateTime.utc(2026, 1, 1, 10, 30));
      expect((title(r.now), title(r.next)), ('First', 'Second'));
    });

    test('start is inclusive, stop exclusive', () {
      final r = guide.nowAndNext(channel, DateTime.utc(2026, 1, 1, 11));
      expect((title(r.now), title(r.next)), ('Second', 'Third'));
    });

    test('in a gap', () {
      final r = guide.nowAndNext(channel, DateTime.utc(2026, 1, 1, 13));
      expect((title(r.now), title(r.next)), (null, 'Third'));
    });

    test('before the first and after the last', () {
      final before = guide.nowAndNext(channel, DateTime.utc(2026, 1, 1, 8));
      expect((title(before.now), title(before.next)), (null, 'First'));
      final after = guide.nowAndNext(channel, DateTime.utc(2026, 1, 1, 16));
      expect((after.now, after.next), (null, null));
    });

    test('between returns overlapping programmes', () {
      final r = guide.between(
        channel,
        DateTime.utc(2026, 1, 1, 10, 30),
        DateTime.utc(2026, 1, 1, 14),
      );
      expect(r.map((p) => p.title), ['First', 'Second']);
    });
  });

  group('reaches', () {
    // Channels whose guides end at the given hours.
    EpgGuide endingAt(List<int> hours) => EpgGuide(
      programs: {
        for (final (i, h) in hours.indexed) 'c$i': [_p('c$i', 'P', h - 1, h)],
      },
      fetchedAt: _fetched,
    );
    final at = DateTime.utc(2026, 1, 1, 20);

    test('an empty guide reaches nothing', () {
      expect(EpgGuide.empty(fetchedAt: _fetched).reaches(at), isFalse);
    });

    test('when all channels end after the time', () {
      expect(endingAt([21, 22, 23]).reaches(at), isTrue);
    });

    test('not when only one of three channels does', () {
      expect(endingAt([15, 16, 23]).reaches(at), isFalse);
    });

    test('half of the channels is enough', () {
      expect(endingAt([15, 16, 21, 22]).reaches(at), isTrue);
      expect(endingAt([15, 16, 17, 22]).reaches(at), isFalse);
    });

    test('a guide ending exactly at the time does not reach it', () {
      expect(endingAt([20]).reaches(at), isFalse);
      expect(endingAt([21]).reaches(at), isTrue);
    });
  });

  test('sorts, drops duplicates and trims overlaps', () {
    final guide = EpgGuide(
      programs: {
        'a': [
          _p('a', 'Long', 10, 13),
          _p('a', 'Duplicate', 10, 11),
          _p('a', 'Inside', 11, 12),
        ],
      },
      fetchedAt: _fetched,
    );
    final list = guide.programsFor(_ch('A', 'a'));
    expect(list.map((p) => p.title), ['Long', 'Inside']);
    expect(list.first.stop, DateTime.utc(2026, 1, 1, 11));
    expect(guide.end, DateTime.utc(2026, 1, 1, 12));
  });

  test('JSON round trip', () {
    final guide = EpgGuide(
      programs: {
        'a': [
          EpgProgram(
            channelId: 'a',
            title: 'Ünïcode 📺',
            description: 'Desc',
            category: 'News',
            start: DateTime.utc(2026, 10, 25, 0, 30),
            stop: DateTime.utc(2026, 10, 25, 1, 30),
          ),
        ],
      },
      displayNames: {
        'a': ['Kanal A'],
      },
      fetchedAt: DateTime.utc(2026, 10, 24, 12),
    );
    final copy = EpgGuide.fromJson(jsonDecode(jsonEncode(guide.toJson())))!;
    expect(copy.fetchedAt, guide.fetchedAt);
    final p = copy.programsFor(_ch('Kanal A')).single;
    expect(p.title, 'Ünïcode 📺');
    expect(p.description, 'Desc');
    expect(p.category, 'News');
    expect(p.start, DateTime.utc(2026, 10, 25, 0, 30));
    expect(p.start.isUtc, isTrue);
    expect(p.stop, DateTime.utc(2026, 10, 25, 1, 30));
  });

  test('fromJson rejects other versions and junk', () {
    expect(EpgGuide.fromJson({'v': 999}), isNull);
    expect(EpgGuide.fromJson('junk'), isNull);
    expect(
      EpgGuide.fromJson({
        'v': EpgGuide.jsonVersion,
        'fetchedAt': 0,
        'channels': {
          'a': {
            'programs': [
              ['x'],
            ],
          },
        },
      }),
      isNull,
    );
  });

  group('building from XMLTV', () {
    test('reports channels with their display names', () async {
      final channels = <XmltvChannel>[];
      await const XmltvParser()
          .parseString(fixture('epg_dst.xml'), onChannel: channels.add)
          .drain<void>();
      expect(channels.map((c) => c.id), [
        'kanal1.example',
        'kanal2.example',
        'other.example',
      ]);
      expect(channels[1].displayNames, ['Kanal 2', 'Channel Two']);
    });

    test('keeps only channels the playlist matches, by id or name', () async {
      final guide = await buildGuideFromXmltv(
        fixtureBytes('epg_dst.xml'),
        fetchedAt: _fetched,
        epgIds: ['KANAL1.example'],
        names: ['SE: Channel Two FHD'],
      );
      expect(guide.channelIds.toSet(), {'kanal1.example', 'kanal2.example'});
      expect(
        guide.programsFor(_ch('SE: Channel Two FHD')).single.title,
        'Night Film',
      );
      expect(guide.programsFor(_ch('Kanal 1', 'kanal1.example')), hasLength(3));
    });

    test('drops programmes that ended before keepFrom', () async {
      final guide = await buildGuideFromXmltv(
        fixtureBytes('epg_dst.xml'),
        fetchedAt: _fetched,
        keepFrom: DateTime.utc(2026, 10, 25, 1),
      );
      expect(
        guide.programsFor(_ch('x', 'kanal1.example')).map((p) => p.title),
        ['Across The Switch', 'After The Switch'],
      );
    });

    test('keeps everything without filters', () async {
      final guide = await buildGuideFromXmltv(
        fixtureBytes('epg_dst.xml'),
        fetchedAt: _fetched,
      );
      expect(guide.programCount, 5);
      expect(guide.displayNamesOf('other.example'), ['Other']);
    });
  });
}
