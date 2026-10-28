import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/ui/shell/app_messages.dart';
import 'package:tvplayer/ui/shell/snack_bar_dismisser.dart';
import 'package:tvplayer/ui/theme/app_colors.dart';
import 'package:tvplayer/ui/theme/app_theme.dart';

void main() {
  late ScaffoldMessengerState messenger;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        navigatorObservers: [SnackBarDismisser()],
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }

  Color? barColor(WidgetTester tester) =>
      (tester.widget<Container>(find.byKey(const Key('message.bar'))).decoration
              as BoxDecoration)
          .color;

  for (final (level, color, icon) in [
    (NoticeLevel.success, AppColors.success, Icons.check_circle_outline),
    (NoticeLevel.warning, AppColors.live, Icons.warning_amber_rounded),
    (NoticeLevel.error, AppColors.live, Icons.error_outline),
  ]) {
    testWidgets('$level: bar and icon in its colour', (tester) async {
      await pump(tester);
      showAppMessage(messenger, 'Hello', level: level);
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(barColor(tester), color);
      final shown = tester.widget<Icon>(
        find.byKey(Key('message.icon.${level.name}')),
      );
      expect(shown.icon, icon);
      expect(shown.color, color);
    });
  }

  testWidgets('info looks plain', (tester) async {
    await pump(tester);
    showAppMessage(messenger, 'Hello');
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.byKey(const Key('message.bar')), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('with an action it still closes after 6 s', (tester) async {
    await pump(tester);
    showAppMessage(
      messenger,
      'Removed',
      key: const Key('m'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    );
    await tester.pumpAndSettle();
    final bar = tester.widget<SnackBar>(find.byKey(const Key('m')));
    expect(bar.persist, isFalse);
    expect(bar.duration, messageDuration);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Removed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Removed'), findsNothing);
  });

  testWidgets('a new message replaces the current one', (tester) async {
    await pump(tester);
    showAppMessage(messenger, 'First', level: NoticeLevel.error);
    await tester.pumpAndSettle();
    showAppMessage(messenger, 'Second', level: NoticeLevel.success);
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('a long message wraps beside its bar', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    showAppMessage(
      messenger,
      "Couldn't refresh channels, movies and the TV guide. "
      'The previous data is kept.',
      level: NoticeLevel.error,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final bar = tester.getSize(find.byKey(const Key('message.bar')));
    expect(bar.height, greaterThan(30));
  });
}
