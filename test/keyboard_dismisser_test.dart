import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/ui/shell/keyboard_dismisser.dart';

void main() {
  testWidgets('opening a page unfocuses a text field and tells the '
      'keyboard to hide', (tester) async {
    final field = FocusNode();
    addTearDown(field.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [KeyboardDismisser()],
        home: Scaffold(body: TextField(focusNode: field)),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(field.hasFocus, isTrue);

    tester.testTextInput.log.clear();
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('Details')),
    );
    await tester.pumpAndSettle();
    expect(field.hasFocus, isFalse);
    expect(
      tester.testTextInput.log.map((c) => c.method),
      contains('TextInput.hide'),
    );
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
