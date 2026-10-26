import 'dart:async';
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
    this.focusNode,
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
  final FocusNode? focusNode;

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
          focusNode: focusNode,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// An entry in a vertical category list: a pill, accent when selected,
/// with an optional leading [icon] and item count. [dimmed] shows a hidden
/// entry; set [checked] when tapping toggles something rather than
/// selecting.
class CategoryPill extends StatelessWidget {
  const CategoryPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.icon,
    this.dimmed = false,
    this.checked,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final IconData? icon;
  final bool dimmed;
  final bool? checked;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fg = selected
        ? AppColors.onAccent
        : dimmed
        ? AppColors.textDisabled
        : AppColors.textSecondary;
    Widget pill = Material(
      color: selected ? AppColors.accent : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: selected
            ? AppColors.accentHover
            : AppColors.textPrimary.withValues(alpha: 0.07),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: EdgeInsets.only(left: icon == null ? 16 : 12, right: 16),
            child: Row(
              children: [
                if (icon case final icon?) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TruncatedText(
                    label,
                    style: text.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: text.bodySmall?.copyWith(
                      color: selected
                          ? fg
                          : dimmed
                          ? AppColors.textDisabled
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip case final message?) {
      pill = Tooltip(message: message, child: pill);
    }
    return Semantics(
      selected: checked == null ? selected : null,
      checked: checked,
      child: FocusRing(
        radius: AppRadius.pill,
        inset: true,
        // An accent ring doesn't show on the accent fill.
        color: selected ? AppColors.textPrimary : AppColors.accent,
        child: pill,
      ),
    );
  }
}

/// The pill search field: `surface` fill, search icon, clear button.
/// With a [debounce], [onChanged] is called once typing pauses for that
/// long (the clear button and [onSubmitted] report at once), so heavy
/// searches don't run on every key press.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.debounce = Duration.zero,
    this.focusNode,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Duration debounce;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  static const _pill = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
    borderSide: BorderSide.none,
  );

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    if (widget.debounce == Duration.zero) {
      widget.onChanged(text);
    } else {
      _timer = Timer(widget.debounce, () {
        // Cleared or changed from outside meanwhile (e.g. a category click).
        if (widget.controller.text == text) widget.onChanged(text);
      });
    }
  }

  void _now(String text) {
    _timer?.cancel();
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return SizedBox(
      height: 44,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onChanged: _changed,
          onSubmitted: (text) {
            _now(text);
            widget.onSubmitted?.call(text);
          },
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: widget.hintText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            border: SearchField._pill,
            enabledBorder: SearchField._pill,
            focusedBorder: SearchField._pill.copyWith(
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
                      _now('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// The title row of a page: the page title (h1) on the left, and on the
/// right an optional [search] field (up to [searchWidth] wide) followed by
/// [actions]. Page padding: 28 at the top, 40 at the sides.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.search,
    this.actions = const [],
    this.searchWidth = 380,
  });

  final String title;
  final Widget? search;
  final List<Widget> actions;
  final double searchWidth;

  @override
  Widget build(BuildContext context) {
    final search = this.search;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 16),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(width: 24),
          if (search != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: searchWidth),
                  child: search,
                ),
              ),
            )
          else
            const Spacer(),
          if (actions.isNotEmpty) ...[const SizedBox(width: 8), ...actions],
        ],
      ),
    );
  }
}

/// A chip in a toolbar (sort, filters, search scope): pill, height 40,
/// `surface` normally and accent while [selected]. With [dropdown] it shows
/// an arrow, for chips that open a menu. Long labels are cut off at
/// [maxLabelWidth].
class ToolbarChip extends StatelessWidget {
  const ToolbarChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.dropdown = false,
    this.icon,
    this.tooltip,
    this.maxLabelWidth = 260,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;
  final bool dropdown;
  final IconData? icon;
  final String? tooltip;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.onAccent : AppColors.textSecondary;
    final chip = FocusRing(
      radius: AppRadius.pill,
      child: FilterChip(
        // No padded tap target, so the ring hugs the chip.
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        selected: selected,
        avatar: icon == null ? null : Icon(icon, color: color),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabelWidth),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (dropdown) ...[
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 20, color: color),
            ],
          ],
        ),
        onSelected: onPressed == null ? null : (_) => onPressed!(),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
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

/// A channel [number] (or nothing) in a column as wide as five digits at
/// the current text scale, followed by [gap], so numbers never wrap and
/// the names after them line up.
class ChannelNumber extends StatelessWidget {
  const ChannelNumber(this.number, {super.key, this.style, this.gap = 8});

  final int? number;
  final TextStyle? style;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    final painter = TextPainter(
      text: TextSpan(text: '88888', style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble() + gap;
    painter.dispose();
    return SizedBox(
      width: width,
      child: Text(
        number == null ? '' : '$number',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: this.style,
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
