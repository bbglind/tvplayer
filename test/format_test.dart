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

  test('formatTimeLeft', () {
    expect(formatTimeLeft(const Duration(minutes: 18)), '18 min left');
    expect(
      formatTimeLeft(const Duration(minutes: 17, seconds: 5)),
      '18 min left',
    );
    expect(
      formatTimeLeft(const Duration(hours: 1, minutes: 2)),
      '1 h 02 min left',
    );
    expect(formatTimeLeft(const Duration(seconds: 3)), '1 min left');
  });

  test('formatAgo', () {
    final now = DateTime.utc(2026, 1, 2, 12);
    String ago(Duration d) => formatAgo(now.subtract(d), now);
    expect(ago(const Duration(seconds: 20)), 'just now');
    expect(ago(const Duration(minutes: 5)), '5 min ago');
    expect(ago(const Duration(minutes: 70)), '1 h ago');
    expect(ago(const Duration(hours: 30)), 'yesterday');
    expect(ago(const Duration(days: 3)), '3 days ago');
  });

  test('greetingFor', () {
    expect(greetingFor(4), 'Good evening');
    expect(greetingFor(5), 'Good morning');
    expect(greetingFor(12), 'Good afternoon');
    expect(greetingFor(18), 'Good evening');
  });
}
