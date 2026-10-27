import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/category_selection.dart';
import '../../state/providers.dart';
import '../favourites/category_dialogs.dart';
import '../favourites/category_icons.dart';
import '../favourites/order_actions.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// The category list of Live TV, Movies or Series: "My categories" with a
/// "New category" button, then "All …" and the provider categories that
/// aren't hidden, in the user's order.
///
/// In edit mode ([CategoryEditButton]) my categories can be reordered
/// (drag handle, or Move up/down in their menu), edited and deleted, and
/// every provider category shows a drag handle and an eye toggle to hide
/// or show it. The context menu of a provider category (right click, long
/// press, Menu key, Shift+F10) has Move up, Move down and Move to top.
class CategoryList extends ConsumerWidget {
  const CategoryList({
    super.key,
    required this.section,
    required this.kind,
    required this.allLabel,
    required this.categories,
    required this.allCount,
    required this.countIn,
    required this.selected,
    required this.onSelect,
  });

  /// `live`, `movies` or `series`, for widget keys and the edit mode.
  final String section;
  final ContentKind kind;

  /// "All channels" etc.
  final String allLabel;

  /// All provider categories, hidden ones included, in the provider's
  /// order.
  final List<Category> categories;

  /// Number of items outside the given hidden categories.
  final int Function(Set<String> hidden) allCount;

  /// Number of items in a provider category.
  final int Function(String id) countIn;

  /// The current selection, already [CategorySelection.resolve]d.
  final CategorySelection selected;
  final ValueChanged<CategorySelection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourites = ref.watch(favouritesProvider);
    final editing = ref.watch(categoryEditingProvider) == section;
    final notifier = ref.read(favouritesProvider.notifier);
    final mine = favourites.categoriesOf(kind);
    final hidden = favourites.hiddenIds(kind);
    final ordered = favourites.orderedCategories(kind, categories);
    final orderedIds = [for (final c in ordered) c.id];
    final shown = editing
        ? ordered
        : [
            for (final c in ordered)
              if (!hidden.contains(c.id)) c,
          ];

    /// [pill] of provider category [c] with its context menu.
    Widget withMenu(Category c, Widget pill) => _ProviderCategoryMenu(
      section: section,
      kind: kind,
      categories: categories,
      ids: orderedIds,
      id: c.id,
      // Outside edit mode hidden categories aren't shown, so moves pass
      // over them.
      skip: editing ? const {} : hidden,
      child: pill,
    );

    int? indexOfKey(Key key) {
      if (key case ValueKey<String>(:final value)) {
        final i = shown.indexWhere((c) => 'provider.${c.id}' == value);
        if (i >= 0) return i;
      }
      return null;
    }

    Widget pad(Widget child) =>
        Padding(padding: const EdgeInsets.only(bottom: 4), child: child);

