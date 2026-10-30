import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../epg/now_next.dart';
import '../favourites/category_icons.dart';
import '../live/live_tv_screen.dart';
import '../live/replay_mark.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';
import 'player_hint.dart';
import 'player_shortcuts.dart';

/// "Channels": my Live TV categories as tabs, each listing its channels
/// with logo, name and the programme on now. Choosing one calls
/// [onSelect]; the [current] channel is highlighted and gets focus. A
/// side panel, as nothing can be drawn over the embedded video.
class ZapPanel extends ConsumerStatefulWidget {
  const ZapPanel({
    super.key,
    required this.current,
    required this.onSelect,
    this.onClose,
  });

  final LiveStream current;
  final ValueChanged<LiveStream> onSelect;
  final VoidCallback? onClose;

  static const width = 360.0;

  @override
  ConsumerState<ZapPanel> createState() => _ZapPanelState();
}

class _ZapPanelState extends ConsumerState<ZapPanel> {
  /// The chosen tab; null for the first category with the current channel.
  String? _tab;

  FavouriteCategory _selected(List<FavouriteCategory> categories) {
    final chosen = categories.where((c) => c.id == _tab).firstOrNull;
    if (chosen != null) return chosen;
    final containing = ref
        .read(favouritesProvider)
        .categoriesContaining(liveItemRef(widget.current));
    return categories.where((c) => containing.contains(c.id)).firstOrNull ??
        categories.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favourites = ref.watch(favouritesProvider);
    final categories = favourites.categoriesOf(ContentKind.live);
    final header = Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Text('CHANNELS', style: theme.textTheme.labelMedium),
          ),
        ),
        if (widget.onClose != null)
          PlayerTooltip(
            message: 'Close (Esc)',
            side: true,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: widget.onClose,
            ),
          ),
      ],
    );
    final Widget body;
    if (categories.every((c) => favourites.countIn(c.id) == 0)) {
      body = Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No Live TV favourites yet. Add channels to one of My categories '
          'with the star.',
          key: const Key('zap.hint'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    } else {
      final tab = _selected(categories);
      final catalog = ref.watch(liveCatalogProvider).value;
      final channels = catalog == null
          ? const <LiveStream>[]
          : [
              for (final c in myCategoryChannels(catalog, favourites, tab.id))
                if (!c.isSeparator) c,
            ];
      body = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Row(
                children: [
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PlayerTooltip(
                        message: 'Show the channels in ${c.name}',
                        side: true,
                        child: ToolbarChip(
                          key: Key('zap.tab.${c.id}'),
                          label: c.name,
                          icon: categoryIcon(c.icon),
                          selected: c.id == tab.id,
                          maxLabelWidth: 180,
                          onPressed: () => setState(() => _tab = c.id),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: channels.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        catalog == null ? 'Loading channels…' : 'No channels',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  : _ChannelList(
                      key: ValueKey(tab.id),
                      channels: channels,
                      current: widget.current,
                      onSelect: widget.onSelect,
                    ),
            ),
          ],
        ),
      );
    }
    return PlayerPanelScope(
      child: Material(
        key: const Key('player.zap'),
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, body],
        ),
      ),
    );
  }
}

/// The channels of one tab. When it appears, the current channel (or the
/// first one) gets focus, so the arrow keys work at once.
class _ChannelList extends StatefulWidget {
  const _ChannelList({
    super.key,
    required this.channels,
    required this.current,
    required this.onSelect,
  });

  final List<LiveStream> channels;
  final LiveStream current;
  final ValueChanged<LiveStream> onSelect;

  @override
  State<_ChannelList> createState() => _ChannelListState();
}

class _ChannelListState extends State<_ChannelList> {
  ScrollController? _scroll;
  final _focus = FocusNode(debugLabel: 'zap.channel');
  late final int _focused = math.max(
    0,
    widget.channels.indexWhere((c) => c.stableId == widget.current.stableId),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.context != null) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scroll?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = ChannelRow.extent(context);
    // Starts with the focused channel in view.
    _scroll ??= ScrollController(
      initialScrollOffset: math.max(0.0, (_focused - 1) * extent),
    );
    return ListView.builder(
      key: const Key('zap.channels'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemExtent: extent,
      itemCount: widget.channels.length,
      // One image for the whole panel when it is shown over the video.
      addRepaintBoundaries: false,
      itemBuilder: (context, i) {
        final channel = widget.channels[i];
        final current = channel.stableId == widget.current.stableId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PlayerTooltip(
            message: [
              'Watch ${channelDisplayName(channel)}',
              if (channel.hasReplay) replayDescription(channel.archiveDays),
            ].join(' · '),
            side: true,
            child: AppTile(
              key: Key('zap.channel.${channel.id}'),
              selected: current,
              focusNode: i == _focused ? _focus : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onTap: () => widget.onSelect(channel),
              child: Row(
                children: [
                  ChannelLogo(channel.logoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChannelName(
                          channel,
                          style: Theme.of(context).textTheme.titleMedium,
                          // Over the video: the row's hint says it.
                          markTooltip: false,
                        ),
                        NowNextLine(channel: channel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
