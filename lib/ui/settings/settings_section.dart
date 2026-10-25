import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
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
                          child: child,
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
