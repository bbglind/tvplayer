import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/compact.dart';
import '../theme/widgets.dart';

/// A settings group: an overline title and a panel with its rows,
/// separated by dividers. List rows get the keyboard focus ring.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  /// Whether [trailing] is small enough to stay beside the text in the
  /// phone layout: icons, switches, a spinner.
  static bool _small(Widget trailing) => switch (trailing) {
    Icon() || IconButton() || Tooltip() || Switch() || Checkbox() => true,
    SizedBox() || ProgressIndicator() => true,
    _ => false,
  };

  /// In the phone layout a tile's control (a dropdown, buttons) goes below
  /// its title and description, so the text keeps the row's width.
  static Widget stackControl(Widget tile) {
    if (tile is! ListTile) return tile;
    final trailing = tile.trailing;
    if (trailing == null || _small(trailing)) return tile;
    return ListTile(
      key: tile.key,
      leading: tile.leading,
      title: tile.title,
      enabled: tile.enabled,
      onTap: tile.onTap,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?tile.subtitle,
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(alignment: Alignment.centerLeft, child: trailing),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 12),
              Panel(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, child) in children.indexed) ...[
                      if (i > 0)
                        const Divider(height: 9, indent: 16, endIndent: 16),
                      // Buttons draw their own ring.
                      if (child is ListTile || child is SwitchListTile)
                        FocusRing(
                          radius: AppRadius.small,
                          inset: true,
                          child: compact ? stackControl(child) : child,
                        )
                      else
                        child,
                    ],
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
