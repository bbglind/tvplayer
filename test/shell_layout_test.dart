import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';

import 'helpers.dart';

Future<FakeSettingsStorage> _pump(
  WidgetTester tester, {
  AppSettings saved = const AppSettings(),
  double width = 1400,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = FakeSettingsStorage(saved);
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(
          FakeLiveSource(syntheticCatalog(count: 20, categories: 2)),
        ),
      ],
      settings: settings,
      child: const AppShell(),
    ),
  );
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
      final search = find.byKey(const Key('live.search'));
      expect(list, findsOneWidget);
      expect(find.byTooltip('Hide categories'), findsOneWidget);
      final searchLeft = tester.getTopLeft(search).dx;

      await tester.tap(find.byKey(const Key('live.categories.hide')));
      await tester.pumpAndSettle();
      expect(list, findsNothing);
      expect(settings.saved.hiddenCategoryLists, {'live'});
      expect(find.byTooltip('Show categories'), findsOneWidget);
      // The content takes the freed width.
      expect(tester.getTopLeft(search).dx, lessThan(searchLeft - 200));

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
  });
}
