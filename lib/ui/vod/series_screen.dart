import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/providers.dart';
import '../home/continue_actions.dart';
import 'poster.dart';
import 'series_details_screen.dart';
import 'vod_browser.dart';

/// Opens the details page of [series].
void openSeries(BuildContext context, Series series) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailsScreen(series: series),
      ),
    );

/// The poster of [series] in a grid: title, year, favourite star and watch
/// state.
Widget seriesPoster(
  BuildContext context,
  WatchData watch,
  Series series, {
  Key? key,
  FocusNode? focusNode,
}) {
  final progress = watch.series[series.seriesId];
  return PosterCard(
    key: key ?? ValueKey(series.seriesId),
    focusNode: focusNode,
    title: series.name,
    favourite: seriesItemRef(series),
    subtitle: series.year?.toString(),
    imageUrl: series.coverUrl,
    placeholder: Icons.tv,
    watched: progress?.finished ?? false,
    // Started: at least a sliver, so the bar shows.
    progress: progress == null ? null : math.max(progress.fraction, 0.03),
    onTap: () => openSeries(context, series),
  );
}

/// The Series tab: categories, search, sort and filters, "Continue
/// watching" (with the next episode to watch) and a poster grid.
class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key});

  static void _open(BuildContext context, Series series) =>
      openSeries(context, series);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(seriesCatalogProvider);
    final filter = ref.watch(seriesFilterProvider);
    final watch = ref.watch(watchProvider);
    final catalog = state.catalog;
    return VodBrowser<Series>(
      title: 'Series',
      what: 'series',
      kind: ContentKind.series,
      state: state,
      filter: filter,
      notifier: ref.read(seriesFilterProvider.notifier),
      categoryOf: (item) => item.categoryId,
      itemRef: seriesItemRef,
      onRefresh: ref.read(seriesCatalogProvider.notifier).refresh,
      continueWatching: [
        if (catalog != null)
          for (final (id, progress) in continueSeries(watch))
            if (catalog.byId(id) case final series?)
              (series, _continueCard(context, ref, watch, series, progress)),
      ],
      itemBuilder: (context, series) => seriesPoster(context, watch, series),
    );
  }

  Widget _continueCard(
    BuildContext context,
    WidgetRef ref,
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
      favourite: seriesItemRef(series),
      subtitle: [?code, ?progress.nextTitle].join(' · '),
      imageUrl: series.coverUrl,
      placeholder: Icons.tv,
      progress: isInProgress(episode) ? episode!.fraction : null,
      actions: [removeFromContinueAction(context, ref, series: series)],
      onTap: () => _open(context, series),
    );
  }
}
