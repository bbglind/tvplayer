import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/providers.dart';
import 'poster.dart';
import 'series_details_screen.dart';
import 'vod_browser.dart';

/// The Series tab: categories, search, "Continue watching" (with the next
/// episode to watch) and a poster grid.
class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key});

  static void _open(BuildContext context, Series series) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SeriesDetailsScreen(series: series),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seriesCatalogProvider);
    final filter = ref.watch(seriesFilterProvider);
    final watch = ref.watch(watchProvider);
    final catalog = state.catalog;
    final filterNotifier = ref.read(seriesFilterProvider.notifier);
    return VodBrowser<Series>(
      what: 'series',
      state: state,
      filter: filter,
      onCategory: filterNotifier.selectCategory,
      onQuery: filterNotifier.setQuery,
      onRefresh: ref.read(seriesCatalogProvider.notifier).refresh,
      continueWatching: [
        if (catalog != null)
          for (final (id, progress) in continueSeries(watch))
            if (catalog.byId(id) case final series?)
              _continueCard(context, watch, series, progress),
      ],
      itemBuilder: (context, series) {
        final progress = watch.series[series.seriesId];
        return PosterCard(
          key: ValueKey(series.seriesId),
          title: series.name,
          subtitle: series.year?.toString(),
          imageUrl: series.coverUrl,
          placeholder: Icons.tv,
          watched: progress?.finished ?? false,
          // Started: at least a sliver, so the bar shows.
          progress: progress == null ? null : math.max(progress.fraction, 0.03),
          onTap: () => _open(context, series),
        );
      },
    );
  }

  Widget _continueCard(
    BuildContext context,
    WatchData watch,
    Series series,
    SeriesProgress progress,
  ) {
    final next = progress.nextEpisodeId;
    final episode = next == null ? null : watch.episode(next);
    final code =
        progress.nextSeason != null && progress.nextEpisodeNumber != null
        ? formatEpisodeCode(progress.nextSeason!, progress.nextEpisodeNumber!)
        : null;
    return PosterCard(
      key: ValueKey('continue.${series.seriesId}'),
      title: series.name,
      subtitle: [?code, ?progress.nextTitle].join(' · '),
      imageUrl: series.coverUrl,
      placeholder: Icons.tv,
      progress: isInProgress(episode) ? episode!.fraction : null,
      onTap: () => _open(context, series),
    );
  }
}
