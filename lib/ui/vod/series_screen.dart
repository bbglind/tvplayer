import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/downloads_controller.dart';
import '../../state/playlist_refresh.dart';
import '../../state/providers.dart';
import '../../state/tmdb.dart';
import '../../state/variants.dart';
import '../home/continue_actions.dart';
import 'poster.dart';
import 'series_details_screen.dart';
import 'vod_browser.dart';

/// Opens the details page of [series], on [season] when given (else the
/// season of the episode up next).
void openSeries(BuildContext context, Series series, {int? season}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeriesDetailsScreen(series: series, season: season),
      ),
    );

/// The poster of [series] in a grid: title, year (or [subtitle]),
/// favourite star and watch state, together with its other sources.
/// [lastPlayed] marks the source played last.
Widget seriesPoster(
  BuildContext context,
  Series series, {
  Key? key,
  FocusNode? focusNode,
  String? subtitle,
  bool lastPlayed = false,
}) => Consumer(
  builder: (context, ref, _) {
    final progress = seriesGroupProgress(
      ref.watch(watchProvider),
      ref.watch(seriesVariantsProvider).groupOf(series.seriesId),
    );
    return PosterCard(
      key: key ?? ValueKey(series.seriesId),
      focusNode: focusNode,
      title: series.name,
      favourite: seriesItemRef(series),
      subtitle: subtitle ?? series.year?.toString(),
      subtitleIcon: lastPlayed ? Icons.history : null,
      subtitleIconTooltip: lastPlayed ? 'Last played' : null,
      imageUrl: seriesPosterUrls(ref, series).primary,
      imageFallbackUrl: seriesPosterUrls(ref, series).fallback,
      placeholder: Icons.tv,
      watched: progress?.finished ?? false,
      // Some of its episodes are downloaded.
      downloaded: ref.watch(
        downloadsProvider.select(
          (s) => s.items.any((i) => i.isDone && i.seriesId == series.seriesId),
        ),
      ),
      // Started: at least a sliver, so the bar shows.
      progress: progress == null ? null : math.max(progress.fraction, 0.03),
      onTap: () => openSeries(context, series),
    );
  },
);

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
      imageOf: (item) => item.coverUrl,
      onRefresh: () => refreshPlaylistPart(ref, PlaylistPart.series),
      continueWatching: [
        if (catalog != null)
          for (final (id, progress) in continueSeriesGroups(
            watch,
            ref.watch(seriesVariantsProvider).groupOf,
          ))
            if (catalog.byId(id) case final series?)
              (series, _continueCard(context, ref, watch, series, progress)),
      ],
      itemBuilder: (context, series) => seriesPoster(context, series),
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
    final episode = _nextProgress(ref, series.seriesId, progress);
    final code =
        progress.nextSeason != null && progress.nextEpisodeNumber != null
        ? formatEpisodeCode(progress.nextSeason!, progress.nextEpisodeNumber!)
        : null;
    final title = switch (progress.nextTitle) {
      final t? => episodeDisplayTitle(
        series,
        Episode(
          id: next ?? '',
          season: progress.nextSeason ?? 0,
          episodeNumber: progress.nextEpisodeNumber ?? 0,
          title: t,
        ),
        ref.watch(providerTagsProvider),
      ),
      null => null,
    };
    return PosterCard(
      key: ValueKey('continue.${series.seriesId}'),
      title: series.name,
      favourite: seriesItemRef(series),
      subtitle: [?code, ?title].join(' · '),
      imageUrl: seriesPosterUrls(ref, series).primary,
      imageFallbackUrl: seriesPosterUrls(ref, series).fallback,
      placeholder: Icons.tv,
      progress: isInProgress(episode) ? episode!.fraction : null,
      actions: [
        goToSeriesAction(context, series, season: progress.nextSeason),
        removeFromContinueAction(context, ref, series: series),
      ],
      onTap: () => _open(context, series),
    );
  }
}

/// The progress of the next episode of [progress] across the other sources
/// of series [seriesId].
WatchProgress? _nextProgress(
  WidgetRef ref,
  int seriesId,
  SeriesProgress progress,
) => nextEpisodeProgress(ref.watch(episodeViewProvider(seriesId)), progress);
