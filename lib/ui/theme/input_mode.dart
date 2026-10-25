import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps keyboard focus and focus rings in step with how the app is used:
///
/// * A pointer press moves focus to the innermost focusable widget under
///   it, so the next key press continues from what was clicked.
/// * Pointer input hides focus rings (touch highlight mode); the next key
///   press shows them again (traditional highlight mode).
///
/// Wrap the app once, e.g. in `MaterialApp.builder`.
class InputModeScope extends StatefulWidget {
  const InputModeScope({super.key, required this.child});

  final Widget child;

  @override
  State<InputModeScope> createState() => _InputModeScopeState();
}

class _InputModeScopeState extends State<InputModeScope> {
  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  static void _setStrategy(FocusHighlightStrategy strategy) {
    final manager = FocusManager.instance;
    if (manager.highlightStrategy != strategy) {
      manager.highlightStrategy = strategy;
    }
  }

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    _setStrategy(FocusHighlightStrategy.alwaysTouch);
    final target = focusTargetAt(event.position, event.viewId);
    if (target != null && !target.hasPrimaryFocus) target.requestFocus();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && !_modifiers.contains(event.logicalKey)) {
      _setStrategy(FocusHighlightStrategy.alwaysTraditional);
    }
    return false;
  }

  static final _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The innermost focusable node whose widget is hit at [position], or null.
/// Uses a hit test, so widgets covered by others (e.g. under a dialog) are
/// never chosen. Focus scopes and nodes holding them (the navigator) don't
/// count, so pressing empty space keeps the current focus.
@visibleForTesting
FocusNode? focusTargetAt(Offset position, int viewId) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, viewId);
  final depth = <RenderObject, int>{};
  for (final (i, entry) in result.path.indexed) {
    if (entry.target case final RenderObject object) {
      depth.putIfAbsent(object, () => i);
    }
  }
  FocusNode? best;
  var bestDepth = result.path.length;
  // Descendants come before their ancestors, so on a tie (several nodes
  // over the same render object) the innermost one is kept.
  for (final node in FocusManager.instance.rootScope.descendants) {
    if (node is FocusScopeNode || !node.canRequestFocus) continue;
    if (node.descendants.any((d) => d is FocusScopeNode)) continue;
    final context = node.context;
    if (context == null || !context.mounted) continue;
    final d = depth[context.findRenderObject()];
    if (d != null && d < bestDepth) {
      best = node;
      bestDepth = d;
    }
  }
  return best;
}
