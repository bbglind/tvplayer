import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'favourite_menu.dart';

/// The items of my category [categoryId] as a list to reorder ("Reorder"
/// in Live TV, Movies and Series): a drag handle, the [leading] picture,
/// the name and [subtitle] per row. Each row's context menu (right click,
/// long press, Menu key, Shift+F10) has Move up, Move down and Move to
/// top, for the keyboard.
class ReorderItemsList extends ConsumerWidget {
  const ReorderItemsList({
    super.key,
    required this.section,
    required this.categoryId,
    required this.leading,
    required this.subtitle,
    this.padding = EdgeInsets.zero,
  });

  /// `live`, `movies` or `series`, for widget keys.
  final String section;
  final String categoryId;
  final Widget Function(BuildContext context, FavouriteMembership item) leading;
  final String? Function(FavouriteMembership item) subtitle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(favouritesProvider).itemsIn(categoryId);
    final notifier = ref.read(favouritesProvider.notifier);
    return ItemOrderScope(
      categoryId: categoryId,
      child: ReorderableListView.builder(
        key: Key('$section.reorderList'),
        buildDefaultDragHandles: false,
        padding: padding,
        itemCount: items.length,
        proxyDecorator: (child, _, _) => Material(
          color: AppColors.hover,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: child,
        ),
        onReorderItem: (from, to) =>
            notifier.moveItem(categoryId, items[from].item, to),
        itemBuilder: (context, i) => _ReorderRow(
          key: ValueKey(items[i].key),
          section: section,
          index: i,
          membership: items[i],
          leading: leading(context, items[i]),
          subtitle: subtitle(items[i]),
        ),
      ),
    );
  }
}

class _ReorderRow extends StatelessWidget {
  const _ReorderRow({
    super.key,
    required this.section,
    required this.index,
    required this.membership,
    required this.leading,
    required this.subtitle,
  });

  final String section;
  final int index;
  final FavouriteMembership membership;
  final Widget leading;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ItemContextMenu(
        item: membership.item,
        name: membership.name,
        child: AppTile(
          key: Key('$section.reorder.${membership.item.id}'),
          padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
          // Focusable for the keyboard's context menu; a click does
          // nothing while reordering.
          onTap: () {},
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Tooltip(
                  message: 'Drag to reorder',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TruncatedText(membership.name, style: text.titleMedium),
                    if (subtitle case final s?)
                      TruncatedText(
                        s,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Reorder chip of Live TV, Movies and Series for my category
/// [category]: starts and ends reordering its [what] ("channels").
class ReorderChip extends ConsumerWidget {
  const ReorderChip({
    super.key,
    required this.category,
    required this.what,
    this.onStart,
  });

  final FavouriteCategory category;
  final String what;

  /// Called when reordering starts (to clear the search).
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(itemReorderProvider) == category.id;
    return ToolbarChip(
      icon: on ? Icons.check : Icons.swap_vert,
      selected: on,
      label: on ? 'Done reordering' : 'Reorder',
      tooltip: on ? 'Done reordering' : 'Reorder the $what in ${category.name}',
      onPressed: () {
        if (!on) onStart?.call();
        ref.read(itemReorderProvider.notifier).toggle(category.id);
      },
    );
  }
}
