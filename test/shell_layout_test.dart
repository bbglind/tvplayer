import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/state/navigation.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

Future<FakeSettingsStorage> _pump(
  WidgetTester tester, {
  AppSettings saved = const AppSettings(),
  double width = 1400,
  LiveCatalog? catalog,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = FakeSettingsStorage(saved);
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(
          FakeLiveSource(catalog ?? syntheticCatalog(count: 20, categories: 2)),
        ),
      ],
      settings: settings,
      child: const AppShell(),
    ),
  );
  await tester.pumpAndSettle();
  // The app opens on Home; these tests start on Live TV.
  await tester.tap(find.byKey(Key('nav.${AppSection.live.index}')));
  await tester.pumpAndSettle();
  return settings;
}

double _sidebarWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(const Key('sidebar'))).width;

const _toggle = Key('sidebar.toggle');
const _resize = Key('sidebar.resize');

bool _focusIn(WidgetTester tester, Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final element = tester.element(finder);
  if (context == element) return true;
  var inside = false;
  context.visitAncestorElements((e) => !(inside = e == element));
  return inside;
}

void main() {
  group('Sidebar', () {
    testWidgets('the toggle collapses to icons only and back, remembered', (
      tester,
    ) async {
      final settings = await _pump(tester);
      expect(_sidebarWidth(tester), AppSettings.defaultSidebarWidth);
      expect(find.byTooltip('Collapse sidebar'), findsOneWidget);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), Sidebar.compactWidth);
      expect(find.text('tvplayer'), findsNothing);
      expect(find.byTooltip('Expand sidebar'), findsOneWidget);
      expect(settings.saved.sidebarCollapsed, isTrue);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), AppSettings.defaultSidebarWidth);
      expect(settings.saved.sidebarCollapsed, isFalse);
    });

    testWidgets('dragging the edge resizes; below the minimum it snaps to '
        'icons only', (tester) async {
      final settings = await _pump(tester);

      await tester.drag(find.byKey(_resize), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), closeTo(292, 1));
      expect(settings.saved.sidebarWidth, closeTo(292, 1));

      // Clamped to the maximum.
      await tester.drag(find.byKey(_resize), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), AppSettings.maxSidebarWidth);

      await tester.drag(find.byKey(_resize), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), Sidebar.compactWidth);
      expect(settings.saved.sidebarCollapsed, isTrue);
      // The full width is kept for expanding again.
      expect(settings.saved.sidebarWidth, AppSettings.maxSidebarWidth);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), AppSettings.maxSidebarWidth);

      // Dragging a collapsed sidebar wide enough expands it.
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(_resize), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), closeTo(276, 1));
      expect(settings.saved.sidebarCollapsed, isFalse);
    });

    testWidgets('starts with the saved state', (tester) async {
      await _pump(
        tester,
        saved: const AppSettings(sidebarCollapsed: true, sidebarWidth: 300),
      );
      expect(_sidebarWidth(tester), Sidebar.compactWidth);

      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_sidebarWidth(tester), 300);
    });

    testWidgets('narrow windows always show icons only, without controls', (
      tester,
    ) async {
      await _pump(tester, width: 850);
      expect(_sidebarWidth(tester), Sidebar.compactWidth);
      expect(find.byKey(_toggle), findsNothing);
      expect(find.byKey(_resize), findsNothing);
    });
  });

  group('Category list', () {
    testWidgets('the header hides it and a button brings it back, '
        'remembered per section', (tester) async {
      final settings = await _pump(tester);
      final list = find.byKey(const Key('live.categories'));
      final channels = find.byKey(const Key('live.channels'));
      expect(list, findsOneWidget);
      expect(find.byTooltip('Hide categories'), findsOneWidget);
      final channelsLeft = tester.getTopLeft(channels).dx;

      await tester.tap(find.byKey(const Key('live.categories.hide')));
      await tester.pumpAndSettle();
      expect(list, findsNothing);
      expect(settings.saved.hiddenCategoryLists, {'live'});
      expect(find.byTooltip('Show categories'), findsOneWidget);
      // The content takes the freed width.
      expect(tester.getTopLeft(channels).dx, lessThan(channelsLeft - 200));

      await tester.tap(find.byKey(const Key('live.categories.show')));
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
      expect(settings.saved.hiddenCategoryLists, isEmpty);
    });

    testWidgets('each section has its own state', (tester) async {
      await _pump(
        tester,
        saved: const AppSettings(hiddenCategoryLists: {'movies'}),
      );
      expect(find.byKey(const Key('live.categories')), findsOneWidget);
    });

    testWidgets('starts hidden when saved hidden', (tester) async {
      await _pump(
        tester,
        saved: const AppSettings(hiddenCategoryLists: {'live'}),
      );
      expect(find.byKey(const Key('live.categories')), findsNothing);
      expect(find.byKey(const Key('live.categories.show')), findsOneWidget);
    });

    testWidgets('works with the keyboard; focus follows the toggle', (
      tester,
    ) async {
      await _pump(tester);
      final hide = find.byKey(const Key('live.categories.hide'));
      Focus.of(tester.element(find.text('CATEGORIES'))).requestFocus();
      await tester.pump();
      expect(_focusIn(tester, hide), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final show = find.byKey(const Key('live.categories.show'));
      expect(show, findsOneWidget);
      expect(_focusIn(tester, show), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live.categories')), findsOneWidget);
      expect(_focusIn(tester, hide), isTrue);
    });

    testWidgets('dragging its edge resizes it, within limits, remembered', (
      tester,
    ) async {
      final settings = await _pump(tester);
      final list = find.byKey(const Key('live.categories'));
      final resize = find.byKey(const Key('live.categories.resize'));
      expect(tester.getSize(list).width, AppSettings.defaultCategoryListWidth);

      await tester.drag(resize, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(list).width, 340);
      expect(settings.saved.categoryListWidth, 340);

      await tester.drag(resize, const Offset(1000, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(list).width, AppSettings.maxCategoryListWidth);

      await tester.drag(resize, const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(list).width, AppSettings.minCategoryListWidth);
      expect(
        settings.saved.categoryListWidth,
        AppSettings.minCategoryListWidth,
      );

      final region = tester.widget<MouseRegion>(
        find.descendant(of: resize, matching: find.byType(MouseRegion)),
      );
      expect(region.cursor, SystemMouseCursors.resizeColumn);
    });

    testWidgets('starts at the saved width', (tester) async {
      await _pump(tester, saved: const AppSettings(categoryListWidth: 300));
      expect(
        tester.getSize(find.byKey(const Key('live.categories'))).width,
        300,
      );
    });

    testWidgets('a cut-off name shows in full in a tooltip, on hover and on '
        'keyboard focus', (tester) async {
      const long = 'Nature and Science';
      await _pump(
        tester,
        catalog: LiveCatalog(
          categories: const [
            Category(id: 'a', name: long),
            Category(id: 'b', name: 'Short'),
          ],
          channels: const [
            LiveStream(id: '1', name: 'One', categoryIds: ['a', 'b']),
          ],
        ),
      );
      // Only the cut-off name gets a tooltip.
      expect(find.byTooltip(long), findsOneWidget);
      expect(find.byTooltip('Short'), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text(long)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(long), findsNWidgets(2), reason: 'label + tooltip');
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text(long), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Keyboard mode.
      Focus.of(tester.element(find.text(long))).requestFocus();
      await tester.pumpAndSettle();
      expect(find.text(long), findsNWidgets(2));

      Focus.of(tester.element(find.text('Short'))).requestFocus();
      await tester.pumpAndSettle();
      expect(find.text(long), findsOneWidget);
      expect(find.text('Short'), findsOneWidget, reason: 'fits: no tooltip');

      // Wider than the name: no tooltip.
      await tester.drag(
        find.byKey(const Key('live.categories.resize')),
        const Offset(1000, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip(long), findsNothing);
    });
  });
}
