import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../favourites/category_dialogs.dart';
import '../favourites/category_icons.dart';
import '../favourites/order_actions.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';
import '../theme/compact.dart';
import 'settings_section.dart';

/// "My categories: 2 · 5 hidden", for the settings overview.
String describeCategories(FavouritesData favourites, ContentKind kind) {
  final mine = favourites.categoriesOf(kind).length;
  final hidden = favourites.hiddenIds(kind).length;
  return [
    'My categories: ${mine == 0 ? 'none' : mine}',
    if (hidden > 0) '$hidden hidden',
  ].join(' · ');
}

String _title(ContentKind kind) => switch (kind) {
  ContentKind.live => 'Live TV categories',
  ContentKind.movie => 'Movie categories',
  ContentKind.series => 'Series categories',
};

/// Where hidden categories of [kind] are left out.
String _leftOut(ContentKind kind) => switch (kind) {
  ContentKind.live => 'the category list, "All channels" and the TV guide',
  ContentKind.movie => 'the category list and "All movies"',
  ContentKind.series => 'the category list and "All series"',
};

String _items(ContentKind kind, int count) => switch (kind) {
  ContentKind.live => count == 1 ? '1 channel' : '$count channels',
  ContentKind.movie => count == 1 ? '1 movie' : '$count movies',
  ContentKind.series => '$count series',
};

/// My categories of [kind] (rename, icon, order, delete) and show/hide
/// switches for all provider categories of [kind].
class CategorySettingsScreen extends ConsumerStatefulWidget {
  const CategorySettingsScreen({super.key, required this.kind});

  final ContentKind kind;

  @override
  ConsumerState<CategorySettingsScreen> createState() =>
      _CategorySettingsScreenState();
}

class _CategorySettingsScreenState
    extends ConsumerState<CategorySettingsScreen> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// The provider's categories and their sizes; null while loading or when
  /// the provider has none of this kind.
  ({List<Category> categories, int Function(String) countIn})? _provider() {
    switch (widget.kind) {
      case ContentKind.live:
        final catalog = ref.watch(liveCatalogProvider).value;
        return catalog == null
            ? null
            : (categories: catalog.categories, countIn: catalog.countIn);
      case ContentKind.movie:
        final catalog = ref.watch(movieCatalogProvider).catalog;
        return catalog == null
            ? null
            : (categories: catalog.categories, countIn: catalog.countIn);
      case ContentKind.series:
        final catalog = ref.watch(seriesCatalogProvider).catalog;
        return catalog == null
            ? null
            : (categories: catalog.categories, countIn: catalog.countIn);
    }
  }

  /// False when the provider has no movies or series (M3U).
  bool get _supported => switch (widget.kind) {
    ContentKind.live => true,
    ContentKind.movie => ref.watch(movieCatalogProvider).supported,
    ContentKind.series => ref.watch(seriesCatalogProvider).supported,
  };

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final favourites = ref.watch(favouritesProvider);
    final notifier = ref.read(favouritesProvider.notifier);
    final mine = favourites.categoriesOf(kind);
    final hidden = favourites.hiddenIds(kind);
    final provider = _provider();
    final query = _filter.text.trim().toLowerCase();
    final listed = [
      for (final c in favourites.orderedCategories(
        kind,
        provider?.categories ?? const <Category>[],
      ))
        if (c.name.toLowerCase().contains(query)) c,
    ];
    final filtering = query.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(_title(kind))),
      body: ListView(
        padding: pagePadding(context),
        children: [
          SettingsSection(
            title: 'My categories',
            children: [
              if (mine.isEmpty)
                const ListTile(
                  title: Text('No categories yet'),
                  subtitle: Text(
                    'Create one here, or with the star on an item.',
                  ),
                ),
              for (final (i, c) in mine.indexed)
                _MyCategoryRow(
                  key: Key('settings.my.${c.name}'),
                  category: c,
                  count: favourites.countIn(c.id),
                  kind: kind,
                  first: i == 0,
                  last: i == mine.length - 1,
                  onUp: () => notifier.move(c.id, i - 1),
                  onDown: () => notifier.move(c.id, i + 1),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('settings.categories.new'),
                    onPressed: () => createCategoryFlow(context, ref, kind),
                    icon: const Icon(Icons.add),
                    label: const Text('New category'),
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Categories',
            children: [
              if (provider == null)
                ListTile(
                  title: Text(
                    _supported
                        ? 'Loading categories…'
                        : 'Not available for '
                              'this provider',
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${hidden.length} of ${provider.categories.length} '
                        'hidden. Hidden categories are left out of '
                        '${_leftOut(kind)}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      SearchField(
                        key: const Key('settings.categories.filter'),
                        controller: _filter,
                        hintText: 'Filter categories',
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            key: const Key('settings.categories.showAll'),
                            onPressed: () => notifier.setHidden(kind, [
                              for (final c in listed) c.id,
                            ], false),
                            child: Text(filtering ? 'Show these' : 'Show all'),
                          ),
                          TextButton(
                            key: const Key('settings.categories.hideAll'),
                            onPressed: () => notifier.setHidden(kind, [
                              for (final c in listed) c.id,
                            ], true),
                            child: Text(filtering ? 'Hide these' : 'Hide all'),
                          ),
                          ResetOrderButton(
                            key: const Key('settings.categories.resetOrder'),
                            kind: kind,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                for (final c in listed)
                  SwitchListTile(
                    key: Key('settings.visible.${c.id}'),
                    title: Text(c.name),
                    subtitle: Text(_items(kind, provider.countIn(c.id))),
                    value: !hidden.contains(c.id),
                    onChanged: (shown) =>
                        notifier.setHidden(kind, [c.id], !shown),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Icon, name and size of one of my categories, with buttons to edit,
/// move and delete it.
class _MyCategoryRow extends ConsumerWidget {
  const _MyCategoryRow({
    super.key,
    required this.category,
    required this.count,
    required this.kind,
    required this.first,
    required this.last,
    required this.onUp,
    required this.onDown,
  });

  final FavouriteCategory category;
  final int count;
  final ContentKind kind;
  final bool first;
  final bool last;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(categoryIcon(category.icon), color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TruncatedText(category.name, style: text.titleMedium),
                Text(_items(kind, count), style: text.bodySmall),
              ],
            ),
          ),
          IconButton(
            key: const Key('settings.my.edit'),
            tooltip: 'Rename or change icon',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => editCategoryFlow(context, ref, category),
          ),
          IconButton(
            key: const Key('settings.my.up'),
            tooltip: 'Move up',
            icon: const Icon(Icons.arrow_upward),
            onPressed: first ? null : onUp,
          ),
          IconButton(
            key: const Key('settings.my.down'),
            tooltip: 'Move down',
            icon: const Icon(Icons.arrow_downward),
            onPressed: last ? null : onDown,
          ),
          IconButton(
            key: const Key('settings.my.delete'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => deleteCategoryFlow(context, ref, category),
          ),
        ],
      ),
    );
  }
}
