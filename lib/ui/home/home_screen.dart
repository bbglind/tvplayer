import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../format.dart';
import '../../state/home.dart';
import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../theme/compact.dart';
import '../vod/movies_screen.dart';
import '../vod/series_screen.dart';
import 'continue_watching_screen.dart';
import 'featured_banner.dart';
import 'home_cards.dart';
import 'home_row.dart';

/// The start page: a greeting and a search field that opens the Search
/// page, then the rows of [HomeLayout] in their saved order: Featured,
/// recently viewed channels, my categories, continue watching and the
/// recently added series and movies.
///
/// It shows at once; rows whose catalogue is still loading show
/// placeholders, and rows with nothing to show are left out (my
/// categories shows a hint instead). "Edit home" moves and hides rows.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _search = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openSearch(String text) {
    if (text.trim().isEmpty) return;
    openSearch(ref, text);
  }

  void _changeLayout(HomeLayout Function(HomeLayout) apply) => ref
      .read(appSettingsProvider.notifier)
      .remember((s) => s.copyWith(homeLayout: apply(s.homeLayout)));

  @override
  Widget build(BuildContext context) {
    final layout = (ref.watch(appSettingsProvider).value ?? const AppSettings())
        .homeLayout;
    final hour = ref.watch(clockProvider).toLocal().hour;
    final rows = layout.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: greetingFor(hour),
          search: SearchField(
            key: const Key('home.search'),
            controller: _search,
            hintText: 'Search channels, movies and series',
            onChanged: _openSearch,
            onSubmitted: _openSearch,
          ),
          actions: [
            IconButton(
              key: const Key('home.edit'),
              tooltip: _editing ? 'Done' : 'Edit home',
              isSelected: _editing,
              icon: const Icon(Icons.edit_outlined, size: 20),
              selectedIcon: const Icon(Icons.check, size: 20),
              onPressed: () => setState(() => _editing = !_editing),
            ),
          ],
        ),
        Expanded(
          child: CustomScrollView(
            key: const Key('home.scroll'),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              for (final (i, row) in rows.indexed)
                if (row.visible || _editing)
                  SliverToBoxAdapter(
                    child: _buildRow(
                      context,
                      row,
                      _editing
                          ? HomeRowEdit(
                              visible: row.visible,
                              onMoveUp: i == 0
                                  ? null
                                  : () => _changeLayout(
                                      (l) => l.move(row.id, -1),
                                    ),
                              onMoveDown: i == rows.length - 1
                                  ? null
                                  : () =>
                                        _changeLayout((l) => l.move(row.id, 1)),
                              onToggle: () => _changeLayout(
                                (l) => l.withVisible(row.id, !row.visible),
                              ),
                            )
                          : null,
                    ),
                  ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ),
        ),
      ],
    );
  }

  /// One row; an empty one is left out, or in edit mode shows its heading
  /// with a note.
  Widget _buildRow(BuildContext context, HomeRow row, HomeRowEdit? edit) {
    Widget section(Widget? child, {VoidCallback? onSeeAll}) => HomeSection(
      id: row.id,
      edit: edit,
      onSeeAll: onSeeAll,
      showTitle: row.id != HomeRowId.featured,
      child: edit != null && !edit.visible ? null : child,
    );
    Widget empty() =>
        edit == null ? const SizedBox.shrink() : section(const _EmptyNote());
    switch (row.id) {
      case HomeRowId.featured:
        final featured = ref.watch(featuredProvider);
        if (featured.isEmpty) return empty();
        return section(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
            child: featured.items.isEmpty
                ? LayoutBuilder(
                    builder: (context, c) => Container(
                      key: const Key('home.placeholder'),
                      height: FeaturedBanner.height(context, c.maxWidth),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.large),
                      ),
                    ),
                  )
                : FeaturedBanner(picks: featured.items),
          ),
        );
      case HomeRowId.channels:
        final channels = ref.watch(recentChannelsProvider);
        if (channels.isEmpty) return empty();
        return section(
          HorizontalRow(
            height: RecentChannelCard.height(context),
            itemWidth: RecentChannelCard.width,
            itemCount: channels.items.length,
            loading: channels.loading,
            itemBuilder: (context, i) {
              final (channel, time) = channels.items[i];
              return RecentChannelCard(channel: channel, watchedAt: time);
            },
          ),
        );
      case HomeRowId.myCategories:
        final favourites = ref.watch(favouritesProvider);
        final categories = [
          for (final kind in ContentKind.values)
            ...favourites.categoriesOf(kind),
        ];
        return section(
          categories.every((c) => favourites.countIn(c.id) == 0)
              ? const _CategoriesHint()
              : HorizontalRow(
                  height: MyCategoryTile.height(context),
                  itemWidth: MyCategoryTile.width,
                  itemCount: categories.length,
                  itemBuilder: (context, i) =>
                      MyCategoryTile(category: categories[i]),
                ),
        );
      case HomeRowId.continueWatching:
        final items = ref.watch(homeContinueProvider);
        if (items.isEmpty) return empty();
        return section(
          HorizontalRow(
            key: const Key('home.continue'),
            height: posterCardHeight(
              context,
              continueCardWidth,
              aspectRatio: 16 / 9,
            ),
            itemWidth: continueCardWidth,
            spacing: 4,
            itemCount: items.items.length,
            loading: items.loading,
            itemBuilder: (context, i) =>
                continueCard(context, ref, items.items[i]),
          ),
          onSeeAll: () => openContinueWatching(context),
        );
      case HomeRowId.recentSeries:
        final items = ref.watch(recentSeriesProvider);
        if (items.isEmpty) return empty();
        return section(
          _posterRow(
            items.items.length,
            items.loading,
            (context, i) => seriesPoster(
              context,
              items.items[i],
              key: ValueKey('home.series.${items.items[i].seriesId}'),
            ),
          ),
          onSeeAll: () => openRecentlyAdded(ref, ContentKind.series),
        );
      case HomeRowId.recentMovies:
        final items = ref.watch(recentMoviesProvider);
        if (items.isEmpty) return empty();
        return section(
          _posterRow(
            items.items.length,
            items.loading,
            (context, i) => moviePoster(
              context,
              items.items[i],
              key: ValueKey('home.movie.${items.items[i].streamId}'),
            ),
          ),
          onSeeAll: () => openRecentlyAdded(ref, ContentKind.movie),
        );
    }
  }

  Widget _posterRow(int count, bool loading, IndexedWidgetBuilder builder) =>
      HorizontalRow(
        height: posterCardHeight(context, homePosterWidth, aspectRatio: 2 / 3),
        itemWidth: homePosterWidth,
        spacing: 4,
        itemCount: count,
        loading: loading,
        itemBuilder: builder,
      );
}

/// In edit mode, under a row that has nothing to show.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
    child: Text(
      'Nothing to show yet',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

/// Shown under "My categories" when there are none.
class _CategoriesHint extends StatelessWidget {
  const _CategoriesHint();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
      child: Panel(
        child: Row(
          children: [
            const Icon(Icons.star_border, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add favourites to my categories with the star on a channel, '
                'movie or series, or from its context menu.',
                key: const Key('home.categories.hint'),
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
