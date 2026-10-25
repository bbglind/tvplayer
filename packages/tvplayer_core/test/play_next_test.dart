import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  int? countdown(int position, {int? duration = 2400, int lead = 30}) =>
      playNextCountdown(
        position: Duration(milliseconds: position),
        duration: duration == null ? null : Duration(seconds: duration),
        leadSeconds: lead,
      );

  test('counts down the time left over the last lead seconds', () {
    expect(countdown(2369000), isNull);
    expect(countdown(2370000), 30);
    expect(countdown(2370001), 30);
    expect(countdown(2389500), 11);
    expect(countdown(2399999), 1);
    expect(countdown(2400000), 0);
    expect(countdown(2401000), 0);
  });

  test('nothing while the length is unknown or within the window', () {
    expect(countdown(0, duration: null), isNull);
    expect(countdown(0, duration: 0), isNull);
    expect(countdown(10000, duration: 30), isNull);
    expect(countdown(25000, duration: 31), 6);
  });

  test('other lead times', () {
    expect(countdown(2280000, lead: 120), 120);
    expect(countdown(2279000, lead: 120), isNull);
  });
}
