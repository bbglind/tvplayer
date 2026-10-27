import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'category_selection.dart';
import 'global_search.dart';
import 'providers.dart';

/// The sections of the sidebar, in order; Settings sits at the bottom.
/// [more] is the phone layout's "More" page (not in the sidebar).
enum AppSection {
  home,
  search,
  live,
  guide,
  movies,
  series,
  downloads,
  settings,
  more,
}

/// The section the shell shows. The app opens on Home.
final appSectionProvider = NotifierProvider<SelectedSection, AppSection>(
  SelectedSection.new,
);

class SelectedSection extends Notifier<AppSection> {
  /// The sections opened before the current one, for [back].
  final _history = <AppSection>[];

  @override
  AppSection build() => AppSection.home;

  /// Opens [section]; [back] returns from it.
  void select(AppSection section) {
    if (section == state) return;
    // Back never goes round in circles: opening a section again drops
    // what was opened after it.
    final at = _history.indexOf(section);
    if (at >= 0) {
      _history.removeRange(at, _history.length);
    } else {
      _history.add(state);
    }
    state = section;
  }

  /// Opens [section] as a starting point, forgetting where it came from
  /// (the phone layout's bottom bar).
  void open(AppSection section) {
    _history.clear();
    state = section;
  }

  /// The sections [back] returns to, the last one first back.
  List<AppSection> get history => List.unmodifiable(_history);

  /// Returns to the section opened before; false when there is none.
  bool back() {
    if (_history.isEmpty) return false;
    state = _history.removeLast();
    return true;
  }
}

/// Opens the Search page searching for [text].
void openSearch(WidgetRef ref, String text) {
  ref.read(globalQueryProvider.notifier).set(text);
  ref.read(appSectionProvider.notifier).select(AppSection.search);
}

/// Opens the section of [category] (one of my categories) with it
/// selected and no search.
void openMyCategory(WidgetRef ref, FavouriteCategory category) {
  final selection = MyCategory(category.id);
  switch (category.kind) {
    case ContentKind.live:
      ref.read(selectedCategoryProvider.notifier).select(selection);
      ref.read(channelQueryProvider.notifier).set('');
      ref.read(appSectionProvider.notifier).select(AppSection.live);
    case ContentKind.movie:
      ref.read(movieFilterProvider.notifier).show(selection);
      ref.read(appSectionProvider.notifier).select(AppSection.movies);
    case ContentKind.series:
      ref.read(seriesFilterProvider.notifier).show(selection);
      ref.read(appSectionProvider.notifier).select(AppSection.series);
  }
}

/// Opens Movies or Series ([kind]) with everything listed, newest first
/// ("See all" of "Recently added").
void openRecentlyAdded(WidgetRef ref, ContentKind kind) {
  final series = kind == ContentKind.series;
  ref
      .read(appSettingsProvider.notifier)
      .remember(
        (s) => s.withSort(series ? 'series' : 'movies', VodSort.recent),
      );
  ref
      .read((series ? seriesFilterProvider : movieFilterProvider).notifier)
      .show(const AllCategories());
  ref
      .read(appSectionProvider.notifier)
      .select(series ? AppSection.series : AppSection.movies);
}
