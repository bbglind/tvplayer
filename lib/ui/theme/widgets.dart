import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme.dart';

/// Draws the accent focus ring around (or inside) [child] while it or one
/// of its descendants has keyboard focus, or always when [visible].
///
/// The ring shows only in keyboard mode (see `InputModeScope`): pointer
/// input hides it until the next key press. It is snapped to device
/// pixels, so the stroke and the gap to [child] are even on all sides.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.radius = AppRadius.card,
    this.inset = false,
    this.visible = false,
    this.focused,
    this.color = AppColors.accent,
  });

  final Widget child;

  /// Corner radius of [child]; the ring follows it.
  final double radius;

  /// Inside the bounds (list rows, guide cells, buttons) instead of outside
  /// (cards, posters, chips).
  final bool inset;

  /// Shows the ring without focus, e.g. for the selected row.
  final bool visible;

  /// The focus state, for widgets that track it themselves (buttons); when
  /// null the ring listens for focus inside [child].
  final bool? focused;
  final Color color;

  /// Gap between an outside ring and [child].
  static const gap = 2.0;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;
  bool _keyboard = _isKeyboard(FocusManager.instance.highlightMode);

  static bool _isKeyboard(FocusHighlightMode mode) =>
      mode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode mode) {
    final keyboard = _isKeyboard(mode);
    if (keyboard != _keyboard) setState(() => _keyboard = keyboard);
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focused ?? _focused;
    final show = widget.visible || (focused && _keyboard);
    final ring = CustomPaint(
      foregroundPainter: show
          ? _RingPainter(widget.color, widget.radius, inset: widget.inset)
          : null,
      child: widget.child,
    );
    if (widget.focused != null) return ring;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: ring,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.radius, {required this.inset});

  final Color color;
  final double radius;
  final bool inset;

  @override
  void paint(Canvas canvas, Size size) {
    // Work in device pixels: snap the ring's outer edge to the pixel grid
    // and use a whole number of pixels for the stroke, so neither the
    // stroke nor the gap is blurred more on one side than the other.
    final m = canvas.getTransform();
    final scale = m[0] > 0 ? m[0] : 1.0;
    double snap(double v, double offset) =>
        ((offset + v * scale).roundToDouble() - offset) / scale;
    final width =
        math.max(1, (AppTheme.focusWidth * scale).roundToDouble()) / scale;
    final bounds = Offset.zero & size;
    final edge = inset ? bounds : bounds.inflate(FocusRing.gap + width);
    final outer = Rect.fromLTRB(
      snap(edge.left, m[12]),
      snap(edge.top, m[13]),
      snap(edge.right, m[12]),
      snap(edge.bottom, m[13]),
    );
    final outerRadius = inset ? radius : radius + FocusRing.gap + width;
    RRect rrect(Rect r, double radius) =>
        RRect.fromRectAndRadius(r, Radius.circular(math.max(0, radius)));
    canvas.drawDRRect(
      rrect(outer, outerRadius),
      rrect(outer.deflate(width), outerRadius - width),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.radius != radius || old.inset != inset;
}

/// A [ButtonStyle.backgroundBuilder] that draws the focus ring inside a
/// button, in [color], in keyboard mode only.
ButtonLayerBuilder focusRingLayer(Color color) =>
    (context, states, child) => FocusRing(
      inset: true,
      radius: AppRadius.small,
      focused: states.contains(WidgetState.focused),
      color: color,
      child: child ?? const SizedBox.shrink(),
    );

/// A tappable rounded tile (row, card, cell) with hover, a selected state
/// (hover background + ring) and the keyboard focus ring.
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.color = AppColors.card,
    this.selectedColor = AppColors.hover,
    this.radius = AppRadius.card,
    this.padding = EdgeInsets.zero,
    this.ringInside = true,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final Color color;
  final Color selectedColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool ringInside;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return FocusRing(
      radius: radius,
      inset: ringInside,
      visible: selected,
      child: Material(
        color: selected ? selectedColor : color,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          autofocus: autofocus,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// An entry in a vertical category list: a pill, accent when selected,
/// with an optional item count.
class CategoryPill extends StatelessWidget {
  const CategoryPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fg = selected ? AppColors.onAccent : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      child: FocusRing(
        radius: AppRadius.pill,
        inset: true,
        // An accent ring doesn't show on the accent fill.
        color: selected ? AppColors.textPrimary : AppColors.accent,
        child: Material(
          color: selected ? AppColors.accent : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: selected
                ? AppColors.accentHover
                : AppColors.textPrimary.withValues(alpha: 0.07),
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TruncatedText(
                        label,
                        style: text.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$count',
                        style: text.bodySmall?.copyWith(
                          color: selected ? fg : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill search field: `surface` fill, search icon, clear button.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  static const _pill = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
    borderSide: BorderSide.none,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: hintText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            border: _pill,
            enabledBorder: _pill,
            focusedBorder: _pill.copyWith(
              borderSide: const BorderSide(
                color: AppColors.accent,
                width: AppTheme.focusWidth,
              ),
            ),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// A `surface` panel (now/next info, settings groups): radius 14,
/// padding 20.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // A Material, so list tiles inside can paint their ink on it.
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.panel)),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A thin rounded progress bar: accent fill on a `hover` track.
class ProgressStrip extends StatelessWidget {
  const ProgressStrip(this.value, {super.key, this.height = 3});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: value.clamp(0.0, 1.0),
      minHeight: height,
      color: AppColors.accent,
      backgroundColor: AppColors.hover,
      borderRadius: BorderRadius.circular(height),
    );
  }
}

/// A draggable edge for resizing a column: a resize cursor and a strip
/// [width] wide that reports horizontal drags. Place it centred on the
/// column's edge.
class ResizeHandle extends StatelessWidget {
  const ResizeHandle({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  static const width = 8.0;

  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => onStart(),
        onHorizontalDragUpdate: (d) => onUpdate(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        onHorizontalDragCancel: onEnd,
      ),
    );
  }
}

/// [Text] with an ellipsis that shows its full [text] in a tooltip when it
/// doesn't fit: on hover, and while the focusable widget around it (a
/// row's [InkWell]) has keyboard focus.
class TruncatedText extends StatefulWidget {
  const TruncatedText(this.text, {super.key, this.style, this.maxLines = 1});

  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  State<TruncatedText> createState() => _TruncatedTextState();
}

class _TruncatedTextState extends State<TruncatedText> {
  final _tooltip = GlobalKey<TooltipState>();
  FocusNode? _focus;
  bool _hadFocus = false;
  bool _truncated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final focus = Focus.maybeOf(context);
    if (focus != _focus) {
      _focus?.removeListener(_onFocus);
      _focus = focus?..addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    _focus?.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final focused = _focus?.hasPrimaryFocus ?? false;
    if (focused == _hadFocus) return;
    _hadFocus = focused;
    if (!_truncated) return;
    if (focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional) {
      _tooltip.currentState?.ensureTooltipVisible();
    } else if (!focused) {
      Tooltip.dismissAllToolTips();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: widget.text,
            style: DefaultTextStyle.of(context).style.merge(widget.style),
          ),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        _truncated = painter.didExceedMaxLines;
        painter.dispose();
        if (!_truncated) return text;
        return Tooltip(
          key: _tooltip,
          message: widget.text,
          waitDuration: const Duration(milliseconds: 500),
          child: text,
        );
      },
    );
  }
}
