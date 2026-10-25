import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';
import 'package:tvplayer/ui/theme/app_theme.dart';
import 'package:tvplayer/ui/theme/input_mode.dart';
import 'package:tvplayer/ui/theme/widgets.dart';

const _items = <SidebarItem>[
  (icon: Icons.live_tv_outlined, label: 'Live TV'),
  (icon: Icons.calendar_view_week_outlined, label: 'TV Guide'),
  (icon: Icons.movie_outlined, label: 'Movies'),
];
const _settings = (icon: Icons.settings_outlined, label: 'Settings');

Future<void> _pump(WidgetTester tester) async {
  var index = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => InputModeScope(child: child!),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Row(
            children: [
              Sidebar(
                items: _items,
                bottomItem: _settings,
                selectedIndex: index,
                onSelect: (i) => setState(() => index = i),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    FilledButton(
                      key: const Key('play'),
                      onPressed: () {},
                      child: const Text('Play'),
                    ),
                    const SizedBox(height: 16),
                    FocusRing(
                      radius: AppRadius.pill,
                      child: ChoiceChip(
                        key: const Key('chip'),
                        label: const Text('Season 1'),
                        selected: false,
                        onSelected: (_) {},
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Whether [ring] (a [FocusRing]) draws its ring.
bool _drawn(WidgetTester tester, Finder ring) =>
    tester
        .widget<CustomPaint>(
          find.descendant(of: ring, matching: find.byType(CustomPaint)).first,
        )
        .foregroundPainter !=
    null;

/// Whether the focus ring of [finder] is drawn: a [FocusRing] around it or,
/// for buttons and nav items, inside it.
bool _ringShown(WidgetTester tester, Finder finder) {
  final inside = find.descendant(of: finder, matching: find.byType(FocusRing));
  return _drawn(
    tester,
    inside.evaluate().isNotEmpty
        ? inside.first
        : find.ancestor(of: finder, matching: find.byType(FocusRing)).first,
  );
}

Finder _nav(int i) => find.byKey(Key('nav.$i'));

FocusNode? get _focus => FocusManager.instance.primaryFocus;

bool _focusIn(WidgetTester tester, Finder finder) {
  final context = _focus?.context;
  if (context == null) return false;
  final element = tester.element(finder);
  var inside = false;
  if (context == element) return true;
  context.visitAncestorElements((e) {
    inside = e == element;
    return !inside;
  });
  return inside;
}

void main() {
  testWidgets('a mouse click moves focus to the clicked item', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusIn(tester, _nav(0)), isTrue);
    expect(_ringShown(tester, _nav(0)), isTrue);

    await tester.tap(_nav(2), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(_focusIn(tester, _nav(2)), isTrue);
    // Pointer input hides the rings.
    expect(_ringShown(tester, _nav(0)), isFalse);
    expect(_ringShown(tester, _nav(2)), isFalse);

    // The next key shows the ring again, continuing from the clicked item.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_focusIn(tester, _nav(1)), isTrue);
    expect(_ringShown(tester, _nav(1)), isTrue);
  });

  testWidgets('touch also moves focus and hides the ring', (tester) async {
    await _pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.tap(find.byKey(const Key('chip')));
    await tester.pump();
    expect(_focusIn(tester, find.byKey(const Key('chip'))), isTrue);
    expect(_ringShown(tester, find.byKey(const Key('chip'))), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      _ringShown(tester, find.byKey(const Key('chip'))),
      isFalse,
      reason: 'a modifier alone does not switch to keyboard mode',
    );
  });

  testWidgets('buttons show their ring in keyboard mode only', (tester) async {
    await _pump(tester);
    final play = find.byKey(const Key('play'));

    await tester.tap(play, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(_focusIn(tester, play), isTrue);
    expect(_ringShown(tester, play), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_focusIn(tester, play), isTrue);
    expect(_ringShown(tester, play), isTrue);
  });

  testWidgets('pressing empty space keeps the focus', (tester) async {
    await _pump(tester);
    await tester.tap(_nav(1), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tapAt(const Offset(700, 500), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(_focusIn(tester, _nav(1)), isTrue);
  });

  testWidgets('a row with a button inside takes focus itself', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => InputModeScope(child: child!),
        home: Scaffold(
          body: AppTile(
            key: const Key('row'),
            onTap: () {},
            child: Row(
              children: [
                const Expanded(child: Text('Episode')),
                IconButton(
                  key: const Key('menu'),
                  onPressed: () {},
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Episode'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(_focusIn(tester, find.byKey(const Key('row'))), isTrue);
    expect(_focusIn(tester, find.byKey(const Key('menu'))), isFalse);

    await tester.tap(
      find.byKey(const Key('menu')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(_focusIn(tester, find.byKey(const Key('menu'))), isTrue);
  });
}
