import 'package:flutter/material.dart';

/// Closes the current snack bar when a page opens or closes, so a message
/// (and its "Undo") doesn't follow the user to another page. Menus and
/// dialogs are not pages and leave it alone.
class SnackBarDismisser extends NavigatorObserver {
  void _hide(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    final context = navigator?.context;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _hide(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _hide(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _hide(newRoute);
}
