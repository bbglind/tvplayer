import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_colors.dart';

/// One hint: what [owner] says, and where it is on screen.
typedef _Hint = ({Object owner, String message, Rect anchor});

/// The hint of the player control under the mouse or, failing that, the
/// one with keyboard focus; shown by [PlayerHintLine].
class PlayerHintController extends ChangeNotifier {
  _Hint? _hover;
  _Hint? _focus;
  bool _disposed = false;

  /// What the hint line shows now.
  ({String message, Rect anchor})? get current {
    final hint = _hover ?? _focus;
    return hint == null ? null : (message: hint.message, anchor: hint.anchor);
  }

  void show(Object owner, String message, Rect anchor, {required bool focus}) {
    final hint = (owner: owner, message: message, anchor: anchor);
    if (focus) {
      if (_focus == hint) return;
      _focus = hint;
    } else {
      if (_hover == hint) return;
      _hover = hint;
    }
    notifyListeners();
  }

  /// Takes away [owner]'s hover or focus hint, if it still shows.
  void hide(Object owner, {required bool focus}) {
    if (focus) {
      if (_focus?.owner != owner) return;
      _focus = null;
    } else {
      if (_hover?.owner != owner) return;
      _hover = null;
    }
    notifyListeners();
  }

  /// Takes away both hints of [owner] after this frame (for `dispose`,
  /// when the tree is locked).
  void hideLater(Object owner) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      hide(owner, focus: false);
      hide(owner, focus: true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void clear() {
    if (_hover == null && _focus == null) return;
    _hover = null;
    _focus = null;
    notifyListeners();
  }
}

/// Sends the [PlayerTooltip]s below it to a [PlayerHintLine] while
/// [controller] is set; without it they are plain tooltips.
///
/// Side panel controls ([PlayerTooltip.side]) use the hint line only with
/// [panelsInLine]; otherwise their tooltips are kept inside the right-hand
/// column of [panelWidth], beside the video.
class PlayerHintScope extends InheritedWidget {
  const PlayerHintScope({
    super.key,
    required this.controller,
    this.panelsInLine = false,
    this.panelWidth = 0,
    required super.child,
  });

  final PlayerHintController? controller;
  final bool panelsInLine;
  final double panelWidth;

  static PlayerHintScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerHintScope>();

  @override
  bool updateShouldNotify(PlayerHintScope oldWidget) =>
      controller != oldWidget.controller ||
      panelsInLine != oldWidget.panelsInLine ||
      panelWidth != oldWidget.panelWidth;
}

/// The tooltip of a player control. Over the embedded video Flutter can't
/// draw, so under a [PlayerHintScope] it shows in the [PlayerHintLine]
/// instead, on hover and on keyboard focus. Mark controls of the side
/// panels and the next-episode card with [side].
class PlayerTooltip extends StatefulWidget {
  const PlayerTooltip({
    super.key,
    required this.message,
    this.side = false,
    required this.child,
  });

  final String message;
  final bool side;
  final Widget child;

  @override
  State<PlayerTooltip> createState() => _PlayerTooltipState();
}

class _PlayerTooltipState extends State<PlayerTooltip> {
  PlayerHintController? _controller;
  bool _hovered = false;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = PlayerHintScope.maybeOf(context);
    final controller = scope == null || (widget.side && !scope.panelsInLine)
        ? null
        : scope.controller;
    if (controller == _controller) return;
    _controller?.hideLater(this);
    _controller = controller;
    _hovered = false;
    _focused = false;
  }

  @override
  void didUpdateWidget(PlayerTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_hovered) _show(focus: false);
        if (_focused) _show(focus: true);
      });
    }
  }

  @override
  void dispose() {
    _controller?.hideLater(this);
    super.dispose();
  }

  void _show({required bool focus}) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    _controller?.show(
      this,
      widget.message,
      box.localToGlobal(Offset.zero) & box.size,
      focus: focus,
    );
  }

  void _setHovered(bool value) {
    _hovered = value;
    value ? _show(focus: false) : _controller?.hide(this, focus: false);
  }

  void _setFocused(bool value) {
    // A click also focuses; only keyboard focus shows the hint.
    _focused =
        value &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    _focused ? _show(focus: true) : _controller?.hide(this, focus: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      final scope = PlayerHintScope.maybeOf(context);
      final width = scope?.controller == null ? 0.0 : scope!.panelWidth;
      if (!widget.side || width <= 0) {
        return Tooltip(message: widget.message, child: widget.child);
      }
      return Tooltip(
        message: widget.message,
        constraints: BoxConstraints(maxWidth: width - 16),
        positionDelegate: (c) => _inColumn(c, width),
        child: widget.child,
      );
    }
    return Semantics(
      tooltip: widget.message,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: _setFocused,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Flutter's usual tooltip position, moved sideways into the right-hand
/// column of [width] where the side panels sit.
Offset _inColumn(TooltipPositionContext c, double width) {
  final p = positionDependentBox(
    size: c.overlaySize,
    childSize: c.tooltipSize,
    target: c.target,
    verticalOffset: c.verticalOffset,
    preferBelow: c.preferBelow,
  );
  final left = c.overlaySize.width - width;
  final right = c.overlaySize.width - c.tooltipSize.width;
  return Offset(math.max(left, math.min(p.dx, right)), p.dy);
}

/// The line below the player controls that shows the hint of the control
/// under the mouse or with keyboard focus, under that control. Its height
/// is always kept, so the video above it never changes size.
class PlayerHintLine extends StatelessWidget {
  const PlayerHintLine({super.key, required this.controller});

  final PlayerHintController controller;

  static const _lineHeight = 1.3;
  static const _pillPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 2);
  static const _margin = EdgeInsets.fromLTRB(12, 2, 12, 4);

  /// The height of the line at the current text scale.
  static double heightOf(BuildContext context) {
    final size = Theme.of(context).textTheme.bodySmall?.fontSize ?? 13;
    return MediaQuery.textScalerOf(context).scale(size) * _lineHeight +
        _pillPadding.vertical +
        _margin.vertical;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.textPrimary, height: _lineHeight);
    return SizedBox(
      key: const Key('player.hintLine'),
      height: heightOf(context),
      child: IgnorePointer(
        child: Padding(
          padding: _margin,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final hint = controller.current;
              if (hint == null) return const SizedBox.expand();
              return _UnderAnchor(
                anchorX: hint.anchor.center.dx,
                child: DecoratedBox(
                  key: const Key('player.hint'),
                  decoration: const BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Padding(
                    padding: _pillPadding,
                    child: Text(
                      hint.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Fills the space it gets and places [child] centred under the global x
/// [anchorX], kept inside its own edges.
class _UnderAnchor extends SingleChildRenderObjectWidget {
  const _UnderAnchor({required this.anchorX, super.child});

  final double anchorX;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUnderAnchor(anchorX);

  @override
  void updateRenderObject(BuildContext context, _RenderUnderAnchor r) =>
      r.anchorX = anchorX;
}

class _RenderUnderAnchor extends RenderShiftedBox {
  _RenderUnderAnchor(this._anchorX) : super(null);

  double _anchorX;
  set anchorX(double value) {
    if (value == _anchorX) return;
    _anchorX = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(constraints.loosen(), parentUsesSize: true);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // Only now is the line's own place on screen final.
    final x = globalToLocal(Offset(_anchorX, 0)).dx - child.size.width / 2;
    final data = child.parentData! as BoxParentData;
    data.offset = Offset(
      x.clamp(0.0, math.max(0.0, size.width - child.size.width)),
      (size.height - child.size.height) / 2,
    );
    context.paintChild(child, offset + data.offset);
  }
}
