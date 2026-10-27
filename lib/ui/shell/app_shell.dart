import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../state/downloads_controller.dart';
import '../../state/navigation.dart';
import '../../state/playlist_refresh.dart';
import '../../state/providers.dart';
import '../downloads/downloads_screen.dart';
import '../epg/guide_screen.dart';
import '../home/home_screen.dart';
import '../live/live_tv_screen.dart';
import '../search/search_screen.dart';
import '../settings/playlist_section.dart';
import '../settings/settings_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/compact.dart';
import '../theme/widgets.dart';
import '../vod/movies_screen.dart';
import 'more_screen.dart';
import '../vod/series_screen.dart';

/// Main layout: the sidebar plus the selected section.
///
/// The sidebar can be collapsed to icons only and resized by dragging its
/// right edge; both are remembered in [AppSettings]. Below
/// [compactBreakpoint] (a phone in portrait) a bottom bar takes its place.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Below this window width the sidebar shows icons only.
  static const compactWidth = 900.0;

  /// How long a notice such as a failed automatic refresh stays.
  static const noticeDuration = Duration(seconds: 6);

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// The width the user is dragging the sidebar to; null when not dragging.
  /// Below [AppSettings.minSidebarWidth] it previews icons only.
  double? _dragWidth;

  /// In [AppSection] order; Settings is [_settings].
  static const _sections = [
    (icon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.search, label: 'Search'),
    (icon: Icons.live_tv_outlined, label: 'Live TV'),
    (icon: Icons.calendar_view_week_outlined, label: 'TV Guide'),
    (icon: Icons.movie_outlined, label: 'Movies'),
    (icon: Icons.video_library_outlined, label: 'Series'),
    (icon: Icons.download_outlined, label: 'Downloads'),
  ];
  static const _settings = (icon: Icons.settings_outlined, label: 'Settings');

  void _remember(AppSettings Function(AppSettings) apply) =>
      ref.read(appSettingsProvider.notifier).remember(apply);

  void _toggle(bool collapsed) =>
      _remember((s) => s.copyWith(sidebarCollapsed: !collapsed));

  void _endDrag() {
    final width = _dragWidth;
    if (width == null) return;
    setState(() => _dragWidth = null);
    _remember(
      (s) => width < AppSettings.minSidebarWidth
          // Dragged below the minimum: snap to icons only and keep the last
          // full width for when it's expanded again.
          ? s.copyWith(sidebarCollapsed: true)
          : s.copyWith(
              sidebarCollapsed: false,
              sidebarWidth: width.clamp(
                AppSettings.minSidebarWidth,
                AppSettings.maxSidebarWidth,
              ),
            ),
    );
  }

  /// The quiet notice of a failed automatic refresh. It closes by itself
  /// and when another page opens, like every snack bar with an action.
  void _showRefreshFailure(AutoRefreshFailure failure) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('playlist.autoFailed'),
            duration: AppShell.noticeDuration,
            // With an action a snack bar stays until dismissed by default.
            persist: false,
            content: Text(
              "Couldn't refresh ${playlistPartsPhrase(failure.parts)}. "
              'The previous data is kept.',
            ),
            action: SnackBarAction(
              label: 'Details',
              onPressed: () => ref
                  .read(appSectionProvider.notifier)
                  .select(AppSection.settings),
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final section = ref.watch(appSectionProvider);
    // A message (and its "Undo") stays with the page it was shown on.
    ref.listen(
      appSectionProvider,
      (_, _) => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
    );
    // Keeps automatic playlist refresh running while the app is open.
    ref.listen(playlistRefreshProvider, (_, _) {});
    ref.listen(autoRefreshFailureProvider, (_, failure) {
      if (failure != null) _showRefreshFailure(failure);
    });
    // Keeps the downloads queue running while the app is open.
    ref.listen(downloadsProvider, (_, _) {});
    ref.listen(downloadNoticeProvider, (_, notice) {
      if (notice != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('downloads.notice'),
              duration: AppShell.noticeDuration,
              content: Text(notice.text),
            ),
          );
      }
    });
    if (isCompact(context)) return _buildPhone(section);
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow windows always get icons only, without the controls.
          final forced = constraints.maxWidth < AppShell.compactWidth;
          final drag = _dragWidth;
          final collapsed = drag != null
              ? drag < AppSettings.minSidebarWidth
              : settings.sidebarCollapsed;
          final compact = forced || collapsed;
          final width = compact
              ? Sidebar.compactWidth
              : (drag ?? settings.sidebarWidth).clamp(
                  AppSettings.minSidebarWidth,
                  AppSettings.maxSidebarWidth,
                );
          return Stack(
            children: [
              Row(
                children: [
                  Sidebar(
                    compact: compact,
                    width: width,
                    collapsed: collapsed,
                    onToggle: forced ? null : () => _toggle(collapsed),
                    selectedIndex: section.index,
                    onSelect: (i) => ref
                        .read(appSectionProvider.notifier)
                        .select(AppSection.values[i]),
                    items: _sections,
                    bottomItem: _settings,
                  ),
                  Expanded(child: _page(section)),
                ],
              ),
              if (!forced)
                Positioned(
                  left: width - ResizeHandle.width / 2,
                  top: 0,
                  bottom: 0,
                  width: ResizeHandle.width,
                  child: ResizeHandle(
                    key: const Key('sidebar.resize'),
                    onStart: () => setState(() => _dragWidth = width),
                    onUpdate: (dx) =>
                        setState(() => _dragWidth = (_dragWidth ?? width) + dx),
                    onEnd: _endDrag,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static Widget _page(AppSection section) => switch (section) {
    AppSection.home => const HomeScreen(),
    AppSection.search => const SearchScreen(),
    AppSection.live => const LiveTvScreen(),
    AppSection.guide => const GuideScreen(),
    AppSection.movies => const MoviesScreen(),
    AppSection.series => const SeriesScreen(),
    AppSection.downloads => const DownloadsScreen(),
    AppSection.settings => const SettingsScreen(),
    AppSection.more => const MoreScreen(),
  };

  /// The phone layout's bottom bar, in order; [AppSection.more] lists the
  /// rest.
  static const _tabs = [
    (section: AppSection.home, icon: Icons.home_outlined, label: 'Home'),
    (section: AppSection.live, icon: Icons.live_tv_outlined, label: 'Live TV'),
    (section: AppSection.movies, icon: Icons.movie_outlined, label: 'Movies'),
    (
      section: AppSection.series,
      icon: Icons.video_library_outlined,
      label: 'Series',
    ),
    (section: AppSection.more, icon: Icons.more_horiz, label: 'More'),
  ];

  /// The tab of [section]: its own, else that of the page it was opened
  /// from (Search, the guide from Live TV), else More.
  static int _tabOf(AppSection section, List<AppSection> history) {
    for (final s in [section, ...history.reversed]) {
      final i = _tabs.indexWhere((t) => t.section == s);
      if (i >= 0) return i;
    }
    return section == AppSection.search ? 0 : _tabs.length - 1;
  }

  /// The phone layout ([isCompact]): the page above a bottom bar with
  /// Home, Live TV, Movies, Series and More. Pages without a tab have a
  /// back arrow, which Android's Back does too.
  Widget _buildPhone(AppSection section) {
    final nav = ref.read(appSectionProvider.notifier);
    final history = nav.history;
    final tab = _tabOf(section, history);
    final isTab = _tabs.any((t) => t.section == section);
    final canGoBack = !isTab && history.isNotEmpty;
    final page = _page(section);
    return PopScope(
      canPop: section == AppSection.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!nav.back()) nav.open(AppSection.home);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: CompactNav(
            onSearch: section == AppSection.search
                ? null
                : () => openSearch(ref, ''),
            onBack: canGoBack ? () => nav.back() : null,
            child: switch (section) {
              // Pages that have no title row of their own get one.
              AppSection.guide || AppSection.settings => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageHeader(
                    title: section == AppSection.guide
                        ? 'TV Guide'
                        : 'Settings',
                  ),
                  Expanded(child: page),
                ],
              ),
              _ => page,
            },
          ),
        ),
        bottomNavigationBar: NavigationBar(
          key: const Key('phoneNav'),
          selectedIndex: tab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => nav.open(_tabs[i].section),
          destinations: [
            for (final t in _tabs)
              NavigationDestination(
                key: Key('phoneNav.${t.section.name}'),
                icon: Icon(t.icon),
                label: t.label,
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
/// shows icons only, with the labels as tooltips. With [onToggle] it has a
/// button to collapse ([collapsed] false) or expand it.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.items,
    required this.bottomItem,
    required this.selectedIndex,
    required this.onSelect,
    this.compact = false,
    this.width = AppSettings.defaultSidebarWidth,
    this.collapsed = false,
    this.onToggle,
  });

  /// Width when [compact].
  static const compactWidth = 76.0;

  final List<SidebarItem> items;
  final SidebarItem bottomItem;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool compact;

  /// Width when not [compact].
  final double width;
  final bool collapsed;
  final VoidCallback? onToggle;

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

  Widget? _toggleButton() {
    final onToggle = this.onToggle;
    if (onToggle == null) return null;
    return IconButton(
      key: const Key('sidebar.toggle'),
      tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      iconSize: 20,
      color: AppColors.textSecondary,
      icon: Icon(
        collapsed
            ? Icons.keyboard_double_arrow_right
            : Icons.keyboard_double_arrow_left,
      ),
      onPressed: onToggle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('sidebar'),
      width: compact ? compactWidth : width,
      color: AppColors.surface,
      padding: EdgeInsets.symmetric(
        vertical: 24,
        horizontal: compact ? 12 : 16,
      ),
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Brand(compact: compact, toggle: _toggleButton()),
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
  const _Brand({required this.compact, this.toggle});

  final bool compact;

  /// The collapse/expand button: after the name, or under the mark when
  /// [compact].
  final Widget? toggle;

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
      final brand = Semantics(
        label: 'tvplayer',
        child: Center(child: mark),
      );
      final toggle = this.toggle;
      if (toggle == null) return brand;
      return Column(children: [brand, const SizedBox(height: 12), toggle]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          mark,
          const SizedBox(width: 12),
          const Expanded(
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
          ?toggle,
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
      alignment: AlignmentDirectional.centerStart,
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
