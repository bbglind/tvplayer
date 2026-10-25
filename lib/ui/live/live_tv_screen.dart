import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/errors.dart';
import '../../format.dart';
import '../../state/category_selection.dart';
import '../../state/providers.dart';
import '../epg/now_next.dart';
import '../favourites/favourite_menu.dart';
import '../player/open_channel.dart';
import '../shell/category_layout.dart';
import '../shell/category_list.dart';
import '../vod/poster.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'separator_header.dart';

/// The page title and channel search on top; categories on the left and
/// the channel list on the right. The search covers all channels (except
/// hidden categories) unless "Only in …" limits it to the selected
/// category.
class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({super.key});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  late final _search = TextEditingController(
    text: ref.read(channelQueryProvider),
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(liveCatalogProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Live TV',
          search: SearchField(
            key: const Key('live.search'),
            controller: _search,
            onChanged: ref.read(channelQueryProvider.notifier).set,
            debounce: ref.watch(searchDebounceProvider),
            hintText: 'Search channels',
          ),
          actions: [
            IconButton(
              tooltip: 'Reload channels',
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(liveCatalogProvider),
            ),
            if (ref.watch(guideProvider) case final guide when guide.supported)
              IconButton(
                tooltip: 'Refresh TV guide',
                icon: const Icon(Icons.event_repeat),
                onPressed: guide.loading
                    ? null
                    : ref.read(guideProvider.notifier).refresh,
              ),
          ],
        ),
        Expanded(
          child: catalog.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ErrorView(
              message: describeProviderError(error),
              onRetry: () => ref.invalidate(liveCatalogProvider),
            ),
            data: (catalog) => CategoryLayout(
              section: 'live',
              headerAction: const CategoryEditButton(section: 'live'),
              list: _CategoryList(catalog: catalog),
              content: _ChannelPane(catalog: catalog),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
          Text(
            'Could not load channels',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.catalog});

  final LiveCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CategoryList(
      section: 'live',
      kind: ContentKind.live,
      allLabel: 'All channels',
      categories: catalog.categories,
      allCount: catalog.countExcluding,
      countIn: catalog.countIn,
      selected: ref.watch(liveSelectionProvider),
      onSelect: ref.read(selectedCategoryProvider.notifier).select,
    );
  }
}

class _ChannelPane extends ConsumerWidget {
  const _ChannelPane({required this.catalog});

  final LiveCatalog catalog;

  /// Items of the selected one of my categories that the provider no
  /// longer lists, matching the search. Left out while searching all
  /// channels.
  List<FavouriteMembership> _missing(WidgetRef ref, bool searchAll) {
    final selection = ref.watch(liveSelectionProvider);
    if (selection is! MyCategory || searchAll) return const [];
    final query = SearchQuery(ref.watch(channelQueryProvider));
    return [
      for (final m in ref.watch(favouritesProvider).itemsIn(selection.id))
        if (catalog.byStableId(m.item.id) == null &&
            query.matches(SearchKey(m.name)))
          m,
    ];
  }

