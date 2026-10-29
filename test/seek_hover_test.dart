import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/format.dart';
import 'package:tvplayer/ui/player/player_controls.dart';
import 'package:tvplayer/ui/theme/app_theme.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

Future<TestGesture> _mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  return gesture;
}

Widget _host(Widget bar) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 800, child: bar)),
  ),
);

void main() {
  testWidgets('hovering the seek bar names the time a click there seeks '
      'to; leaving or dragging clears it', (tester) async {
    SeekHover? hover;
    Duration? seeked;
    await tester.pumpWidget(
      _host(
        PlayerSeekBar(
          position: Duration.zero,
          duration: const Duration(hours: 1),
          showRemaining: false,
          onToggleRemaining: () {},
          onSeek: (d) => seeked = d,
          onHover: (h) => hover = h,
        ),
      ),
    );
    final slider = tester.getRect(find.byKey(const Key('player.seek')));
    final mouse = await _mouse(tester);
    for (final fraction in [0.0, 0.25, 0.5, 0.9, 1.0]) {
      final at = Offset(
        slider.left + 24 + fraction * (slider.width - 48),
        slider.center.dy,
      );
      await mouse.moveTo(at);
      await tester.pump();
      expect(hover?.x, at.dx);
      final label = hover!.label;
      await tester.tapAt(at, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(label, formatDuration(seeked!), reason: '$fraction');
      if (fraction == 1.0) expect(label, '1:00:00');
    }
    await mouse.moveTo(
      Offset(slider.left + 24 + 0.25 * (slider.width - 48), slider.center.dy),
    );
    await tester.pump();
    expect(hover!.label, '15:00');

    await mouse.moveTo(Offset(slider.left, slider.top - 100));
    await tester.pump();
    expect(hover, isNull);

    await mouse.moveTo(slider.center);
    await tester.pump();
    expect(hover, isNotNull);
    await mouse.down(slider.center);
    await mouse.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(hover, isNull);
    await mouse.up();
  });

  testWidgets('a replay names the clock time', (tester) async {
    final time = GuideTime.named('UTC');
    final from = DateTime.utc(2026, 10, 25, 18);
    SeekHover? hover;
    DateTime? seeked;
    await tester.pumpWidget(
      _host(
        ReplaySeekBar(
          position: from,
          from: from,
          to: from.add(const Duration(hours: 2)),
          time: time,
          onSeek: (t) => seeked = t,
          onHover: (h) => hover = h,
        ),
      ),
    );
    final slider = tester.getRect(find.byKey(const Key('player.seek')));
    final at = Offset(
      slider.left + 24 + 0.25 * (slider.width - 48),
      slider.center.dy,
    );
    final mouse = await _mouse(tester);
    await mouse.moveTo(at);
    await tester.pump();
    expect(hover!.label, '18:30:00');
    // A press starts a drag, which clears it.
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(seeked, DateTime.utc(2026, 10, 25, 18, 30));
  });

  testWidgets('without onHover (the touch player) nothing tracks the mouse', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PlayerSeekBar(
          position: Duration.zero,
          duration: const Duration(hours: 1),
          showRemaining: false,
          onToggleRemaining: () {},
          onSeek: (_) {},
          touch: true,
        ),
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('player.seek')),
        matching: find.byWidgetPredicate(
          (w) => w is MouseRegion && w.onHover != null,
        ),
      ),
      findsNothing,
    );
  });
}
