import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../format.dart';
import '../../state/category_selection.dart';
import '../../state/providers.dart';
import '../../state/vod_controller.dart';
import '../shell/category_layout.dart';
import '../favourites/favourite_menu.dart';
import '../favourites/reorder_list.dart';
import '../shell/category_list.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'poster.dart';
import 'provider_title.dart';
import 'vod_filters.dart';

/// The page title and search field on top; categories on the left; sort
/// and filters, a "Continue watching" row and a lazily built poster grid
/// on the right. Shared by the Movies and Series tabs.
///
/// The search covers the whole section (except hidden categories) unless
/// "Only in …" limits it to the selected category. Sort, filters,
/// the category and the search apply together.
class VodBrowser<T extends Object> extends ConsumerStatefulWidget {
  const VodBrowser({
    super.key,
    required this.title,
    required this.what,
    required this.kind,
    required this.state,
    required this.filter,
    required this.notifier,
    required this.onRefresh,
    required this.itemBuilder,
    required this.categoryOf,
    required this.itemRef,
    required this.imageOf,
    this.continueWatching = const [],
  });

  /// The page title: "Movies" or "Series".
  final String title;

  /// "movies" or "series", for labels, settings and widget keys.
  final String what;

  /// [ContentKind.movie] or [ContentKind.series].
  final ContentKind kind;
  final VodState<T> state;
  final VodFilter filter;
  final VodFilterNotifier notifier;
  final VoidCallback onRefresh;

  /// Builds one grid item.
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// An item's provider category id.
  final String? Function(T item) categoryOf;

  /// An item's reference for my categories.
  final ItemRef Function(T item) itemRef;

  /// An item's poster, for the Reorder list.
  final String? Function(T item) imageOf;

  /// Started items with their cards for the "Continue watching" row, most
  /// recently watched first. Under "All" or a provider category only those
  /// in the selected category show; under one of my categories all show
  /// (except hidden categories), its own items first. The row is hidden
  /// when none show and while searching or filtering.
  final List<(T, Widget)> continueWatching;

  @override
  ConsumerState<VodBrowser<T>> createState() => _VodBrowserState<T>();
}

class _VodBrowserState<T extends Object> extends ConsumerState<VodBrowser<T>> {
  late final _search = TextEditingController(text: widget.filter.query);

  // The query result, kept while catalogue, filter, favourites and sort
  // stay the same (e.g. when only watch progress changed).
  VodCatalog<T>? _queriedCatalog;
  VodFilter? _queriedBy;
  FavouritesData? _queriedFavourites;
  VodSort? _queriedSort;
  List<T> _items = const [];

  // Genre counts for the menu, kept per catalogue and hidden categories.
  VodCatalog<T>? _genresCatalog;
  Set<String>? _genresHidden;
  List<({String genre, int count})> _genres = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  CategorySelection get _selection => widget.filter.category.resolve(
    ref.watch(favouritesProvider),
    widget.kind,
  );

  bool get _searching => !SearchQuery(widget.filter.query).isEmpty;

  /// Shows [category] as if the search had been cleared first.
  void _selectCategory(CategorySelection category) {
    _search.clear();
    ref.read(itemReorderProvider.notifier).stop();
    widget.notifier
      ..setQuery('')
      ..selectCategory(category);
  }

  /// Whether the search covers the whole section rather than the selected
  /// category.
  bool get _searchAll => _searching && !widget.filter.searchInCategory;

  /// Whether one of my categories is shown (not a search of the whole
  /// section): it has its own sort, with "My order".
  bool get _inMine => _selection is MyCategory && !_searchAll;

  VodSort get _sort =>
      (ref.watch(appSettingsProvider).value ?? const AppSettings()).sortOf(
        widget.what,
        mine: _inMine,
      );

  /// My category being reordered; null when not reordering.
  FavouriteCategory? get _reordering {
    if (_selection case MyCategory(:final id) when _inMine) {
      if (ref.watch(itemReorderProvider) == id) {
        return ref.watch(favouritesProvider).category(id);
      }
    }
    return null;
  }

