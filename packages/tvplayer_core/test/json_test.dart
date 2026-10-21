import 'dart:convert';

import 'package:test/test.dart';
import 'package:tvplayer_core/src/util/json.dart';

void main() {
  test('readInt tolerates strings, doubles and junk', () {
    expect(readInt(5), 5);
    expect(readInt('5'), 5);
    expect(readInt(' 7 '), 7);
    expect(readInt('7.9'), 7);
    expect(readInt(3.2), 3);
    expect(readInt(''), isNull);
    expect(readInt('abc'), isNull);
    expect(readInt(null), isNull);
    expect(readInt([]), isNull);
  });

  test('readDouble accepts decimal commas', () {
    expect(readDouble('7,5'), 7.5);
    expect(readDouble(8), 8.0);
    expect(readDouble(''), isNull);
  });

  test('readString trims and drops empty values', () {
    expect(readString(' x '), 'x');
    expect(readString(''), isNull);
    expect(readString(12), '12');
    expect(readString(null), isNull);
  });

  test('readBool', () {
    expect(readBool(1), isTrue);
    expect(readBool('1'), isTrue);
    expect(readBool('true'), isTrue);
    expect(readBool('0'), isFalse);
    expect(readBool(null), isFalse);
  });

  test('readList accepts objects keyed by index', () {
    expect(readList({'0': 'a', '1': 'b'}), ['a', 'b']);
    expect(readList(null), isEmpty);
  });

  test('readEpochSeconds', () {
    expect(readEpochSeconds('1704067200'), DateTime.utc(2024, 1, 1));
    expect(readEpochSeconds('0'), isNull);
    expect(readEpochSeconds(''), isNull);
  });

  group('readMaybeBase64', () {
    test('decodes base64 UTF-8', () {
      final encoded = base64.encode(utf8.encode('Tëst 测试 📺'));
      expect(readMaybeBase64(encoded), 'Tëst 测试 📺');
    });

    test('returns plain text unchanged', () {
      expect(readMaybeBase64('Plain Title'), 'Plain Title');
      expect(readMaybeBase64('News'), 'News');
      expect(readMaybeBase64('Test'), 'Test');
    });

    test('handles null and empty', () {
      expect(readMaybeBase64(null), isNull);
      expect(readMaybeBase64(''), isNull);
    });
  });
}
