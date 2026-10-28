import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/home.dart';
import '../../state/navigation.dart';
import '../../state/providers.dart';
import '../../state/tmdb.dart';
import '../epg/now_next.dart';
import '../favourites/category_icons.dart';
import '../favourites/favourite_menu.dart';
import '../live/live_tv_screen.dart';
import '../live/replay_mark.dart';
import '../player/open_channel.dart';
import '../theme/app_colors.dart';
import '../theme/widgets.dart';
import '../vod/movies_screen.dart';
import '../vod/poster.dart';
import '../vod/series_screen.dart';
import 'continue_actions.dart';
import 'home_playback.dart';
import 'home_row.dart';

/// A recently watched channel: logo, name, when it was watched and what is
/// on now. Enter or a click plays it.
class RecentChannelCard extends ConsumerStatefulWidget {
  const RecentChannelCard({
    super.key,
    required this.channel,
    required this.watchedAt,
  });

  final LiveStream channel;
  final DateTime watchedAt;

  static const width = 300.0;
  static const _padding = EdgeInsets.fromLTRB(12, 12, 44, 12);

  /// Card height at the current text scale: name, "watched" line,
  /// programme line and progress bar.
  static double height(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final content =
        lineHeight(context, text.titleMedium) +
        2 * lineHeight(context, text.bodySmall) +
        NowNextLine.progressGap +
        NowNextLine.progressHeight;
    return (math.max(44.0, content) + _padding.vertical).ceilToDouble();
  }

  @override
  ConsumerState<RecentChannelCard> createState() => _RecentChannelCardState();
}

class _RecentChannelCardState extends ConsumerState<RecentChannelCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final item = liveItemRef(channel);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider);
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
              actions: [
                ItemMenuAction(
                  key: const Key('context.forgetChannel'),
                  label: 'Remove from recently viewed',
                  icon: Icons.history_toggle_off,
                  onPressed: () => ref
                      .read(watchProvider.notifier)
                      .forgetChannel(channel.stableId),
                ),
              ],
              child: AppTile(
                key: Key('home.channel.${channel.stableId}'),
                padding: RecentChannelCard._padding,
                onTap: () => openChannel(context, ref, channel),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ChannelLogo(channel.logoUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ChannelName(channel, style: text.titleMedium),
                          Text(
                            'Watched ${formatAgo(widget.watchedAt, now)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                          NowNextLine(channel: channel),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
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

/// One of my categories: icon, kind, name and item count. A click opens
/// its section with the category selected.
class MyCategoryTile extends ConsumerWidget {
  const MyCategoryTile({super.key, required this.category});

  final FavouriteCategory category;

  static const width = 220.0;
  static const _padding = EdgeInsets.all(14);

  /// Tile height at the current text scale.
  static double height(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return (math.max(20.0, lineHeight(context, text.labelMedium)) +
            8 +
            lineHeight(context, text.titleMedium) +
            lineHeight(context, text.bodySmall) +
            _padding.vertical)
        .ceilToDouble();
  }

  static String kindLabel(ContentKind kind) => switch (kind) {
    ContentKind.live => 'Live TV',
    ContentKind.movie => 'Movies',
    ContentKind.series => 'Series',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final count = ref.watch(
      favouritesProvider.select((f) => f.countIn(category.id)),
    );
    final noun = switch (category.kind) {
      ContentKind.live => ('channel', 'channels'),
      ContentKind.movie => ('movie', 'movies'),
      ContentKind.series => ('series', 'series'),
    };
    return AppTile(
      key: Key('home.category.${category.id}'),
      padding: _padding,
      onTap: () => openMyCategory(ref, category),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                categoryIcon(category.icon),
                size: 20,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kindLabel(category.kind).toUpperCase(),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium,
          ),
          Text(
            formatCountOf(count, noun.$1, noun.$2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Width of a "Continue watching" card; its thumbnail is 16:9.
const continueCardWidth = 300.0;

/// Width of a poster in the "Recently added" rows.
const homePosterWidth = 150.0;

/// Height of a [PosterCard] [width] wide whose image has [aspectRatio]
/// (width / height), at the current text scale: padding, image, two title
/// lines and the second line.
double posterCardHeight(
  BuildContext context,
  double width, {
  required double aspectRatio,
}) {
  final text = Theme.of(context).textTheme;
  const padding = 6.0;
  final image = (width - 2 * padding) / aspectRatio;
  return (2 * padding +
          image +
          8 +
          2 * lineHeight(context, text.titleSmall) +
          lineHeight(context, text.bodySmall))
      .ceilToDouble();
}

/// A started movie or series as a 16:9 card with its progress and what is
/// left. Enter or a click resumes playback; the context menu also opens
/// the details.
Widget continueCard(BuildContext context, WidgetRef ref, ContinueItem item) {
  switch (item) {
    case ContinueMovieItem(:final movie, :final progress):
      final left = switch (progress.duration) {
        final d? when d > progress.position => formatTimeLeft(
          d - progress.position,
        ),
        _ => 'Resume at ${formatDuration(progress.position)}',
      };
      return PosterCard(
        key: ValueKey('home.continue.movie.${movie.streamId}'),
        title: movie.name,
        subtitle: left,
        imageUrl:
            movieBackdropUrl(ref, movie) ?? moviePosterUrls(ref, movie).primary,
        imageFallbackUrl: movieBackdropUrl(ref, movie) == null
            ? moviePosterUrls(ref, movie).fallback
            : moviePosterUrls(ref, movie).primary,
        imageAlignment: movieBackdropUrl(ref, movie) == null
            ? Alignment.topCenter
            : Alignment.center,
        decodeWidth: 600,
        progress: progress.fraction,
        favourite: movieItemRef(movie),
        actions: [
          ItemMenuAction(
            key: const Key('context.details'),
            label: 'Open details',
            icon: Icons.info_outline,
            onPressed: () => openMovie(context, movie),
          ),
          removeFromContinueAction(context, ref, movie: movie),
        ],
        onTap: () => playMovie(context, ref, movie),
      );
    case ContinueSeriesItem(:final series, :final progress, :final episode):
      final started = isInProgress(episode);
      final duration = episode?.duration;
      final left = started && duration != null && duration > episode!.position
          ? formatTimeLeft(duration - episode.position)
          : null;
      final parts = [
        if ((progress.nextSeason, progress.nextEpisodeNumber) case (
          final s?,
          final e?,
        )) ...[
          'S$s',
          'E$e',
        ],
        left ?? 'Up next',
      ];
      return PosterCard(
        key: ValueKey('home.continue.series.${series.seriesId}'),
        title: series.name,
        subtitle: parts.join(' · '),
        imageUrl:
            seriesBackdropUrl(ref, series) ??
            seriesPosterUrls(ref, series).primary,
        imageFallbackUrl: seriesBackdropUrl(ref, series) == null
            ? seriesPosterUrls(ref, series).fallback
            : seriesPosterUrls(ref, series).primary,
        imageAlignment: seriesBackdropUrl(ref, series) == null
            ? Alignment.topCenter
            : Alignment.center,
        decodeWidth: 600,
        placeholder: Icons.tv,
        // The episode's progress, else at least a sliver of the series'.
        progress: started
            ? episode!.fraction
            : math.max(progress.fraction, 0.03),
        favourite: seriesItemRef(series),
        actions: [
          ItemMenuAction(
            key: const Key('context.details'),
            label: 'Open details',
            icon: Icons.info_outline,
            onPressed: () => openSeries(context, series),
          ),
          removeFromContinueAction(context, ref, series: series),
        ],
        onTap: () => playSeries(context, ref, series),
      );
  }
}
