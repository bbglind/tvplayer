import 'dart:async';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

void main() {
  const parser = M3uParser();

  test('parses a well-formed playlist', () {
    final entries = parser.parseString(fixture('playlist.m3u')).toList();
    expect(entries, hasLength(4));

    final first = entries[0];
    expect(first.name, 'Test Channel 1');
    expect(first.tvgId, 'test1.example');
    expect(first.tvgName, 'Test Channel 1');
    expect(first.tvgLogo, 'http://example.com/logos/test1.png');
    expect(first.groupTitle, 'Test News');
    expect(first.duration, -1);
    expect(first.url, 'http://example.com/live/testuser/testpass/101.ts');

    final second = entries[1];
    expect(second.name, 'Test Channel 2, HD');
    expect(second.tvgName, 'Test Channel 2, HD');
    expect(second.attributes['catchup'], 'default');
    expect(second.url, endsWith('/102.ts'));

    final third = entries[2];
    expect(third.name, 'Tëst Ünïcode 测试 📺');
    expect(third.tvgId, isNull);
    expect(third.groupTitle, 'Test Unicode');

    expect(entries[3].duration, 5400);
    expect(entries[3].groupTitle, isNull);
  });

  test('tolerates malformed lines', () {
    final entries = parser.parseString(fixture('malformed.m3u')).toList();
    expect(entries.map((e) => e.name), [
      'Test Channel Broken',
      'nocolon.ts',
      'Bare Stream.ts',
      'Test Channel Unquoted',
      'Unknown',
    ]);
    // The orphan #EXTINF was replaced by the next one.
    expect(entries[0].url, 'http://example.com/broken.ts');
    expect(entries[0].tvgId, isNull);
    expect(entries[3].tvgId, 'unquoted.example');
    expect(entries[3].groupTitle, 'Single Quoted');
  });

  test('streams bytes with BOM and CRLF line endings', () async {
    final entries = await parser
        .parseBytes(fixtureBytes('crlf_bom.m3u'))
        .toList();
    expect(entries.single.name, 'Test Channel CRLF');
    expect(entries.single.groupTitle, 'CRLF');
    expect(entries.single.url, 'http://example.com/crlf.ts');
  });

  test('parses lazily from a line stream', () async {
    final controller = StreamController<String>();
    final received = <M3uEntry>[];
    final done = parser.parseLines(controller.stream).forEach(received.add);

    controller
      ..add('#EXTM3U')
      ..add('#EXTINF:-1,Test Channel 1')
      ..add('http://example.com/1.ts');
    await pumpEventQueue();
    // The first entry is available before the stream is complete.
    expect(received.map((e) => e.name), ['Test Channel 1']);

    controller
      ..add('#EXTINF:-1,Test Channel 2')
      ..add('http://example.com/2.ts');
    await controller.close();
    await done;
    expect(received.map((e) => e.name), ['Test Channel 1', 'Test Channel 2']);
  });

  test('handles large playlists', () async {
    Stream<String> lines() async* {
      yield '#EXTM3U';
      for (var i = 0; i < 50000; i++) {
        yield '#EXTINF:-1 tvg-id="ch$i.example" group-title="G${i % 10}",'
            'Test Channel $i';
        yield 'http://example.com/$i.ts';
      }
    }

    expect(await parser.parseLines(lines()).length, 50000);
  });
}
