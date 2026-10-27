import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// Below this window width (dp) the app uses its phone layout: bottom
/// navigation, categories in a sheet, stacked details. It goes by the
/// width, not the platform, so a desktop window keeps its layout.
const compactBreakpoint = 600.0;

/// Whether the window is narrower than [compactBreakpoint].
bool isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < compactBreakpoint;

/// Side padding of a page in the phone layout.
const compactPagePadding = 16.0;

/// What the phone layout's page header offers: the magnifier opening
/// Search ([onSearch]) and a back arrow ([onBack]) on pages reached from
/// another one (More, the Live TV guide button, Search). Put above a
/// section by the phone shell; absent in the desktop layout.
class CompactNav extends InheritedWidget {
  const CompactNav({
    super.key,
    this.onSearch,
    this.onBack,
    required super.child,
  });

  final VoidCallback? onSearch;
  final VoidCallback? onBack;

  static CompactNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompactNav>();

  @override
  bool updateShouldNotify(CompactNav old) =>
      onSearch != old.onSearch || onBack != old.onBack;
}

/// Side padding of a page: 40, or [compactPagePadding] in the phone
/// layout.
double pageSide(BuildContext context) =>
    isCompact(context) ? compactPagePadding : 40;

/// Padding around a page's content ([AppSpacing.page] outside the phone
/// layout).
EdgeInsets pagePadding(BuildContext context) => isCompact(context)
    ? const EdgeInsets.fromLTRB(compactPagePadding, 8, compactPagePadding, 24)
    : AppSpacing.page;
