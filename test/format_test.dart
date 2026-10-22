import 'package:flutter_test/flutter_test.dart';

import 'package:tvplayer/format.dart';

void main() {
  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  test('formatResolution', () {
    expect(formatResolution('1920', '1080'), '1920x1080');
    expect(formatResolution('', '1080'), '-');
  });

  test('formatDrops', () {
    expect(formatDrops(0, 0), 'dropped (vo/dec): 0 / 0');
    expect(formatDrops(12, 3), 'dropped (vo/dec): 12 / 3');
    expect(formatDrops(null, null), 'dropped (vo/dec): - / -');
  });
}
