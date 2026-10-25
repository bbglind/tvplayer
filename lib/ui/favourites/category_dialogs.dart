import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';
import 'category_icons.dart';

/// Asks for a new category of [kind] and creates it; null when cancelled.
Future<FavouriteCategory?> createCategoryFlow(
  BuildContext context,
  WidgetRef ref,
  ContentKind kind,
) async {
  final result = await showDialog<({String name, String icon})>(
    context: context,
    builder: (_) => const _CategoryEditor(title: 'New category'),
  );
  if (result == null) return null;
  return ref
      .read(favouritesProvider.notifier)
      .create(kind, result.name, result.icon);
}

/// Lets the user rename [category] and change its icon.
Future<void> editCategoryFlow(
  BuildContext context,
  WidgetRef ref,
  FavouriteCategory category,
) async {
  final result = await showDialog<({String name, String icon})>(
    context: context,
    builder: (_) => _CategoryEditor(
      title: 'Edit category',
      name: category.name,
      icon: category.icon,
    ),
  );
  if (result == null) return;
  ref
      .read(favouritesProvider.notifier)
      .edit(category.id, name: result.name, icon: result.icon);
}

/// Deletes [category] after asking.
Future<void> deleteCategoryFlow(
  BuildContext context,
  WidgetRef ref,
  FavouriteCategory category,
) async {
  final count = ref.read(favouritesProvider).countIn(category.id);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete “${category.name}”?'),
      content: Text(
        count == 0
            ? 'The category is empty.'
            : 'Its ${count == 1 ? 'item is' : '$count items are'} removed '
                  'from it. They stay available in the provider categories.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('category.delete.confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  ref.read(favouritesProvider.notifier).delete(category.id);
}

/// Name field and icon choice; pops `(name:, icon:)` on save.
class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.title,
    this.name = '',
    this.icon = defaultCategoryIcon,
  });

  final String title;
  final String name;
  final String icon;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.name);
  late String _icon = categoryIcons.containsKey(widget.icon)
      ? widget.icon
      : defaultCategoryIcon;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => cleanFavouriteName(_name.text) != null;

  void _save() {
    if (!_valid) return;
    Navigator.pop(context, (name: _name.text, icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('category.name'),
                controller: _name,
                autofocus: true,
                maxLength: maxFavouriteNameLength,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              Text('ICON', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final MapEntry(:key, :value) in categoryIcons.entries)
                    IconButton(
                      key: Key('category.icon.$key'),
                      tooltip: key[0].toUpperCase() + key.substring(1),
                      isSelected: key == _icon,
                      style:
                          IconButton.styleFrom(
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.textSecondary,
                          ).copyWith(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? AppColors.accent
                                  : AppColors.card,
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? AppColors.onAccent
                                  : AppColors.textSecondary,
                            ),
                            // An accent ring doesn't show on the accent fill.
                            backgroundBuilder: (context, states, child) =>
                                focusRingLayer(
                                  states.contains(WidgetState.selected)
                                      ? AppColors.textPrimary
                                      : AppColors.accent,
                                )(context, states, child),
                          ),
                      icon: Icon(value),
                      onPressed: () => setState(() => _icon = key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('category.save'),
          onPressed: _valid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
