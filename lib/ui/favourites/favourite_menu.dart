import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../theme/app_colors.dart';
import 'category_dialogs.dart';
import 'category_icons.dart';

/// Creates a category for [item]'s kind and adds [item] to it.
Future<void> _addToNewCategory(
  BuildContext context,
  WidgetRef ref,
  ItemRef item,
  String name,
) async {
  final category = await createCategoryFlow(context, ref, item.kind);
  if (category == null) return;
  ref
      .read(favouritesProvider.notifier)
      .setMember(category.id, item, name: name, member: true);
}

/// Moves keyboard focus into a menu that just opened.
void _focusSoon(FocusNode node) =>
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (node.context != null) node.requestFocus();
    });

/// A checkbox per category of my categories of [item]'s kind, then "New
/// category…" and "Done". Stays open while ticking boxes (each tick is
/// saved at once); Done, Esc or a click outside closes it.
class _FavouriteMenuItems extends ConsumerWidget {
  const _FavouriteMenuItems({
    required this.item,
    required this.name,
    required this.onNew,
    this.firstFocus,
  });

  final ItemRef item;
  final String name;
  final VoidCallback onNew;

  /// For the first entry, to move keyboard focus into the menu.
  final FocusNode? firstFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourites = ref.watch(favouritesProvider);
    final categories = favourites.categoriesOf(item.kind);
    final member = favourites.categoriesContaining(item);
    final notifier = ref.read(favouritesProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in categories.indexed)
          CheckboxMenuButton(
            key: Key('favourite.menu.${c.name}'),
            focusNode: i == 0 ? firstFocus : null,
            value: member.contains(c.id),
            closeOnActivate: false,
            onChanged: (v) =>
                notifier.setMember(c.id, item, name: name, member: v ?? false),
            trailingIcon: Icon(
              categoryIcon(c.icon),
              size: 18,
              color: AppColors.textMuted,
            ),
            child: Text(c.name),
          ),
        if (categories.isNotEmpty) const Divider(height: 9),
        MenuItemButton(
          key: const Key('favourite.menu.new'),
          focusNode: categories.isEmpty ? firstFocus : null,
          leadingIcon: const Icon(Icons.add),
          onPressed: onNew,
          child: const Text('New category…'),
        ),
        const Divider(height: 9),
        // Activating a menu item closes the whole menu.
        MenuItemButton(
          key: const Key('favourite.menu.done'),
          leadingIcon: const Icon(Icons.check),
          onPressed: () {},
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// A star that opens the favourites menu for [item]: filled in accent when
/// it is in at least one of my categories. With [labelled], an outlined
/// button with text, for detail pages.
///
/// An outline star is only shown while [revealed] (e.g. the row or poster
/// is hovered), hovered itself, focused or open, so lists aren't full of
/// stars. Don't put it inside an [ItemContextMenu]: menu anchors nest, so
/// place it beside one (e.g. in a [Stack]).
class FavouriteButton extends ConsumerStatefulWidget {
  const FavouriteButton({
    super.key,
    required this.item,
    required this.name,
    this.revealed = true,
    this.labelled = false,
    this.backdrop,
  });

  final ItemRef item;

  /// The item's name, remembered with the favourite.
  final String name;
  final bool revealed;
  final bool labelled;

  /// Behind the icon, for contrast on images.
  final Color? backdrop;

  @override
  ConsumerState<FavouriteButton> createState() => _FavouriteButtonState();
}

class _FavouriteButtonState extends ConsumerState<FavouriteButton> {
  final _menu = MenuController();
  final _first = FocusNode(debugLabel: 'favourite.menu.first');
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _first.dispose();
    super.dispose();
  }

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    final favourite = ref.watch(
      favouritesProvider.select((d) => d.isFavourite(widget.item)),
    );
    final tooltip = favourite ? 'Favourite' : 'Add to favourites';
    return MenuAnchor(
      controller: _menu,
      onOpen: () {
        setState(() {});
        _focusSoon(_first);
      },
      onClose: () => setState(() {}),
      menuChildren: [
        _FavouriteMenuItems(
          item: widget.item,
          name: widget.name,
          firstFocus: _first,
          onNew: () =>
              _addToNewCategory(context, ref, widget.item, widget.name),
        ),
      ],
      builder: (context, controller, _) {
        if (widget.labelled) {
          return OutlinedButton.icon(
            key: const Key('favourite.button'),
            onPressed: _toggle,
            icon: Icon(
              favourite ? Icons.star : Icons.star_border,
              color: favourite ? AppColors.accent : null,
            ),
            label: Text(tooltip),
          );
        }
        final visible =
            favourite ||
            widget.revealed ||
            _focused ||
            _hovered ||
            controller.isOpen;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (f) => setState(() => _focused = f),
            child: Opacity(
              opacity: visible ? 1 : 0,
              child: IconButton(
                key: const Key('favourite.star'),
                tooltip: tooltip,
                style: widget.backdrop == null
                    ? null
                    : IconButton.styleFrom(backgroundColor: widget.backdrop),
                isSelected: favourite,
                icon: const Icon(Icons.star_border),
                selectedIcon: const Icon(Icons.star),
                onPressed: _toggle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// An entry of an [ItemContextMenu] besides "Add to favourites…".
@immutable
final class ItemMenuAction {
  const ItemMenuAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Key? key;
}

/// The context menu of a channel, movie or series around [child]: opened
/// by a right click, a long press (touch) or the Menu key / Shift+F10
/// while [child] has focus. It offers [actions], then "Add to
/// favourites…", which turns the menu into the favourites checkboxes in
/// place.
class ItemContextMenu extends ConsumerStatefulWidget {
  const ItemContextMenu({
    super.key,
    required this.item,
    required this.name,
    required this.child,
    this.actions = const [],
  });

  final ItemRef item;
  final String name;
  final Widget child;
  final List<ItemMenuAction> actions;

  @override
  ConsumerState<ItemContextMenu> createState() => _ItemContextMenuState();
}

class _ItemContextMenuState extends ConsumerState<ItemContextMenu> {
  final _menu = MenuController();
  final _first = FocusNode(debugLabel: 'context.menu.first');
  final _firstFavourite = FocusNode(debugLabel: 'context.favourites.first');

  /// Whether the menu shows the favourites checkboxes instead of the
  /// actions.
  bool _favourites = false;

  /// Whether the menu was opened from the keyboard, so focus moves into
  /// it.
  bool _byKeyboard = false;

  @override
  void dispose() {
    _first.dispose();
    _firstFavourite.dispose();
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

  void _showFavourites() {
    setState(() => _favourites = true);
    _focusSoon(_firstFavourite);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      onOpen: () {
        if (_byKeyboard) _focusSoon(_first);
      },
      onClose: () => setState(() => _favourites = false),
      menuChildren: [
        if (_favourites)
          _FavouriteMenuItems(
            item: widget.item,
            name: widget.name,
            firstFocus: _firstFavourite,
            onNew: () =>
                _addToNewCategory(context, ref, widget.item, widget.name),
          )
        else ...[
          for (final (i, a) in widget.actions.indexed)
            MenuItemButton(
              key: a.key,
              focusNode: i == 0 ? _first : null,
              leadingIcon: Icon(a.icon),
              onPressed: a.onPressed,
              child: Text(a.label),
            ),
          MenuItemButton(
            key: const Key('context.favourites'),
            focusNode: widget.actions.isEmpty ? _first : null,
            closeOnActivate: false,
            leadingIcon: const Icon(Icons.star_border),
            onPressed: _showFavourites,
            child: const Text('Add to favourites…'),
          ),
        ],
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