  /// Starts reordering: without a search, in My order.
  void _startReorder() {
    _search.clear();
    widget.notifier.setQuery('');
    ref
        .read(appSettingsProvider.notifier)
        .remember((s) => s.withSort(widget.what, VodSort.myOrder, mine: true));
  }

  VodScope _scope(FavouritesData favourites) {
    final hidden = favourites.hiddenIds(widget.kind);
    if (_searchAll) return VodScope.all(hidden: hidden);
    return switch (_selection) {
      AllCategories() => VodScope.all(hidden: hidden),
      ProviderCategory(:final id) => VodScope.category(id),
      MyCategory(:final id) => VodScope.ids([
        for (final m in favourites.itemsIn(id)) ?int.tryParse(m.item.id),
      ]),
    };
  }

  List<T> _query(VodCatalog<T> catalog) {
    final filter = widget.filter;
    final favourites = ref.watch(favouritesProvider);
    final sort = _sort;
    if (!identical(catalog, _queriedCatalog) ||
        filter != _queriedBy ||
        sort != _queriedSort ||
        !identical(favourites, _queriedFavourites)) {
      _queriedCatalog = catalog;
      _queriedBy = filter;
      _queriedFavourites = favourites;
      _queriedSort = sort;
      _items = catalog.query(
        scope: _scope(favourites),
        search: filter.query,
        filters: filter.filters,
        sort: sort,
        currentYear: ref.read(clockProvider).year,
      );
    }
    return _items;
  }

  /// Genres of the whole section (except hidden categories) with their
  /// counts, so the menu stays the same while switching categories.
  List<({String genre, int count})> _genreCounts(
    VodCatalog<T> catalog,
    Set<String> hidden,
  ) {
    if (!identical(catalog, _genresCatalog) ||
        !setEquals(hidden, _genresHidden)) {
      _genresCatalog = catalog;
      _genresHidden = hidden;
      _genres = catalog.genreCounts(scope: VodScope.all(hidden: hidden));
    }
    return _genres;
  }

  /// Whether [item] belongs to the selected category: for "All", any item
  /// outside the hidden categories.
  bool _inSelection(T item, FavouritesData favourites) => switch (_selection) {
    AllCategories() =>
      !favourites.hiddenIds(widget.kind).contains(widget.categoryOf(item)),
    ProviderCategory(:final id) => widget.categoryOf(item) == id,
    MyCategory(:final id) =>
      favourites.categoriesContaining(widget.itemRef(item)).contains(id),
  };

  /// Cards for the "Continue watching" row. Under one of my categories,
  /// its own started items come first, then the rest outside the hidden
  /// categories; each part keeps its order.
  List<Widget> _continueCards(FavouritesData favourites) {
    if (_selection is! MyCategory) {
      return [
        for (final (item, card) in widget.continueWatching)
          if (_inSelection(item, favourites)) card,
      ];
    }
    final hidden = favourites.hiddenIds(widget.kind);
    final first = <Widget>[];
    final rest = <Widget>[];
    for (final (item, card) in widget.continueWatching) {
      if (_inSelection(item, favourites)) {
        first.add(card);
      } else if (!hidden.contains(widget.categoryOf(item))) {
        rest.add(card);
      }
    }
    return [...first, ...rest];
  }

  /// The name of the selected category, for the heading above the grid.
  String _selectionName(VodCatalog<T> catalog) => switch (_selection) {
    AllCategories() => 'All ${widget.what}',
    ProviderCategory(:final id) =>
      catalog.categories.where((c) => c.id == id).firstOrNull?.name ?? '',
    MyCategory(:final id) =>
      ref.watch(favouritesProvider).category(id)?.name ?? '',
  };

