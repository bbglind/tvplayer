import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/vod_controller.dart';
import '../theme/widgets.dart';

/// Categories on the left; search, a "Continue watching" row and a lazily
/// built poster grid on the right. Shared by the Movies and Series tabs.
class VodBrowser<T extends Object> extends StatefulWidget {
  const VodBrowser({
    super.key,
    required this.what,
    required this.state,
    required this.filter,
    required this.onCategory,
    required this.onQuery,
    required this.onRefresh,
    required this.itemBuilder,
    this.continueWatching = const [],
  });

  /// "movies" or "series", for labels and widget keys.
  final String what;
  final VodState<T> state;
  final VodFilter filter;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String> onQuery;
  final VoidCallback onRefresh;

  /// Builds one grid item.
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Cards for the "Continue watching" row; the row is hidden when empty
  /// and while searching.
  final List<Widget> continueWatching;

  @override
  State<VodBrowser<T>> createState() => _VodBrowserState<T>();
}

class _VodBrowserState<T extends Object> extends State<VodBrowser<T>> {
  late final _search = TextEditingController(text: widget.filter.query);

  // The filtered list, kept while catalogue and filter stay the same (e.g.
  // when only watch progress changed).
  VodCatalog<T>? _filteredCatalog;
  VodFilter? _filteredBy;
  List<T> _filtered = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<T> _items(VodCatalog<T> catalog) {
    final filter = widget.filter;
    if (!identical(catalog, _filteredCatalog) ||
        filter.categoryId != _filteredBy?.categoryId ||
        filter.query != _filteredBy?.query) {
      _filteredCatalog = catalog;
      _filteredBy = filter;
      _filtered = catalog.filter(
        categoryId: filter.categoryId,
        query: filter.query,
      );
    }
    return _filtered;
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
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: _CategoryList(
            key: Key('$what.categories'),
            what: what,
            catalog: catalog,
            selected: widget.filter.categoryId,
            onSelect: widget.onCategory,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildMain(context, catalog)),
      ],
    );
  }

  Widget _buildMain(BuildContext context, VodCatalog<T> catalog) {
    final state = widget.state;
    final what = widget.what;
    final items = _items(catalog);
    final searching = widget.filter.query.trim().isNotEmpty;
    final showContinue = !searching && widget.continueWatching.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          child: Row(
            children: [
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
                        for (final card in widget.continueWatching)
                          SizedBox(width: 150, child: card),
                      ],
                    ),
                  ),
                ),
                _sectionTitle(context, 'All $what'),
              ],
              if (items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No $what')),
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
                    itemCount: items.length,
                    itemBuilder: (context, i) =>
                        widget.itemBuilder(context, items[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    super.key,
    required this.what,
    required this.catalog,
    required this.selected,
    required this.onSelect,
  });

  final String what;
  final VodCatalog<Object> catalog;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final categories = catalog.categories;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 28, 12, 16),
      itemCount: categories.length + 1,
      itemBuilder: (context, i) {
        final category = i == 0 ? null : categories[i - 1];
        final id = category?.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CategoryPill(
            label: category?.name ?? 'All $what',
            count: id == null ? catalog.items.length : catalog.countIn(id),
            selected: id == selected,
            onTap: () => onSelect(id),
          ),
        );
      },
    );
  }
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