    return CustomScrollView(
      key: Key('$section.categories'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 16),
          sliver: SliverMainAxisGroup(
            slivers: [
              const SliverToBoxAdapter(child: _Overline('My categories')),
              if (editing)
                SliverReorderableList(
                  itemCount: mine.length,
                  findChildIndexCallback: (key) {
                    final i = mine.indexWhere((c) => ValueKey(c.id) == key);
                    return i < 0 ? null : i;
                  },
                  proxyDecorator: (child, _, _) => Material(
                    color: AppColors.hover,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: child,
                  ),
                  onReorderItem: (from, to) => notifier.move(mine[from].id, to),
                  itemBuilder: (context, i) => _MyCategoryEditRow(
                    key: ValueKey(mine[i].id),
                    section: section,
                    category: mine[i],
                    index: i,
                    count: mine.length,
                  ),
                )
              else
                SliverList.list(
                  children: [
                    for (final c in mine)
                      pad(
                        CategoryPill(
                          key: Key('$section.my.${c.name}'),
                          icon: categoryIcon(c.icon),
                          label: c.name,
                          count: favourites.countIn(c.id),
                          selected: selected == MyCategory(c.id),
                          onTap: () => onSelect(MyCategory(c.id)),
                        ),
                      ),
                  ],
                ),
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: Key('$section.categories.new'),
                    onPressed: () => createCategoryFlow(context, ref, kind),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New category'),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (editing) ...[
                const SliverToBoxAdapter(child: _Overline('Categories')),
                SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        key: Key('$section.categories.showAll'),
                        onPressed: hidden.isEmpty
                            ? null
                            : () => notifier.setHidden(kind, hidden, false),
                        child: const Text('Show all'),
                      ),
                      TextButton(
                        key: Key('$section.categories.hideAll'),
                        onPressed: hidden.length == categories.length
                            ? null
                            : () => notifier.setHidden(kind, [
                                for (final c in categories) c.id,
                              ], true),
                        child: const Text('Hide all'),
                      ),
                      ResetOrderButton(
                        key: Key('$section.categories.resetOrder'),
                        kind: kind,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SliverToBoxAdapter(
                  child: Divider(height: 1, indent: 16, endIndent: 16),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: pad(
                    CategoryPill(
                      label: allLabel,
                      count: allCount(hidden),
                      selected: selected == const AllCategories(),
                      onTap: () => onSelect(const AllCategories()),
                    ),
                  ),
                ),
              ],
              if (editing)
                SliverReorderableList(
                  itemCount: shown.length,
                  findChildIndexCallback: indexOfKey,
                  proxyDecorator: (child, _, _) => Material(
                    color: AppColors.hover,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: child,
                  ),
                  onReorderItem: (from, to) => notifier.moveProvider(
                    kind,
                    categories,
                    shown[from].id,
                    to,
                  ),
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    final isHidden = hidden.contains(c.id);
                    return Padding(
                      key: ValueKey('provider.${c.id}'),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          _DragHandle(index: i),
                          Expanded(
                            child: withMenu(
                              c,
                              CategoryPill(
                                key: Key('$section.visibility.${c.id}'),
                                icon: isHidden
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                label: c.name,
                                count: countIn(c.id),
                                selected: false,
                                dimmed: isHidden,
                                checked: !isHidden,
                                tooltip: isHidden
                                    ? 'Hidden: show'
                                    : 'Shown: hide',
                                onTap: () =>
                                    notifier.setHidden(kind, [c.id], !isHidden),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              else
                SliverList.builder(
                  itemCount: shown.length,
                  findChildIndexCallback: indexOfKey,
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    return Padding(
                      key: ValueKey('provider.${c.id}'),
                      padding: const EdgeInsets.only(bottom: 4),
                      child: withMenu(
                        c,
                        CategoryPill(
                          key: Key('$section.category.${c.id}'),
                          label: c.name,
                          count: countIn(c.id),
                          selected: selected == ProviderCategory(c.id),
                          onTap: () => onSelect(ProviderCategory(c.id)),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Switches the category list of [section] in and out of edit mode.
class CategoryEditButton extends ConsumerWidget {
  const CategoryEditButton({super.key, required this.section});

  final String section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = ref.watch(categoryEditingProvider) == section;
    return IconButton(
      key: Key('$section.categories.edit'),
      tooltip: editing ? 'Done editing' : 'Edit categories',
      isSelected: editing,
      icon: const Icon(Icons.edit_outlined, size: 20),
      selectedIcon: const Icon(Icons.check, size: 20),
      onPressed: () =>
          ref.read(categoryEditingProvider.notifier).toggle(section),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

/// One of my categories in edit mode: drag handle, icon, name and a menu
/// with Edit, Move up/down and Delete.
class _MyCategoryEditRow extends ConsumerWidget {
  const _MyCategoryEditRow({
    super.key,
    required this.section,
    required this.category,
    required this.index,
    required this.count,
  });

  final String section;
  final FavouriteCategory category;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            _DragHandle(index: index),
            Icon(
              categoryIcon(category.icon),
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TruncatedText(
                category.name,
                style: text.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            CategoryActionsMenu(
              key: Key('$section.my.${category.name}.actions'),
              category: category,
              index: index,
              count: count,
            ),
          ],
        ),
      ),
    );
  }
}

/// A ⋯ button with Edit, Move up, Move to top, Move down and Delete for
/// [category], which is at [index] of [count] categories.
class CategoryActionsMenu extends ConsumerWidget {
  const CategoryActionsMenu({
    super.key,
    required this.category,
    required this.index,
    required this.count,
  });

  final FavouriteCategory category;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(favouritesProvider.notifier);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const Key('category.action.edit'),
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => editCategoryFlow(context, ref, category),
          child: const Text('Rename or change icon…'),
        ),
        MenuItemButton(
          key: const Key('category.action.up'),
          leadingIcon: const Icon(Icons.arrow_upward),
          onPressed: index == 0
              ? null
              : () => notifier.move(category.id, index - 1),
          child: const Text('Move up'),
        ),
        MenuItemButton(
          key: const Key('category.action.top'),
          leadingIcon: Icon(moveStepIcon(MoveStep.top)),
          onPressed: index == 0 ? null : () => notifier.move(category.id, 0),
          child: Text(moveStepLabel(MoveStep.top)),
        ),
        MenuItemButton(
          key: const Key('category.action.down'),
          leadingIcon: const Icon(Icons.arrow_downward),
          onPressed: index >= count - 1
              ? null
              : () => notifier.move(category.id, index + 1),
          child: const Text('Move down'),
        ),
        MenuItemButton(
          key: const Key('category.action.delete'),
          leadingIcon: const Icon(Icons.delete_outline),
          onPressed: () => deleteCategoryFlow(context, ref, category),
          child: const Text('Delete…'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Actions for ${category.name}',
        icon: const Icon(Icons.more_vert, size: 20),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// The drag handle of row [index] of a reorderable list.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: const Tooltip(
        message: 'Drag to reorder',
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Icon(
              Icons.drag_indicator,
              size: 20,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The context menu of the provider category [id] around [child]: Move
/// up, Move down and Move to top in [ids] (the user's order), passing over
/// [skip]. Opened by a right click, a long press (touch) or the Menu key /
/// Shift+F10 while [child] has focus.
class _ProviderCategoryMenu extends ConsumerStatefulWidget {
  const _ProviderCategoryMenu({
    required this.section,
    required this.kind,
    required this.categories,
    required this.ids,
    required this.id,
    required this.skip,
    required this.child,
  });

  final String section;
  final ContentKind kind;

  /// The provider's categories, in its order.
  final List<Category> categories;
  final List<String> ids;
  final String id;
  final Set<String> skip;
  final Widget child;

  @override
  ConsumerState<_ProviderCategoryMenu> createState() =>
      _ProviderCategoryMenuState();
}

class _ProviderCategoryMenuState extends ConsumerState<_ProviderCategoryMenu> {
  final _menu = MenuController();
  final _first = FocusNode(debugLabel: 'category.menu.first');

  /// Whether the menu was opened from the keyboard, so focus moves into
  /// it.
  bool _byKeyboard = false;

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  void _openAt(Offset position) {
    _byKeyboard = false;
    _menu.open(position: position);
  }

  void _openByKeyboard() {
    _byKeyboard = true;
    _menu.open();
  }

  @override
  Widget build(BuildContext context) {
    final targets = {
      for (final step in MoveStep.values)
        step: moveTarget(widget.ids, widget.id, step, skip: widget.skip),
    };
    final firstEnabled = MoveStep.values
        .where((s) => targets[s] != null)
        .firstOrNull;
    return MenuAnchor(
      controller: _menu,
      onOpen: () {
        if (_byKeyboard) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (_first.context != null) _first.requestFocus();
          });
        }
      },
      menuChildren: [
        for (final step in MoveStep.values)
          MenuItemButton(
            key: Key('${widget.section}.categoryMenu.${step.name}'),
            focusNode: step == firstEnabled ? _first : null,
            leadingIcon: Icon(moveStepIcon(step)),
            onPressed: switch (targets[step]) {
              final to? =>
                () => ref
                    .read(favouritesProvider.notifier)
                    .moveProvider(
                      widget.kind,
                      widget.categories,
                      widget.id,
                      to,
                    ),
              null => null,
            },
            child: Text(moveStepLabel(step)),
          ),
      ],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.contextMenu):
              _openByKeyboard,
          const SingleActivator(LogicalKeyboardKey.f10, shift: true):
              _openByKeyboard,
        },
        child: GestureDetector(
          onSecondaryTapUp: (d) => _openAt(d.localPosition),
          onLongPressStart: (d) => _openAt(d.localPosition),
          child: widget.child,
        ),
      ),
    );
  }
}
