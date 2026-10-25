import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';
import 'package:tvplayer/ui/theme/app_theme.dart';

const _items = <SidebarItem>[
  (icon: Icons.live_tv_outlined, label: 'Live TV'),
  (icon: Icons.calendar_view_week_outlined, label: 'TV Guide'),
  (icon: Icons.movie_outlined, label: 'Movies'),
];
const _settings = (icon: Icons.settings_outlined, label: 'Settings');

Future<List<int>> _pump(WidgetTester tester, {bool compact = false}) async {
  final selected = <int>[];
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Row(
            children: [
              Sidebar(
                items: _items,
                bottomItem: _settings,
                selectedIndex: index,
                compact: compact,
                onSelect: (i) => setState(() {
                  index = i;
                  selected.add(i);
                }),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return selected;
}

/// Whether the focus ring of the nav item at [index] is drawn.
bool _ringShown(WidgetTester tester, int index) =>
    tester
        .widget<CustomPaint>(
          find
              .descendant(
                of: find.byKey(Key('nav.$index')),
                matching: find.byType(CustomPaint),
              )
              .first,
        )
        .foregroundPainter !=
    null;

void main() {
  testWidgets('shows the app name and labels, Settings last', (tester) async {
    final selected = await _pump(tester);
    expect(find.text('tvplayer'), findsOneWidget);
    expect(find.text('TV Guide'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Settings')).dy,
      greaterThan(tester.getTopLeft(find.text('Movies')).dy + 100),
    );

    await tester.tap(find.text('Movies'));
    await tester.pump();
    expect(selected, [2]);
  });

  testWidgets('compact shows icons only, labels as tooltips', (tester) async {
    final selected = await _pump(tester, compact: true);
    expect(find.text('tvplayer'), findsNothing);
    expect(find.text('Movies'), findsNothing);
    expect(find.byTooltip('Movies'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    expect(selected, [3]);
  });

  testWidgets('works with the keyboard and shows the focus ring', (
    tester,
  ) async {
    final selected = await _pump(tester);
    expect(_ringShown(tester, 0), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_ringShown(tester, 0), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_ringShown(tester, 0), isFalse);
    expect(_ringShown(tester, 1), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, [1]);
  });
}
