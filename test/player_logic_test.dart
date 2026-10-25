import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/controls_visibility.dart';
import 'package:tvplayer/player/mpv/osd_mirror.dart';
import 'package:tvplayer/player/mpv/video_embed.dart';
import 'package:tvplayer/player/video_gestures.dart';
import 'package:tvplayer/player/video_pointer.dart';

const _at = Offset(10, 20);

void main() {
  group('VideoGestures', () {
    late int clicks;
    late int doubles;
    late List<int> wheel;
    late VideoGestures gestures;

    void setUpGestures() {
      clicks = 0;
      doubles = 0;
      wheel = [];
      gestures = VideoGestures(
        onClick: () => clicks++,
        onDoubleClick: () => doubles++,
        onWheelSteps: wheel.add,
      );
      addTearDown(gestures.dispose);
    }

    const time = Duration(milliseconds: 300);
    void press() =>
        gestures.handle(const VideoPointerDown(_at, doubleClickTime: time));

    testWidgets('a click acts once no second click can follow', (tester) async {
      setUpGestures();
      press();
      gestures.handle(const VideoPointerUp(_at));
      await tester.pump(const Duration(milliseconds: 299));
      expect(clicks, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(clicks, 1);
      // Other buttons are not clicks.
      gestures.handle(
        const VideoPointerDown(_at, button: VideoMouseButton.secondary),
      );
      await tester.pump(time);
      expect(clicks, 1);
    });

    testWidgets('a double click never also clicks, nor does a triple click', (
      tester,
    ) async {
      setUpGestures();
      press();
      press();
      gestures.handle(const VideoDoubleClick(_at));
      await tester.pump(time * 2);
      expect((clicks, doubles), (0, 1));

      press();
      press();
      gestures.handle(const VideoDoubleClick(_at));
      press();
      await tester.pump(time * 3);
      expect((clicks, doubles), (0, 2));

      // A slow second click is a click of its own.
      press();
      await tester.pump(time);
      press();
      await tester.pump(time);
      expect(clicks, 2);
    });

    testWidgets('the wheel steps by notch; touchpad fractions add up', (
      tester,
    ) async {
      setUpGestures();
      gestures.handle(const VideoScroll(_at, -1));
      gestures.handle(const VideoScroll(_at, 2));
      for (var i = 0; i < 5; i++) {
        gestures.handle(const VideoScroll(_at, 0.3));
      }
      // A change of direction drops the rest.
      gestures.handle(const VideoScroll(_at, -0.9));
      gestures.handle(const VideoScroll(_at, -0.2));
      expect(wheel, [-1, 2, 1, -1]);
    });
  });

  group('ControlsVisibility', () {
    testWidgets('always shown without auto-hide; with it, shown on activity '
        'and hidden 3 s later unless held', (tester) async {
      final controls = ControlsVisibility();
      addTearDown(controls.dispose);
      await tester.pump(const Duration(seconds: 5));
      expect(controls.visible, isTrue);

      controls.autoHide = true;
      expect(controls.visible, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(controls.visible, isFalse);

      controls.activity();
      expect(controls.visible, isTrue);
      await tester.pump(const Duration(seconds: 2));
      controls.activity();
      await tester.pump(const Duration(seconds: 2));
      expect(controls.visible, isTrue);

      controls.hold(#panel, true);
      await tester.pump(const Duration(seconds: 10));
      expect(controls.visible, isTrue);
      controls.hold(#panel, false);
      await tester.pump(const Duration(seconds: 3));
      expect(controls.visible, isFalse);

      // A hold brings them back.
      controls.hold(#focus, true);
      expect(controls.visible, isTrue);
      controls.hold(#focus, false);

      controls.autoHide = false;
      await tester.pump(const Duration(seconds: 5));
      expect(controls.visible, isTrue);
    });
  });

  test('rgbaToBgra swaps red and blue, keeping green and alpha', () {
    final pixels = Uint8List.fromList([1, 2, 3, 4, 250, 0, 10, 255]);
    expect(rgbaToBgra(pixels), [3, 2, 1, 4, 10, 0, 250, 255]);
  });

  test('pointer messages from the native video area', () {
    expect(
      pointerEventFromNative('pointer', {
        'kind': 'down',
        'x': 5.0,
        'y': 6.0,
        'button': 1,
        'doubleClickMs': 250,
      }),
      isA<VideoPointerDown>()
          .having((e) => e.position, 'position', const Offset(5, 6))
          .having(
            (e) => e.doubleClickTime,
            'time',
            const Duration(milliseconds: 250),
          ),
    );
    expect(
      pointerEventFromNative('pointer', {
        'kind': 'up',
        'x': 1,
        'y': 2,
        'button': 3,
      }),
      isA<VideoPointerUp>().having((e) => e.button, 'button', 3),
    );
    expect(
      pointerEventFromNative('pointer', {'kind': 'move', 'x': 1, 'y': 2}),
      isA<VideoPointerMove>(),
    );
    expect(
      pointerEventFromNative('scroll', {'x': 1, 'y': 2, 'dy': -0.5}),
      isA<VideoScroll>().having((e) => e.dy, 'dy', -0.5),
    );
    expect(
      pointerEventFromNative('doubleClick', {'x': 1, 'y': 2}),
      isA<VideoDoubleClick>(),
    );
    expect(pointerEventFromNative('pointer', null), isNull);
    expect(pointerEventFromNative('pointer', {'kind': 'down'}), isNull);
  });
}
