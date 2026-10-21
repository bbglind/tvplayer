import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

void main() {
  group('parseTime', () {
    test('applies timezone offsets', () {
      expect(
        XmltvParser.parseTime('20240101080000 +0100'),
        DateTime.utc(2024, 1, 1, 7),
      );
      expect(
        XmltvParser.parseTime('20240101090000 -0230'),
        DateTime.utc(2024, 1, 1, 11, 30),
      );
      expect(
        XmltvParser.parseTime('20240101090000 +05:30'),
        DateTime.utc(2024, 1, 1, 3, 30),
      );
      expect(
        XmltvParser.parseTime('20240101000000+0100'),
        DateTime.utc(2023, 12, 31, 23),
      );
    });

    test('defaults to UTC and zero time parts', () {
      expect(
        XmltvParser.parseTime('20240101100000'),
        DateTime.utc(2024, 1, 1, 10),
      );
      expect(XmltvParser.parseTime('2024010112'), DateTime.utc(2024, 1, 1, 12));
      expect(
        XmltvParser.parseTime('202401011330 Z'),
        DateTime.utc(2024, 1, 1, 13, 30),
      );
    });

    test('rejects malformed values', () {
      expect(XmltvParser.parseTime(null), isNull);
      expect(XmltvParser.parseTime(''), isNull);
      expect(XmltvParser.parseTime('garbage'), isNull);
      expect(XmltvParser.parseTime('20241301000000'), isNull);
      expect(XmltvParser.parseTime('20240231000000'), isNull);
      expect(XmltvParser.parseTime('20240101250000'), isNull);
      expect(XmltvParser.parseTime('20240101000000 +2500'), isNull);
    });
  });

  test('parses programmes and skips broken ones', () async {
    final programs = await const XmltvParser()
        .parseBytes(fixtureBytes('epg.xml'))
        .toList();
    expect(programs.map((p) => p.title), [
      'Test Morning Show',
      'Ünïcode <Show> 测试 📺',
      'No Offset Show',
      'Short Timestamp Show',
      'Last Valid Show',
    ]);

    final first = programs[0];
    expect(first.channelId, 'test1.example');
    expect(first.start, DateTime.utc(2024, 1, 1, 7));
    expect(first.stop, DateTime.utc(2024, 1, 1, 8));
    expect(first.description, 'News & weather for testing.');
    expect(first.category, 'News');

    expect(programs[1].start, DateTime.utc(2024, 1, 1, 11, 30));
    expect(programs[2].description, isNull);
    expect(programs[3].stop, DateTime.utc(2024, 1, 1, 13, 30));
  });

  test('filters by channel', () async {
    final programs = await const XmltvParser(
      channelIds: {'test1.example'},
    ).parseString(fixture('epg.xml')).toList();
    expect(programs.map((p) => p.channelId).toSet(), {'test1.example'});
    expect(programs, hasLength(2));
  });

  test('keeps programmes before a truncated end', () async {
    final programs = await const XmltvParser()
        .parseString(fixture('epg_truncated.xml'))
        .toList();
    expect(programs.map((p) => p.title), ['Complete Show']);
  });

  test('handles elements split across chunks', () async {
    final xml = fixture('epg.xml');
    // Feed the document in tiny chunks to exercise chunk boundaries.
    final chunks = [
      for (var i = 0; i < xml.length; i += 7)
        xml.substring(i, i + 7 > xml.length ? xml.length : i + 7),
    ];
    final programs = await const XmltvParser()
        .parseChunks(Stream.fromIterable(chunks))
        .toList();
    expect(programs, hasLength(5));
  });

  test('emits programmes incrementally', () async {
    final controller = StreamController<List<int>>();
    final received = <EpgProgram>[];
    final done = const XmltvParser()
        .parseBytes(controller.stream)
        .forEach(received.add);

    controller.add(
      utf8.encode(
        '<tv><programme start="20240101080000 +0000" '
        'stop="20240101090000 +0000" channel="test1.example">'
        '<title>First</title></programme>',
      ),
    );
    await pumpEventQueue();
    expect(received.map((p) => p.title), ['First']);

    controller.add(utf8.encode('</tv>'));
    await controller.close();
    await done;
  });

  test('handles large guides', () async {
    Stream<String> chunks() async* {
      yield '<?xml version="1.0"?><tv>';
      for (var i = 0; i < 20000; i++) {
        yield '<programme start="20240101000000 +0000" '
            'stop="20240101010000 +0000" channel="ch${i % 100}.example">'
            '<title>Test Show $i</title><desc>Description $i</desc>'
            '</programme>\n';
      }
      yield '</tv>';
    }

    expect(await const XmltvParser().parseChunks(chunks()).length, 20000);
  });
}
