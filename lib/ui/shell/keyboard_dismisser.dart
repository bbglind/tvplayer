import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Takes focus from a text field and closes the on-screen keyboard.
///
/// Losing focus alone should close the keyboard, but on Android it may
/// stay open (seen after opening a search result), so it is also told to
/// hide.
void dismissKeyboard() {
  final focus = FocusManager.instance.primaryFocus;
  if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() !=
      null) {
    focus!.unfocus();
  }
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

/// Closes the on-screen keyboard when a page opens, so it doesn't follow
/// the user from a search field to a details page or the player. Menus
/// and dialogs are not pages and leave it alone.
class KeyboardDismisser extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && previousRoute != null) dismissKeyboard();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PageRoute) dismissKeyboard();
  }
}
