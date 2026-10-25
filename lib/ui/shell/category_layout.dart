import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// A section's category [list] beside its [content]. A "Categories" header
/// above the list hides it; while hidden, [content] takes the full width
/// and a [ShowCategoriesButton] in it brings the list back. The state is
/// remembered per [section] (`live`, `movies`, `series`). The list's right
/// edge can be dragged to resize it; the width is shared by all sections.
class CategoryLayout extends ConsumerStatefulWidget {
  const CategoryLayout({
    super.key,
    required this.section,
    required this.list,
    required this.content,
  });

  final String section;
  final Widget list;
  final Widget content;

  @override
  ConsumerState<CategoryLayout> createState() => _CategoryLayoutState();
}

class _CategoryLayoutState extends ConsumerState<CategoryLayout> {
  final _header = FocusNode(debugLabel: 'categories.hide');
  final _show = FocusNode(debugLabel: 'categories.show');

  /// The width the user is dragging the list to; null when not dragging.
  double? _dragWidth;

  @override
  void dispose() {
    _header.dispose();
    _show.dispose();
    super.dispose();
  }

  void _setHidden(bool hidden) {
    // Keep keyboard focus on the toggle, which moves between the header
    // and the show button.
    final hadFocus = _header.hasFocus || _show.hasFocus;
    ref
        .read(appSettingsProvider.notifier)
        .remember(
          (s) => s.copyWith(
            hiddenCategoryLists: {
              ...s.hiddenCategoryLists.where((x) => x != widget.section),
              if (hidden) widget.section,
            },
          ),
        );
    if (hadFocus) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) (hidden ? _show : _header).requestFocus();
      });
    }
  }

  void _endDrag() {
    final width = _dragWidth;
    if (width == null) return;
    setState(() => _dragWidth = null);
    ref
        .read(appSettingsProvider.notifier)
        .remember((s) => s.copyWith(categoryListWidth: _clamp(width)));
  }

  static double _clamp(double width) => width.clamp(
    AppSettings.minCategoryListWidth,
    AppSettings.maxCategoryListWidth,
  );

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final hidden = settings.hiddenCategoryLists.contains(widget.section);
    final width = _clamp(_dragWidth ?? settings.categoryListWidth);
    final content = _CategoryLayoutScope(
      hidden: hidden,
      onShow: () => _setHidden(false),
      focusNode: _show,
      child: widget.content,
    );
    if (hidden) return content;
    final row = Row(
      children: [
        SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 12, 8),
                child: _CategoriesHeader(
                  key: Key('${widget.section}.categories.hide'),
                  focusNode: _header,
                  onTap: () => _setHidden(true),
                ),
              ),
              Expanded(child: widget.list),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ],
    );
    return Stack(
      children: [
        row,
        Positioned(
          left: width + 0.5 - ResizeHandle.width / 2,
          top: 0,
          bottom: 0,
          width: ResizeHandle.width,
          child: ResizeHandle(
            key: Key('${widget.section}.categories.resize'),
            onStart: () => setState(() => _dragWidth = width),
            onUpdate: (dx) =>
                setState(() => _dragWidth = (_dragWidth ?? width) + dx),
            onEnd: _endDrag,
          ),
        ),
      ],
    );
  }
}

class _CategoryLayoutScope extends InheritedWidget {
  const _CategoryLayoutScope({
    required this.hidden,
    required this.onShow,
    required this.focusNode,
    required super.child,
  });

  final bool hidden;
  final VoidCallback onShow;
  final FocusNode focusNode;

  @override
  bool updateShouldNotify(_CategoryLayoutScope old) =>
      hidden != old.hidden || focusNode != old.focusNode;
}

/// "Categories" with a collapse chevron; tapping it hides the list.
class _CategoriesHeader extends StatelessWidget {
  const _CategoriesHeader({
    super.key,
    required this.focusNode,
    required this.onTap,
  });

  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hide categories',
      child: Semantics(
        button: true,
        child: FocusRing(
          radius: AppRadius.small,
          inset: true,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.small),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              focusNode: focusNode,
              onTap: onTap,
              child: SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'CATEGORIES',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_left,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brings back a hidden category list: put it at the start of the
/// content's top row inside a [CategoryLayout]. Takes no space while the
/// list is shown.
class ShowCategoriesButton extends StatelessWidget {
  const ShowCategoriesButton({super.key, required this.section});

  /// For the widget key; matches [CategoryLayout.section].
  final String section;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_CategoryLayoutScope>();
    if (scope == null || !scope.hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        key: Key('$section.categories.show'),
        focusNode: scope.focusNode,
        tooltip: 'Show categories',
        icon: const Icon(Icons.chevron_right),
        onPressed: scope.onShow,
      ),
    );
  }
}
