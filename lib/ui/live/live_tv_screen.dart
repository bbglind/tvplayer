import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/errors.dart';
import '../../state/providers.dart';
import '../epg/now_next.dart';
import '../player/open_channel.dart';
import '../vod/poster.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'separator_header.dart';

/// Categories on the left, searchable channel list on the right.
class LiveTvScreen extends ConsumerWidget {
  const LiveTvScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(liveCatalogProvider);
    return catalog.when(
      skipLoadingOnRefresh: false,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(
        message: describeProviderError(error),
        onRetry: () => ref.invalidate(liveCatalogProvider),
      ),
      data: (catalog) => Row(
        children: [
          SizedBox(width: 280, child: _CategoryList(catalog: catalog)),
          const VerticalDivider(width: 1),
          const Expanded(child: _ChannelPane()),
        ],
      ),
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
    final selected = ref.watch(selectedCategoryProvider);
    final notifier = ref.read(selectedCategoryProvider.notifier);
    final categories = catalog.categories;
    return ListView.builder(
      key: const Key('live.categories'),
      padding: const EdgeInsets.fromLTRB(16, 28, 12, 16),
      itemCount: categories.length + 1,
      itemBuilder: (context, i) {
        final category = i == 0 ? null : categories[i - 1];
        final id = category?.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: CategoryPill(
            label: category?.name ?? 'All channels',
            count: id == null ? catalog.channelCount : catalog.countIn(id),
            selected: id == selected,
            onTap: () => notifier.select(id),
          ),
        );
      },
    );
  }
}

class _ChannelPane extends ConsumerStatefulWidget {
  const _ChannelPane();

  @override
  ConsumerState<_ChannelPane> createState() => _ChannelPaneState();
}

class _ChannelPaneState extends ConsumerState<_ChannelPane> {
  late final _search = TextEditingController(
    text: ref.read(channelQueryProvider),
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String q) {
    ref.read(channelQueryProvider.notifier).set(q);
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(visibleChannelsProvider).value ?? const [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  key: const Key('live.search'),
                  controller: _search,
                  onChanged: _setQuery,
                  hintText: 'Search channels',
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Reload channels',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(liveCatalogProvider),
              ),
              if (ref.watch(guideProvider) case final guide
                  when guide.supported)
                IconButton(
                  tooltip: 'Refresh TV guide',
                  icon: const Icon(Icons.event_repeat),
                  onPressed: guide.loading
                      ? null
                      : ref.read(guideProvider.notifier).refresh,
                ),
            ],
          ),
        ),
        Expanded(
          child: channels.isEmpty
              ? const Center(child: Text('No channels'))
              : ListView.builder(
                  key: const Key('live.channels'),
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  itemExtent: 76,
                  itemCount: channels.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: channels[i].isSeparator
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

/// A channel in the list: number, logo tile, name and what's on now.
class ChannelRow extends ConsumerWidget {
  const ChannelRow({super.key, required this.channel});

  final LiveStream channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final logo = channel.logoUrl;
    return AppTile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => openChannel(context, ref, channel),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              channel.number == null ? '' : '${channel.number}',
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
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
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                NowNextLine(channel: channel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