  /// Items of the selected one of my categories that the provider no
  /// longer lists, matching the search. Left out while searching the whole
  /// section or filtering (they have no year or genre).
  List<FavouriteMembership> _missing(VodCatalog<T> catalog) {
    if (_searchAll || !widget.filter.filters.isEmpty) return const [];
    if (_selection case MyCategory(:final id)) {
      final query = SearchQuery(widget.filter.query);
      return [
        for (final m in ref.watch(favouritesProvider).itemsIn(id))
          if (catalog.byId(int.tryParse(m.item.id) ?? m.item.id) == null &&
              query.matches(SearchKey(m.name)))
            m,
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final what = widget.what;
    final catalog = state.catalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: widget.title,
          search: state.supported
              ? SearchField(
                  key: Key('$what.search'),
                  controller: _search,
                  onChanged: widget.notifier.setQuery,
                  debounce: ref.watch(searchDebounceProvider),
                  hintText: 'Search $what',
                )
              : null,
          actions: [
            if (state.error case final error? when catalog != null)
              Tooltip(
                message: 'Last update failed: $error',
                child: Icon(
                  Icons.cloud_off,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            if (state.supported)
              IconButton(
                key: Key('$what.refresh'),
                tooltip: 'Reload $what',
                icon: const Icon(Icons.refresh),
                onPressed: state.loading ? null : widget.onRefresh,
              ),
          ],
        ),
        if (state.loading && catalog != null)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = widget.state;
    final what = widget.what;
    final catalog = state.catalog;
    if (!state.supported) {
      return Center(
        child: Text(
          'Movies and series are available for Xtream providers.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    if (catalog == null) {
      return state.error == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('Loading $what…'),
                ],
              ),
            )
          : _ErrorView(
              title: 'Could not load $what',
              message: state.error!,
              onRetry: widget.onRefresh,
            );
    }
    return CategoryLayout(
      section: what,
      headerAction: CategoryEditButton(section: what),
      list: CategoryList(
        section: what,
        kind: widget.kind,
        allLabel: 'All $what',
        categories: catalog.categories,
        allCount: catalog.countExcluding,
        countIn: catalog.countIn,
        selected: _selection,
        onSelect: _selectCategory,
      ),
      content: _buildMain(context, catalog),
    );
  }

  Widget _buildToolbar(BuildContext context, VodCatalog<T> catalog, int count) {
    final what = widget.what;
    final filter = widget.filter;
    final filters = filter.filters;
    final notifier = widget.notifier;
    final favourites = ref.watch(favouritesProvider);
    final hidden = favourites.hiddenIds(widget.kind);
    final text = Theme.of(context).textTheme;
    final mine = _inMine;
    final category = switch (_selection) {
      MyCategory(:final id) when mine => favourites.category(id),
      _ => null,
    };
    final reordering = _reordering != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShowCategoriesButton(section: what),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (category != null && (reordering || count > 0))
                  ReorderChip(
                    key: Key('$what.reorder'),
                    category: category,
                    what: what,
                    onStart: _startReorder,
                  ),
                if (!reordering) ...[
                  SortMenu(
                    section: what,
                    sort: _sort,
                    mine: mine,
                    onChanged: (sort) => ref
                        .read(appSettingsProvider.notifier)
                        .remember((s) => s.withSort(what, sort, mine: mine)),
                  ),
                  YearFilterMenu(
                    section: what,
                    filter: filters.years,
                    onChanged: (y) => notifier.setFilters(filters.withYears(y)),
                  ),
                  if (catalog.genreSource != null)
                    GenreFilterMenu(
                      section: what,
                      genres: _genreCounts(catalog, hidden),
                      selected: filters.genres,
                      onChanged: (g) =>
                          notifier.setFilters(filters.withGenres(g)),
                    ),
                  if (_searching && _selection is! AllCategories)
                    ToolbarChip(
                      key: Key('$what.onlyIn'),
                      icon: filter.searchInCategory
                          ? Icons.check
                          : Icons.filter_alt_outlined,
                      selected: filter.searchInCategory,
                      tooltip: filter.searchInCategory
                          ? 'Search all $what'
                          : 'Search only in this category',
                      label: 'Only in ${_selectionName(catalog)}',
                      onPressed: () => notifier.setSearchInCategory(
                        !filter.searchInCategory,
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    formatCountOf(
                      count,
                      what == 'series' ? 'series' : 'movie',
                      what,
                    ),
                    key: Key('$what.count'),
                    style: text.bodySmall,
                  ),
                ),
                if (!filters.isEmpty && !reordering)
                  TextButton.icon(
                    key: Key('$what.filters.reset'),
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Reset filters'),
                    onPressed: () => notifier.setFilters(const VodFilters()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain(BuildContext context, VodCatalog<T> catalog) {
    final what = widget.what;
    final items = _query(catalog);
    final missing = _missing(catalog);
    final mine = _selection is MyCategory && !_searchAll;
    final filtering = !widget.filter.filters.isEmpty;
    final favourites = ref.watch(favouritesProvider);
    final continueCards = _searching || filtering
        ? const <Widget>[]
        : _continueCards(favourites);
    final showContinue = continueCards.isNotEmpty;
    final reordering = _reordering;
    if (reordering != null) {
      return Column(
        children: [
          _buildToolbar(context, catalog, favourites.countIn(reordering.id)),
          Expanded(
            child: ReorderItemsList(
              section: what,
              categoryId: reordering.id,
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              leading: (context, m) {
                final item = catalog.byId(int.tryParse(m.item.id) ?? m.item.id);
                return SizedBox(
                  width: 40,
                  height: 60,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: Poster(
                      url: item == null ? null : widget.imageOf(item),
                      decodeWidth: 80,
                      placeholder: item == null
                          ? Icons.block
                          : Icons.movie_outlined,
                    ),
                  ),
                );
              },
              subtitle: (m) =>
                  catalog.byId(int.tryParse(m.item.id) ?? m.item.id) == null
                  ? 'Not available'
                  : null,
            ),
          ),
        ],
      );
    }
    // Move up/down/to top in my category in My order; they pass over items
    // left out by the search or filters.
    final orderScope = mine && _sort == VodSort.myOrder
        ? switch (_selection) {
            MyCategory(:final id) => (
              id,
              {for (final item in items) widget.itemRef(item).id},
            ),
            _ => null,
          }
        : null;
    final grid = CustomScrollView(
      key: Key('$what.grid'),
      slivers: [
        if (showContinue) ...[
          _sectionTitle(context, 'Continue watching'),
          SliverToBoxAdapter(
            child: SizedBox(
              key: Key('$what.continue'),
              height: 270,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                children: [
                  for (final card in continueCards)
                    SizedBox(width: 150, child: card),
                ],
              ),
            ),
          ),
          _sectionTitle(context, _selectionName(catalog)),
        ],
        if (items.isEmpty && missing.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                mine && !_searching && !filtering
                    ? 'No $what yet. Add some with the star on a '
                          'poster.'
                    : _searching || filtering
                    ? 'No $what found'
                    : 'No $what',
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
            // Only the visible posters are built.
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 0.52,
              ),
              itemCount: items.length + missing.length,
              // Posters keep their state (and keyboard focus) when
              // they move.
              findChildIndexCallback: (key) {
                if (key case ValueKey<String>(:final value)) {
                  final i = items.indexWhere(
                    (item) => 'item.${widget.itemRef(item).id}' == value,
                  );
                  if (i >= 0) return i;
                  final j = missing.indexWhere(
                    (m) => 'missing.${m.item.id}' == value,
                  );
                  if (j >= 0) return items.length + j;
                }
                return null;
              },
              itemBuilder: (context, i) => i < items.length
                  ? KeyedSubtree(
                      key: ValueKey('item.${widget.itemRef(items[i]).id}'),
                      child: widget.itemBuilder(context, items[i]),
                    )
                  : _missingCard(context, missing[i - items.length]),
            ),
          ),
      ],
    );
    return Column(
      children: [
        _buildToolbar(context, catalog, items.length + missing.length),
        Expanded(
          child: switch (orderScope) {
            (final id, final shown) => ItemOrderScope(
              categoryId: id,
              shown: shown,
              child: grid,
            ),
            null => grid,
          },
        ),
      ],
    );
  }

  /// An item of my category that the provider no longer lists: its
  /// remembered name and the star to remove it.
  Widget _missingCard(BuildContext context, FavouriteMembership m) =>
      PosterCard(
        key: ValueKey('missing.${m.item.id}'),
        title: m.name,
        subtitle: 'Not available',
        imageUrl: null,
        placeholder: Icons.block,
        favourite: m.item,
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The provider no longer lists “${plainTitle(ref, m.name)}”.',
            ),
          ),
        ),
      );

  Widget _sectionTitle(BuildContext context, String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
