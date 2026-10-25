import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';

import 'helpers.dart';

void main() {
  testWidgets('subtitle languages: remove, add and save; subtitles toggle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsStorage();
    await tester.pumpWidget(
      testApp(
        overrides: [],
        settings: settings,
        child: const Scaffold(body: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Svenska, English'), findsOneWidget);
    expect(find.text('Stream default'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings.subtitleLanguages')));
    await tester.pumpAndSettle();
    expect(find.text('1. Svenska (Swedish)'), findsOneWidget);
    expect(find.text('2. English'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Swedish'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('languages.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suomi (Finnish)').last);
    await tester.pumpAndSettle();
    expect(find.text('2. Suomi (Finnish)'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.saved.subtitleLanguages, ['en', 'fi']);
    expect(find.text('English, Suomi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings.subtitlesOn')));
    await tester.pumpAndSettle();
    expect(settings.saved.subtitlesOn, isFalse);
  });

  testWidgets('Play next episode: 30 s by default, other times or off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = FakeSettingsStorage();
    await tester.pumpWidget(
      testApp(
        overrides: [],
        settings: settings,
        child: const Scaffold(body: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const Key('settings.playNext'));
    await tester.ensureVisible(dropdown);
    expect(
      find.descendant(of: dropdown, matching: find.text('30 s')),
      findsOneWidget,
    );

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('90 s').last);
    await tester.pumpAndSettle();
    expect(settings.saved.playNextSeconds, 90);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(settings.saved.playNextSeconds, isNull);
  });
}
