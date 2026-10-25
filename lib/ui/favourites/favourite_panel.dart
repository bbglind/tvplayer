import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'category_icons.dart';

/// My categories for [item] as a side panel, with a field to add a new
/// one. For places where menus and dialogs can't be drawn, like next to
/// the embedded mpv video, which covers anything Flutter draws over it.
class FavouritePanel extends ConsumerStatefulWidget {
  const FavouritePanel({
    super.key,
    required this.item,
    required this.name,
    this.onClose,
  });

  final ItemRef item;
  final String name;
  final VoidCallback? onClose;

  @override
  ConsumerState<FavouritePanel> createState() => _FavouritePanelState();
}

class _FavouritePanelState extends ConsumerState<FavouritePanel> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final notifier = ref.read(favouritesProvider.notifier);
    final category = notifier.create(
      widget.item.kind,
      _name.text,
      defaultCategoryIcon,
    );
    if (category == null) return;
    notifier.setMember(
      category.id,
      widget.item,
      name: widget.name,
      member: true,
    );
    _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favourites = ref.watch(favouritesProvider);
    final member = favourites.categoriesContaining(widget.item);
    final notifier = ref.read(favouritesProvider.notifier);
    return Material(
      key: const Key('player.favourites'),
      color: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                  child: Text(
                    'MY CATEGORIES',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
            ],
          ),
          for (final c in favourites.categoriesOf(widget.item.kind))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: FocusRing(
                radius: AppRadius.small,
                inset: true,
                child: CheckboxListTile(
                  key: Key('player.favourite.${c.name}'),
                  dense: true,
                  value: member.contains(c.id),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: Icon(
                    categoryIcon(c.icon),
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  title: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (v) => notifier.setMember(
                    c.id,
                    widget.item,
                    name: widget.name,
                    member: v ?? false,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('player.favourite.newName'),
                    controller: _name,
                    maxLength: maxFavouriteNameLength,
                    decoration: const InputDecoration(
                      hintText: 'New category',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                IconButton(
                  key: const Key('player.favourite.create'),
                  tooltip: 'Create and add',
                  icon: const Icon(Icons.add),
                  onPressed: _create,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
