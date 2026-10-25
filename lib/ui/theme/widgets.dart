import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme.dart';

/// Draws the accent focus ring around (or inside) [child] while it or one
/// of its descendants has keyboard focus, or always when [visible].
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.radius = AppRadius.card,
    this.inset = false,
    this.visible = false,
    this.color = AppColors.accent,
  });

  final Widget child;
  final double radius;

  /// Inside the bounds (list rows, guide cells) instead of outside (cards,
  /// posters).
  final bool inset;

  /// Shows the ring without focus, e.g. for the selected row.
  final bool visible;
  final Color color;

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
    final show = widget.visible || (_focused && _keyboard);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: CustomPaint(
        foregroundPainter: show
            ? _RingPainter(widget.color, widget.radius, inset: widget.inset)
            : null,
        child: widget.child,
      ),
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
    const w = AppTheme.focusWidth;
    // Outside rings keep a 1 px gap so they read against the content.
    final delta = inset ? -w / 2 : w / 2 + 1;
    final rect = (Offset.zero & size).inflate(delta);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular((radius + delta).clamp(0, double.infinity)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.radius != radius || old.inset != inset;
}

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
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
