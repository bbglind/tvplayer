import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/global_search.dart';
import '../../state/providers.dart';
import '../live/live_tv_screen.dart';
import '../theme/app_colors.dart';
import '../vod/movies_screen.dart';
import '../vod/series_screen.dart';
import '../theme/widgets.dart';

/// A group of results on the Search page.
enum _Group {
  live('Live TV', 'channels', 'channel'),
  movies('Movies', 'movies', 'movie'),
  series('Series', 'series', 'series');

  const _Group(this.title, this.plural, this.singular);

  final String title;
  final String plural;
  final String singular;
}

/// The Search page: one field (focused when the page opens) searching
/// channels, movies and series at once. Results are grouped with their
/// counts; each group shows its best matches and "Show all" lists all of
/// them. Enter in the field moves to the first result; Enter or a click
/// on a result plays the channel or opens the movie or series.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  /// How many channels and posters a group shows before "Show all".
  static const previewChannels = 5;
  static const previewPosters = 12;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  // With the cursor at the end, so typing started on Home continues.
  late final _search = TextEditingController.fromValue(
    TextEditingValue(
      text: ref.read(globalQueryProvider),
      selection: TextSelection.collapsed(
        offset: ref.read(globalQueryProvider).length,
      ),
    ),
  );
  final _field = FocusNode(debugLabel: 'search.field');
  final _firstResult = FocusNode(debugLabel: 'search.first');

  /// The group listed in full ("Show all"), if any.
  _Group? _expanded;

  @override
  void dispose() {
    _search.dispose();
    _field.dispose();
    _firstResult.dispose();
    super.dispose();
  }

  void _focusFirst() {
    if (_firstResult.context != null) _firstResult.requestFocus();
  }

  void _collapse() {
    setState(() => _expanded = null);
    _field.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(globalSearchProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Search',
          searchWidth: 560,
          search: SearchField(
            key: const Key('search.field'),
            controller: _search,
            focusNode: _field,
            autofocus: true,
            debounce: ref.watch(searchDebounceProvider),
            hintText: 'Search channels, movies and series',
            onChanged: ref.read(globalQueryProvider.notifier).set,
            onSubmitted: (_) => WidgetsBinding.instance.addPostFrameCallback(
              (_) => _focusFirst(),
            ),
          ),
        ),
        if (results.searching)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(child: _buildBody(context, results)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, GlobalSearchState results) {
    if (SearchQuery(results.query).isEmpty) {
      return _buildStart(context, results);
    }
    if (_expanded case final group?) {
      return CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _collapse},
        child: _buildExpanded(context, results, group),
      );
    }
    final groups = [
      for (final g in _Group.values)
        if (_status(results, g) != SearchGroupStatus.unsupported) g,
    ];
    final first = groups.where((g) => _count(results, g) > 0).firstOrNull;
    return CustomScrollView(
      key: const Key('search.results'),
      slivers: [
        for (final g in groups) ...[
          SliverToBoxAdapter(child: _groupHeading(context, results, g)),
          ..._groupPreview(context, results, g, focusFirst: g == first),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  /// Before anything is typed: what can be searched, and which catalogues
  /// are still loading.
  Widget _buildStart(BuildContext context, GlobalSearchState results) {
    final text = Theme.of(context).textTheme;
    final loading = [
      for (final g in _Group.values)
        if (_status(results, g) == SearchGroupStatus.loading) g.plural,
    ];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Find channels, movies and series',
            style: text.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (loading.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              key: const Key('search.loading'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Loading ${loading.join(', ')}…',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static SearchGroupStatus _status(GlobalSearchState r, _Group g) =>
      switch (g) {
        _Group.live => r.live.status,
        _Group.movies => r.movies.status,
        _Group.series => r.series.status,
      };

  static String? _error(GlobalSearchState r, _Group g) => switch (g) {
    _Group.live => r.live.error,
    _Group.movies => r.movies.error,
    _Group.series => r.series.error,
  };

  static int _count(GlobalSearchState r, _Group g) => switch (g) {
    _Group.live => r.live.items.length,
    _Group.movies => r.movies.items.length,
    _Group.series => r.series.items.length,
  };

  static int _preview(_Group g) => g == _Group.live
      ? SearchScreen.previewChannels
      : SearchScreen.previewPosters;

  Widget _groupHeading(
    BuildContext context,
    GlobalSearchState results,
    _Group g,
  ) {
    final text = Theme.of(context).textTheme;
    final status = _status(results, g);
    final count = _count(results, g);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 12),
      child: Row(
        children: [
          Text(g.title, style: text.titleLarge),
          if (status == SearchGroupStatus.ready) ...[
            const SizedBox(width: 10),
            Text(
              formatCount(count),
              key: Key('search.${g.name}.count'),
              style: text.bodySmall,
            ),
          ],
          const Spacer(),
          if (count > _preview(g))
            TextButton(
              key: Key('search.${g.name}.all'),
              onPressed: () => setState(() => _expanded = g),
              child: const Text('Show all'),
            ),
        ],
      ),
    );
  }

  /// A line under a group heading: loading, an error or no matches.
  Widget? _groupMessage(
    BuildContext context,
    GlobalSearchState results,
    _Group g,
  ) {
    final text = Theme.of(context).textTheme;
    final Widget message = switch (_status(results, g)) {
      SearchGroupStatus.loading => Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Loading ${g.plural}…', style: text.bodySmall),
        ],
      ),
      SearchGroupStatus.error => Text(
        'Could not load ${g.plural}: ${_error(results, g) ?? ''}',
        style: text.bodySmall,
      ),
      _ when _count(results, g) == 0 && !results.searching => Text(
        'No ${g.plural} found',
        style: text.bodySmall,
      ),
      _ => const SizedBox.shrink(),
    };
    if (message is SizedBox) return null;
    return Padding(
      key: Key('search.${g.name}.message'),
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 8),
      child: message,
    );
  }

  List<Widget> _groupPreview(
    BuildContext context,
    GlobalSearchState results,
    _Group g, {
    required bool focusFirst,
  }) {
    if (_groupMessage(context, results, g) case final message?) {
      return [SliverToBoxAdapter(child: message)];
    }
    final first = focusFirst ? _firstResult : null;
    final watch = ref.watch(watchProvider);
    switch (g) {
      case _Group.live:
        final channels = results.live.items
            .take(SearchScreen.previewChannels)
            .toList();
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            sliver: SliverFixedExtentList.builder(
              itemExtent: ChannelRow.extent(context),
              itemCount: channels.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChannelRow(
                  key: ValueKey('search.live.${channels[i].id}'),
                  channel: channels[i],
                  focusNode: i == 0 ? first : null,
                ),
              ),
            ),
          ),
        ];
      case _Group.movies:
      case _Group.series:
        final posters = <Widget>[
          if (g == _Group.movies)
            for (final (i, m)
                in results.movies.items
                    .take(SearchScreen.previewPosters)
                    .indexed)
              moviePoster(
                context,
                watch,
                m,
                key: ValueKey('search.movie.${m.streamId}'),
                focusNode: i == 0 ? first : null,
              )
          else
            for (final (i, s)
                in results.series.items
                    .take(SearchScreen.previewPosters)
                    .indexed)
              seriesPoster(
                context,
                watch,
                s,
                key: ValueKey('search.series.${s.seriesId}'),
                focusNode: i == 0 ? first : null,
              ),
        ];
        return [
          SliverToBoxAdapter(
            child: SizedBox(
              key: Key('search.${g.name}.row'),
              height: 270,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 34),
                children: [
                  for (final p in posters) SizedBox(width: 150, child: p),
                ],
              ),
            ),
          ),
        ];
    }
  }

  /// All results of [g], listed lazily.
  Widget _buildExpanded(
    BuildContext context,
    GlobalSearchState results,
    _Group g,
  ) {
    final text = Theme.of(context).textTheme;
    final watch = ref.watch(watchProvider);
    final count = _count(results, g);
    final Widget list = switch (g) {
      _Group.live => ListView.builder(
        key: const Key('search.all'),
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 28),
        itemExtent: ChannelRow.extent(context),
        itemCount: count,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ChannelRow(
            key: ValueKey('search.live.${results.live.items[i].id}'),
            channel: results.live.items[i],
            focusNode: i == 0 ? _firstResult : null,
          ),
        ),
      ),
      _Group.movies || _Group.series => GridView.builder(
        key: const Key('search.all'),
        padding: const EdgeInsets.fromLTRB(34, 0, 34, 28),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          childAspectRatio: 0.52,
        ),
        itemCount: count,
        itemBuilder: (context, i) => g == _Group.movies
            ? moviePoster(
                context,
                watch,
                results.movies.items[i],
                key: ValueKey(
                  'search.movie.${results.movies.items[i].streamId}',
                ),
                focusNode: i == 0 ? _firstResult : null,
              )
            : seriesPoster(
                context,
                watch,
                results.series.items[i],
                key: ValueKey(
                  'search.series.${results.series.items[i].seriesId}',
                ),
                focusNode: i == 0 ? _firstResult : null,
              ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 40, 12),
          child: Row(
            children: [
              IconButton(
                key: const Key('search.back'),
                tooltip: 'All results',
                icon: const Icon(Icons.arrow_back),
                onPressed: _collapse,
              ),
              const SizedBox(width: 8),
              Text(g.title, style: text.titleLarge),
              const SizedBox(width: 10),
              Text(
                formatCountOf(count, g.singular, g.plural),
                key: Key('search.${g.name}.count'),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: count == 0
              ? Center(child: Text('No ${g.plural} found'))
              : list,
        ),
      ],
    );
  }
}
