import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/errors.dart';
import '../../state/providers.dart';
import '../epg/now_next.dart';
import '../player/open_channel.dart';
import '../vod/poster.dart';
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
      itemCount: categories.length + 1,
      itemBuilder: (context, i) {
        final category = i == 0 ? null : categories[i - 1];
        final id = category?.id;
        return ListTile(
          dense: true,
          selected: id == selected,
          title: Text(
            category?.name ?? 'All channels',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            '${id == null ? catalog.channelCount : catalog.countIn(id)}',
          ),
          onTap: () => notifier.select(id),
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
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('live.search'),
                  controller: _search,
                  onChanged: _setQuery,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search channels',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              _setQuery('');
                            },
                          ),
                  ),
                ),
              ),
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
                  itemExtent: 72,
                  itemCount: channels.length,
                  itemBuilder: (context, i) => channels[i].isSeparator
                      ? SeparatorHeader(channel: channels[i])
                      : _ChannelTile(channel: channels[i]),
                ),
        ),
      ],
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.channel});

  final LiveStream channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = channel.logoUrl;
    return ListTile(
      leading: SizedBox.square(
        dimension: 40,
        child: logo == null || logo.isEmpty
            ? const Icon(Icons.live_tv)
            : Poster(
                url: logo,
                decodeWidth: 80,
                fit: BoxFit.contain,
                placeholder: Icons.live_tv,
              ),
      ),
      title: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: NowNextLine(channel: channel),
      trailing: channel.number == null ? null : Text('${channel.number}'),
      onTap: () => openChannel(context, ref, channel),
    );
  }
}
