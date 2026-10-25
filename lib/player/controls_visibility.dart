import 'dart:async';

import 'package:flutter/foundation.dart';

/// Whether the player controls show. With [autoHide] (fullscreen) they
/// show on [activity] and hide [hideAfter] later, unless something
/// [hold]s them (an open panel, keyboard focus in the controls, a drag).
/// Without it they always show.
class ControlsVisibility extends ChangeNotifier {
  ControlsVisibility({this.hideAfter = const Duration(seconds: 3)});

  final Duration hideAfter;
  bool _autoHide = false;
  bool _shown = true;
  final _holds = <Object>{};
  Timer? _timer;

  bool get visible => !_autoHide || _shown;

  bool get autoHide => _autoHide;
  set autoHide(bool value) {
    if (value == _autoHide) return;
    _autoHide = value;
    _shown = true;
    _restart();
    notifyListeners();
  }

  /// The mouse moved or a key was pressed: show, and hide again later.
  void activity() {
    if (!_autoHide) return;
    _restart();
    if (_shown) return;
    _shown = true;
    notifyListeners();
  }

  /// Keeps the controls up while [on] for [reason]; when the last hold
  /// ends they hide [hideAfter] later.
  void hold(Object reason, bool on) {
    final changed = on ? _holds.add(reason) : _holds.remove(reason);
    if (!changed) return;
    if (on && !_shown && _autoHide) {
      _shown = true;
      notifyListeners();
    }
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = _autoHide && _holds.isEmpty ? Timer(hideAfter, _hide) : null;
  }

  void _hide() {
    _timer = null;
    if (!_shown) return;
    _shown = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
