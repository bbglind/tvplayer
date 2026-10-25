import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// A section's category [list] beside its [content]. A "Categories" header
/// above the list hides it; while hidden, [content] takes the full width
/// and a [ShowCategoriesButton] in it brings the list back. The state is
/// remembered per [section] (`live`, `movies`, `series`).
class CategoryLayout extends ConsumerStatefulWidget {
  const CategoryLayout({
    super.key,
    required this.section,
    required this.width,
    required this.list,
    required this.content,
  });

  final String section;
  final double width;
  final Widget list;
  final Widget content;

  @override
  ConsumerState<CategoryLayout> createState() => _CategoryLayoutState();
}

class _CategoryLayoutState extends ConsumerState<CategoryLayout> {
  final _header = FocusNode(debugLabel: 'categories.hide');
  final _show = FocusNode(debugLabel: 'categories.show');

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

  @override
  Widget build(BuildContext context) {
    final hidden =
        ref
            .watch(appSettingsProvider)
            .value
            ?.hiddenCategoryLists
            .contains(widget.section) ??
        false;
    final content = _CategoryLayoutScope(
      hidden: hidden,
      onShow: () => _setHidden(false),
      focusNode: _show,
      child: widget.content,
    );
    if (hidden) return content;
    return Row(
      children: [
        SizedBox(
          width: widget.width,
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
