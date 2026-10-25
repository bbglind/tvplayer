import 'package:flutter/material.dart';

import '../../data/home_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Height of one line of [style] at the current text scale.
double lineHeight(BuildContext context, TextStyle? style) =>
    MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
    (style?.height ?? 1.3);

/// Edit controls of a row on the start page in "Edit home" mode.
@immutable
final class HomeRowEdit {
  const HomeRowEdit({
    required this.visible,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggle,
  });

  final bool visible;

  /// Null for the first (up) or last (down) row.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onToggle;
}

/// A row of the start page: its heading (with "See all" or, in edit mode,
/// move and hide buttons) above [child]. Without [child] only the heading
/// shows, e.g. for a hidden row in edit mode.
class HomeSection extends StatelessWidget {
  const HomeSection({
    super.key,
    required this.id,
    this.child,
    this.onSeeAll,
    this.edit,
    this.showTitle = true,
  });

  final HomeRowId id;
  final Widget? child;
  final VoidCallback? onSeeAll;

  /// The edit controls while editing; null otherwise.
  final HomeRowEdit? edit;

  /// Whether the heading shows outside edit mode (Featured has none).
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final edit = this.edit;
    final dimmed = edit != null && !edit.visible;
    final child = this.child;
    final key = 'home.row.${id.name}';
    final heading = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: [
          Expanded(
            child: Text(
              id.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dimmed
                  ? text.titleLarge?.copyWith(color: AppColors.textDisabled)
                  : text.titleLarge,
            ),
          ),
          if (edit != null) ...[
            IconButton(
              key: Key('$key.up'),
              tooltip: 'Move up',
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: edit.onMoveUp,
            ),
            IconButton(
              key: Key('$key.down'),
              tooltip: 'Move down',
              icon: const Icon(Icons.arrow_downward, size: 20),
              onPressed: edit.onMoveDown,
            ),
            IconButton(
              key: Key('$key.visible'),
              tooltip: edit.visible ? 'Hide row' : 'Show row',
              icon: Icon(
                edit.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: edit.onToggle,
            ),
          ] else if (onSeeAll case final onSeeAll?)
            TextButton(
              key: Key('$key.seeAll'),
              onPressed: onSeeAll,
              child: const Text('See all'),
            ),
        ],
      ),
    );
    return Padding(
      key: Key(key),
      padding: const EdgeInsets.only(bottom: AppSpacing.section - 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle || edit != null) ...[
            heading,
            const SizedBox(height: AppSpacing.inSection - 4),
          ],
          ?child,
        ],
      ),
    );
  }
}

/// A horizontally scrolling row of [itemCount] items, each [itemWidth]
/// wide and [height] high, with [loading] placeholder cards while it is
/// empty.
///
/// The vertical mouse wheel scrolls the page; the row scrolls with
/// Shift+wheel, horizontal touchpad swipes, the arrow buttons that show at
/// its ends while hovered, and as keyboard focus moves along it.
class HorizontalRow extends StatefulWidget {
  const HorizontalRow({
    super.key,
    required this.height,
    required this.itemWidth,
    required this.itemCount,
    required this.itemBuilder,
    this.loading = false,
    this.spacing = 12,
    this.placeholderRadius = AppRadius.card,
  });

  final double height;
  final double itemWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool loading;
  final double spacing;
  final double placeholderRadius;

  /// Placeholder cards while loading.
  static const placeholders = 6;

  @override
  State<HorizontalRow> createState() => _HorizontalRowState();
}

class _HorizontalRowState extends State<HorizontalRow> {
  final _controller = ScrollController();
  bool _hovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int direction) {
    final position = _controller.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.itemCount == 0 && widget.loading;
    final count = placeholder ? HorizontalRow.placeholders : widget.itemCount;
    final list = ListView.separated(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      itemCount: count,
      separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
      itemBuilder: (context, i) => SizedBox(
        width: widget.itemWidth,
        child: placeholder
            ? DecoratedBox(
                key: const Key('home.placeholder'),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(widget.placeholderRadius),
                ),
              )
            : widget.itemBuilder(context, i),
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: widget.height,
        child: FocusTraversalGroup(
          child: Stack(
            children: [
              Positioned.fill(child: list),
              if (_hovered && !placeholder)
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      if (!_controller.hasClients) return const SizedBox();
                      final p = _controller.position;
                      return Stack(
                        children: [
                          if (p.pixels > p.minScrollExtent)
                            _arrow(Alignment.centerLeft, -1),
                          if (p.pixels < p.maxScrollExtent)
                            _arrow(Alignment.centerRight, 1),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _arrow(Alignment alignment, int direction) => Positioned.fill(
    child: Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // The keyboard moves along the row with the arrow keys instead.
        child: ExcludeFocus(
          child: IconButton(
            tooltip: direction < 0 ? 'Scroll left' : 'Scroll right',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surface.withValues(alpha: 0.92),
              minimumSize: const Size(44, 44),
            ),
            icon: Icon(
              direction < 0 ? Icons.chevron_left : Icons.chevron_right,
              color: AppColors.textPrimary,
            ),
            onPressed: () => _page(direction),
          ),
        ),
      ),
    ),
  );
}
