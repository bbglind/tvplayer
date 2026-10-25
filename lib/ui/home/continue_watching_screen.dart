import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/home.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'home_cards.dart';
import 'home_row.dart';

/// Opens the Continue watching page ("See all" on Home).
void openContinueWatching(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const ContinueWatchingScreen()));

/// Which started items the Continue watching page shows.
enum ContinueFilter {
  all('All'),
  movies('Movies'),
  series('Series');

  const ContinueFilter(this.label);

  final String label;

  bool accepts(ContinueItem item) => switch (this) {
    all => true,
    movies => item is ContinueMovieItem,
    series => item is ContinueSeriesItem,
  };
}

/// Every started movie and series as 16:9 cards, most recently watched
/// first and without hidden categories, with chips to show only movies or
/// series. Cards work as in the Home row.
class ContinueWatchingScreen extends ConsumerStatefulWidget {
  const ContinueWatchingScreen({super.key});

  @override
  ConsumerState<ContinueWatchingScreen> createState() =>
      _ContinueWatchingScreenState();
}

class _ContinueWatchingScreenState
    extends ConsumerState<ContinueWatchingScreen> {
  ContinueFilter _filter = ContinueFilter.all;

  static const _spacing = 4.0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeContinueProvider);
    final items = state.items.where(_filter.accepts).toList();
    final placeholder = items.isEmpty && state.loading;
    return Scaffold(
      appBar: AppBar(title: const Text('Continue watching')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 8, 40, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in ContinueFilter.values)
                  ToolbarChip(
                    key: Key('continue.filter.${f.name}'),
                    label: f.label,
                    selected: f == _filter,
                    onPressed: () => setState(() => _filter = f),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty && !placeholder
                ? Center(
                    child: Text(
                      'Nothing to continue',
                      key: const Key('continue.empty'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) =>
                        _grid(context, c.maxWidth, items, placeholder),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    double width,
    List<ContinueItem> items,
    bool placeholder,
  ) {
    const padding = EdgeInsets.fromLTRB(40, 0, 40, 28);
    final inner = width - padding.horizontal;
    final columns = math.max(
      1,
      ((inner + _spacing) / (continueCardWidth + _spacing)).floor(),
    );
    final cellWidth = (inner - (columns - 1) * _spacing) / columns;
    return GridView.builder(
      key: const Key('continue.grid'),
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: _spacing,
        mainAxisSpacing: _spacing,
        mainAxisExtent: posterCardHeight(
          context,
          cellWidth,
          aspectRatio: 16 / 9,
        ),
      ),
      itemCount: placeholder ? HorizontalRow.placeholders : items.length,
      itemBuilder: (context, i) => placeholder
          ? DecoratedBox(
              key: const Key('home.placeholder'),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            )
          : continueCard(context, ref, items[i]),
    );
  }
}
