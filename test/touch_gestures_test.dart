import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/player/touch/touch_gestures.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  group('tapSide', () {
    test('halves, with a middle strip', () {
      expect(tapSide(10, 1000), TapSide.left);
      expect(tapSide(399, 1000), TapSide.left);
      expect(tapSide(400, 1000), TapSide.middle);
      expect(tapSide(600, 1000), TapSide.middle);
      expect(tapSide(601, 1000), TapSide.right);
      expect(tapSide(5, 0), TapSide.middle);
    });
  });

  test('canSeekByTap: fixed-length content, not live TV', () {
    const channel = LiveStream(id: '1', name: 'News', categoryIds: []);
    expect(canSeekByTap(const LivePlayback(channel)), isFalse);
    expect(
      canSeekByTap(const MoviePlayback(Movie(streamId: 1, name: 'Film'))),
      isTrue,
    );
    expect(
      canSeekByTap(const RecordingPlayback('/tmp/x.ts', name: 'x')),
      isTrue,
    );
    expect(
      canSeekByTap(
        ReplayPlayback(
          channel,
          from: DateTime.utc(2026, 10, 26, 17),
          serverZone: 'UTC',
          requestedAt: DateTime.utc(2026, 10, 26, 18),
        ),
      ),
      isTrue,
    );
  });

  group('TouchTaps', () {
    late List<String> events;
    late bool seekable;
    late TouchTaps taps;

    setUp(() {
      events = [];
      seekable = true;
      taps = TouchTaps(
        onTap: () => events.add('tap'),
        onSeek: (by, total, side) =>
            events.add('seek ${by.inSeconds} ${total.inSeconds}'),
        onSeekEnd: () => events.add('end'),
        canSeek: () => seekable,
      );
      addTearDown(taps.dispose);
    });

    testWidgets('a single tap counts once it cannot be a double tap', (
      tester,
    ) async {
      taps.tap(TapSide.right);
      await tester.pump(const Duration(milliseconds: 299));
      expect(events, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(events, ['tap']);
    });

    testWidgets('a double tap seeks, never also a tap', (tester) async {
      taps.tap(TapSide.left);
      await tester.pump(const Duration(milliseconds: 150));
      taps.tap(TapSide.left);
      expect(events, ['seek -10 -10']);
      expect(taps.seeking, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(events, ['seek -10 -10', 'end']);
      expect(taps.seeking, isFalse);
    });

    testWidgets('more taps on the same side seek on and add up', (
      tester,
    ) async {
      taps.tap(TapSide.right);
      await tester.pump(const Duration(milliseconds: 100));
      taps.tap(TapSide.right);
      await tester.pump(const Duration(milliseconds: 500));
      taps.tap(TapSide.right);
      await tester.pump(const Duration(milliseconds: 500));
      taps.tap(TapSide.right);
      expect(events, ['seek 10 10', 'seek 10 20', 'seek 10 30']);
      await tester.pump(const Duration(milliseconds: 700));
      expect(events.last, 'end');
      // A tap after the streak starts over.
      events.clear();
      taps.tap(TapSide.right);
      await tester.pump(const Duration(milliseconds: 300));
      expect(events, ['tap']);
    });

    testWidgets('a tap on the other side ends the streak', (tester) async {
      taps.tap(TapSide.right);
      taps.tap(TapSide.right);
      await tester.pump(const Duration(milliseconds: 100));
      taps.tap(TapSide.left);
      expect(events, ['seek 10 10', 'end']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(events, ['seek 10 10', 'end', 'tap']);
    });

    testWidgets('taps on both sides are two taps', (tester) async {
      taps.tap(TapSide.left);
      await tester.pump(const Duration(milliseconds: 100));
      taps.tap(TapSide.right);
      expect(events, ['tap']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(events, ['tap', 'tap']);
    });

    testWidgets('in the middle a tap counts at once and never seeks', (
      tester,
    ) async {
      taps.tap(TapSide.middle);
      taps.tap(TapSide.middle);
      expect(events, ['tap', 'tap']);
      await tester.pump(const Duration(seconds: 1));
      expect(events, ['tap', 'tap']);
    });

    testWidgets('without seeking (live TV) every tap counts at once', (
      tester,
    ) async {
      seekable = false;
      taps.tap(TapSide.left);
      taps.tap(TapSide.left);
      expect(events, ['tap', 'tap']);
      await tester.pump(const Duration(seconds: 1));
      expect(events, ['tap', 'tap']);
    });
  });

  group('swipes', () {
    const size = Size(900, 400);

    test('left half brightness, right half volume, not at the edges', () {
      expect(swipeTarget(const Offset(100, 200), size), SwipeTarget.brightness);
      expect(swipeTarget(const Offset(800, 200), size), SwipeTarget.volume);
      expect(swipeTarget(const Offset(800, 47), size), isNull);
      expect(swipeTarget(const Offset(800, 353), size), isNull);
      expect(swipeTarget(const Offset(800, 48), size), SwipeTarget.volume);
    });

    test('the full height is the whole range; up is more', () {
      expect(levelAfterSwipe(0.5, -100, 400), 0.75);
      expect(levelAfterSwipe(0.5, 100, 400), 0.25);
      expect(levelAfterSwipe(0.5, -400, 400), 1.0);
      expect(levelAfterSwipe(0.5, 400, 400), 0.0);
      expect(levelAfterSwipe(0.3, 10, 0), 0.3);
    });
  });
}