  /// The name of the selected category.
  String _selectionName(WidgetRef ref) =>
      switch (ref.watch(liveSelectionProvider)) {
        AllCategories() => 'All channels',
        ProviderCategory(:final id) =>
          catalog.categories.where((c) => c.id == id).firstOrNull?.name ?? '',
        MyCategory(:final id) =>
          ref.watch(favouritesProvider).category(id)?.name ?? '',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(visibleChannelsProvider).value ?? const [];
    final selection = ref.watch(liveSelectionProvider);
    final searching = !SearchQuery(ref.watch(channelQueryProvider)).isEmpty;
    final inCategory = ref.watch(channelSearchInCategoryProvider);
    final searchAll = searching && !inCategory && selection is! AllCategories;
    final missing = _missing(ref, searchAll);
    final mine = selection is MyCategory;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
          child: Row(
            children: [
              const ShowCategoriesButton(section: 'live'),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (searching && selection is! AllCategories)
                      ToolbarChip(
                        key: const Key('live.onlyIn'),
                        icon: inCategory
                            ? Icons.check
                            : Icons.filter_alt_outlined,
                        selected: inCategory,
                        tooltip: inCategory
                            ? 'Search all channels'
                            : 'Search only in this category',
                        label: 'Only in ${_selectionName(ref)}',
                        onPressed: () => ref
                            .read(channelSearchInCategoryProvider.notifier)
                            .set(!inCategory),
                      ),
                    if (searching)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          formatCountOf(
                            channels.length + missing.length,
                            'channel',
                            'channels',
                          ),
                          key: const Key('live.count'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: channels.isEmpty && missing.isEmpty
              ? Center(
                  child: Text(
                    mine && !searching
                        ? 'No channels yet. Add some with the star on a '
                              'channel.'
                        : searching
                        ? 'No channels found'
                        : 'No channels',
                  ),
                )
              : ListView.builder(
                  key: const Key('live.channels'),
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  itemExtent: ChannelRow.extent(context),
                  itemCount: channels.length + missing.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: i >= channels.length
                        ? _MissingChannelRow(
                            membership: missing[i - channels.length],
                          )
                        : channels[i].isSeparator
                        ? SeparatorHeader(
                            channel: channels[i],
                            radius: AppRadius.card,
                          )
                        : ChannelRow(channel: channels[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A channel in the list: number, logo tile, name and what's on now, and
/// a favourite star (shown on hover or focus, or when it is a favourite).
/// Right click, long press or the Menu key open its context menu.
class ChannelRow extends StatefulWidget {
  const ChannelRow({super.key, required this.channel, this.focusNode});

  final LiveStream channel;
  final FocusNode? focusNode;

  static const _padding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

  /// Room for the star at the right end.
  static const _starSpace = 44.0;

  /// Height of a row plus the gap below it. Grows with the text scale, so
  /// the name, now/next line and progress bar always fit: a fixed height
  /// pushed the bar under the row's bottom edge at large text sizes.
  static double extent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style) =>
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.3);
    final content =
        line(text.titleMedium) +
        line(text.bodySmall) +
        NowNextLine.progressGap +
        NowNextLine.progressHeight;
    // At least the 44 px logo tile, plus padding and the 8 px gap.
    return math.max(44.0, content).ceilToDouble() + _padding.vertical + 8;
  }

  @override
  State<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<ChannelRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final item = liveItemRef(channel);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // The star sits beside the context menu, not in it: menu anchors
      // nest.
      child: Stack(
        children: [
          Positioned.fill(
            child: ItemContextMenu(
              item: item,
              name: channel.name,
              child: Consumer(
                builder: (context, ref, _) => AppTile(
                  padding: ChannelRow._padding.copyWith(
                    right: ChannelRow._padding.right + ChannelRow._starSpace,
                  ),
                  focusNode: widget.focusNode,
                  onTap: () => openChannel(context, ref, channel),
                  child: _ChannelContent(
                    number: channel.number,
                    logoUrl: channel.logoUrl,
                    title: channel.name,
                    below: NowNextLine(channel: channel),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: FavouriteButton(
                item: item,
                name: channel.name,
                revealed: _hovered,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Number, logo tile, [title] and the line [below] it.
class _ChannelContent extends StatelessWidget {
  const _ChannelContent({
    required this.number,
    required this.logoUrl,
    required this.title,
    required this.below,
    this.dimmed = false,
  });

  final int? number;
  final String? logoUrl;
  final String title;
  final Widget below;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final logo = logoUrl;
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(
            number == null ? '' : '$number',
            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        ChannelLogo(logo),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dimmed
                    ? text.titleMedium?.copyWith(color: AppColors.textSecondary)
                    : text.titleMedium,
              ),
              below,
            ],
          ),
        ),
      ],
    );
  }
}

/// The 44×44 logo tile of a channel, with a TV icon when it has no logo.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo(this.url, {super.key});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final logo = url;
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.small)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(4),
      child: logo == null || logo.isEmpty
          ? const Icon(
              Icons.live_tv_outlined,
              size: 20,
              color: AppColors.textMuted,
            )
          : Poster(
              url: logo,
              decodeWidth: 88,
              fit: BoxFit.contain,
              placeholder: Icons.live_tv_outlined,
              background: AppColors.background,
            ),
    );
  }
}

/// A channel in one of my categories that the provider no longer lists:
/// its remembered name, and the star to remove it.
class _MissingChannelRow extends StatelessWidget {
  const _MissingChannelRow({required this.membership});

  final FavouriteMembership membership;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Stack(
      children: [
        Positioned.fill(
          child: AppTile(
            padding: ChannelRow._padding.copyWith(
              right: ChannelRow._padding.right + ChannelRow._starSpace,
            ),
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('The provider no longer lists this channel.'),
              ),
            ),
            child: _ChannelContent(
              number: null,
              logoUrl: null,
              title: membership.name,
              dimmed: true,
              below: Text('Not available', style: text.bodySmall),
            ),
          ),
        ),
        Positioned(
          right: 6,
          top: 0,
          bottom: 0,
          child: Center(
            child: FavouriteButton(
              item: membership.item,
              name: membership.name,
            ),
          ),
        ),
      ],
    );
  }
}
