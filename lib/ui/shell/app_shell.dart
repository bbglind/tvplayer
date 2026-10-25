import 'package:flutter/material.dart';

import '../epg/guide_screen.dart';
import '../live/live_tv_screen.dart';
import '../settings/settings_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../vod/movies_screen.dart';
import '../vod/series_screen.dart';

/// Main layout: the sidebar plus the selected section.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Below this window width the sidebar shows icons only.
  static const compactWidth = 900.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _sections = [
    (icon: Icons.live_tv_outlined, label: 'Live TV'),
    (icon: Icons.calendar_view_week_outlined, label: 'TV Guide'),
    (icon: Icons.movie_outlined, label: 'Movies'),
    (icon: Icons.video_library_outlined, label: 'Series'),
  ];
  static const _settings = (icon: Icons.settings_outlined, label: 'Settings');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Sidebar(
              compact: constraints.maxWidth < AppShell.compactWidth,
              selectedIndex: _index,
              onSelect: (i) => setState(() => _index = i),
              items: _sections,
              bottomItem: _settings,
            ),
            Expanded(
              child: switch (_index) {
                0 => const LiveTvScreen(),
                1 => const GuideScreen(),
                2 => const MoviesScreen(),
                3 => const SeriesScreen(),
                _ => const SettingsScreen(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

typedef SidebarItem = ({IconData icon, String label});

/// The left navigation: app mark and name, [items] from the top and
/// [bottomItem] at the bottom (its index is `items.length`). [compact]
/// shows icons only, with the labels as tooltips.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.items,
    required this.bottomItem,
    required this.selectedIndex,
    required this.onSelect,
    this.compact = false,
  });

  final List<SidebarItem> items;
  final SidebarItem bottomItem;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool compact;

  Widget _item(int index, SidebarItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: _SidebarButton(
      key: Key('nav.$index'),
      icon: item.icon,
      label: item.label,
      selected: index == selectedIndex,
      compact: compact,
      onTap: () => onSelect(index),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('sidebar'),
      width: compact ? 76 : 232,
      color: AppColors.surface,
      padding: EdgeInsets.symmetric(
        vertical: 24,
        horizontal: compact ? 12 : 16,
      ),
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Brand(compact: compact),
            const SizedBox(height: 28),
            for (final (i, item) in items.indexed) _item(i, item),
            const Spacer(),
            _item(items.length, bottomItem),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        size: 22,
        color: AppColors.onAccent,
      ),
    );
    if (compact) {
      return Semantics(
        label: 'tvplayer',
        child: Center(child: mark),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 12),
          const Flexible(
            child: Text(
              'tvplayer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.textPrimary : AppColors.textSecondary;
    final content = Stack(
      children: [
        if (selected)
          const Positioned(
            left: 0,
            top: 10,
            bottom: 10,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: fg),
              if (!compact) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final button = Semantics(
      button: true,
      selected: selected,
      label: compact ? label : null,
      child: FocusRing(
        radius: AppRadius.small,
        inset: true,
        child: Material(
          color: selected ? AppColors.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.small),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(height: 44, child: content),
          ),
        ),
      ),
    );
    return compact
        ? Tooltip(message: label, preferBelow: false, child: button)
        : button;
  }
}
