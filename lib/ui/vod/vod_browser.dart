import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/category_selection.dart';
import '../../state/providers.dart';
import '../../state/vod_controller.dart';
import '../shell/category_layout.dart';
import '../shell/category_list.dart';
import '../theme/widgets.dart';
import 'poster.dart';

/// Categories on the left; search, a "Continue watching" row and a lazily
/// built poster grid on the right. Shared by the Movies and Series tabs.
class VodBrowser<T extends Object> extends ConsumerStatefulWidget {
  const VodBrowser({
    super.key,
    required this.what,
    required this.kind,
    required this.state,
    required this.filter,
    required this.onCategory,
    required this.onQuery,
    required this.onRefresh,
    required this.itemBuilder,
    required this.categoryOf,
    required this.itemRef,
    this.continueWatching = const [],
  });

  /// "movies" or "series", for labels and widget keys.
  final String what;

  /// [ContentKind.movie] or [ContentKind.series].
  final ContentKind kind;
  final VodState<T> state;
  final VodFilter filter;
  final ValueChanged<CategorySelection> onCategory;
  final ValueChanged<String> onQuery;
  final VoidCallback onRefresh;

  /// Builds one grid item.
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// An item's provider category id.
  final String? Function(T item) categoryOf;

  /// An item's reference for my categories.
  final ItemRef Function(T item) itemRef;

  /// Started items with their cards for the "Continue watching" row, most
  /// recently watched first. Under "All" or a provider category only those
  /// in the selected category show; under one of my categories all show
  /// (except hidden categories), its own items first. The row is hidden
  /// when none show and while searching.
  final List<(T, Widget)> continueWatching;

  @override
  ConsumerState<VodBrowser<T>> createState() => _VodBrowserState<T>();
}

class _VodBrowserState<T extends Object> extends ConsumerState<VodBrowser<T>> {
  late final _search = TextEditingController(text: widget.filter.query);

  // The filtered list, kept while catalogue, filter and favourites stay the
  // same (e.g. when only watch progress changed).
  VodCatalog<T>? _filteredCatalog;
  VodFilter? _filteredBy;
  FavouritesData? _filteredFavourites;
  List<T> _filtered = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  CategorySelection get _selection => widget.filter.category.resolve(
    ref.watch(favouritesProvider),
    widget.kind,
  );

  List<T> _items(VodCatalog<T> catalog) {
    final filter = widget.filter;
    final favourites = ref.watch(favouritesProvider);
    if (!identical(catalog, _filteredCatalog) ||
        filter.category != _filteredBy?.category ||
        filter.query != _filteredBy?.query ||
        !identical(favourites, _filteredFavourites)) {
      _filteredCatalog = catalog;
      _filteredBy = filter;
      _filteredFavourites = favourites;
      _filtered = switch (_selection) {
        AllCategories() => catalog.filter(
          query: filter.query,
          hidden: favourites.hiddenIds(widget.kind),
        ),
        ProviderCategory(:final id) => catalog.filter(
          categoryId: id,
          query: filter.query,
        ),
        MyCategory(:final id) => catalog.pick([
          for (final m in favourites.itemsIn(id)) ?int.tryParse(m.item.id),
        ], query: filter.query),
      };
    }
    return _filtered;
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
  /// longer lists, matching the search.
  List<FavouriteMembership> _missing(VodCatalog<T> catalog) {
    if (_selection case MyCategory(:final id)) {
      final query = widget.filter.query.trim().toLowerCase();
      return [
        for (final m in ref.watch(favouritesProvider).itemsIn(id))
          if (catalog.byId(int.tryParse(m.item.id) ?? m.item.id) == null &&
              m.name.toLowerCase().contains(query))
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
        onSelect: widget.onCategory,
      ),
      content: _buildMain(context, catalog),
    );
  }

  Widget _buildMain(BuildContext context, VodCatalog<T> catalog) {
    final state = widget.state;
    final what = widget.what;
    final items = _items(catalog);
    final missing = _missing(catalog);
    final mine = _selection is MyCategory;
    final searching = widget.filter.query.trim().isNotEmpty;
    final favourites = ref.watch(favouritesProvider);
    final continueCards = searching
        ? const <Widget>[]
        : _continueCards(favourites);
    final showContinue = continueCards.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          child: Row(
            children: [
              ShowCategoriesButton(section: what),
              Expanded(
                child: SearchField(
                  key: Key('$what.search'),
                  controller: _search,
                  onChanged: widget.onQuery,
                  hintText: 'Search $what',
                ),
              ),
              const SizedBox(width: 8),
              if (state.error case final error?)
                Tooltip(
                  message: 'Last update failed: $error',
                  child: Icon(
                    Icons.cloud_off,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              IconButton(
                key: Key('$what.refresh'),
                tooltip: 'Reload $what',
                icon: const Icon(Icons.refresh),
                onPressed: state.loading ? null : widget.onRefresh,
              ),
            ],
          ),
        ),
        if (state.loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: CustomScrollView(
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
                      mine && !searching
                          ? 'No $what yet. Add some with the star on a '
                                'poster.'
                          : 'No $what',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                  // Only the visible posters are built.
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          childAspectRatio: 0.52,
                        ),
                    itemCount: items.length + missing.length,
                    itemBuilder: (context, i) => i < items.length
                        ? widget.itemBuilder(context, items[i])
                        : _missingCard(context, missing[i - items.length]),
                  ),
                ),
            ],
          ),
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
          SnackBar(content: Text('The provider no longer lists “${m.name}”.')),
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
