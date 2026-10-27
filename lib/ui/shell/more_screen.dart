import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/navigation.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/compact.dart';
import '../theme/widgets.dart';

/// "More" in the phone layout's bottom bar: the sections that don't have
/// a tab of their own (TV Guide, Downloads, Settings).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  static const entries = [
    (
      section: AppSection.guide,
      icon: Icons.calendar_view_week_outlined,
      label: 'TV Guide',
    ),
    (
      section: AppSection.downloads,
      icon: Icons.download_outlined,
      label: 'Downloads',
    ),
    (
      section: AppSection.settings,
      icon: Icons.settings_outlined,
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(title: 'More'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: compactPagePadding - 4,
              vertical: 8,
            ),
            children: [
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: Key('more.${e.section.name}'),
                      minTileHeight: 56,
                      leading: Icon(e.icon, color: AppColors.textSecondary),
                      title: Text(e.label),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                      onTap: () => ref
                          .read(appSectionProvider.notifier)
                          .select(e.section),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
