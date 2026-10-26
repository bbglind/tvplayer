import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'providers.dart';

/// The variant groups (other sources) of the movie catalogue, built in the
/// background; [VariantGroups.empty] until then.
final movieVariantsProvider = Provider<VariantGroups>(
  (ref) => ref.watch(_movieVariants).value ?? VariantGroups.empty,
);

/// The variant groups of the series catalogue, as [movieVariantsProvider].
final seriesVariantsProvider = Provider<VariantGroups>(
  (ref) => ref.watch(_seriesVariants).value ?? VariantGroups.empty,
);

final _movieVariants = FutureProvider<VariantGroups>((ref) async {
  final catalog = ref.watch(movieCatalogProvider.select((s) => s.catalog));
  final tags = ref.watch(providerTagsProvider);
  if (catalog == null) return VariantGroups.empty;
  final items = catalog.items;
  return ref.read(backgroundRunnerProvider)(
    () => VariantGroups.movies(items, tags),
  );
});

final _seriesVariants = FutureProvider<VariantGroups>((ref) async {
  final catalog = ref.watch(seriesCatalogProvider.select((s) => s.catalog));
  final tags = ref.watch(providerTagsProvider);
  if (catalog == null) return VariantGroups.empty;
  final items = catalog.items;
  return ref.read(backgroundRunnerProvider)(
    () => VariantGroups.series(items, tags),
  );
});

/// How the episodes of series [seriesId] stand across its other sources.
final episodeViewProvider = Provider.family<EpisodeGroupView, int>(
  (ref, seriesId) => EpisodeGroupView(
    ref.watch(watchProvider),
    seriesId,
    ref.watch(seriesVariantsProvider).variantsOf(seriesId),
  ),
);

/// How movie [streamId] stands together with its other sources, and which
/// of them the position is from (see [movieGroupProgress]).
final movieProgressProvider =
    Provider.family<({WatchProgress progress, int from})?, int>(
      (ref, streamId) => movieGroupProgress(
        ref.watch(watchProvider),
        ref.watch(movieVariantsProvider).groupOf(streamId),
      ),
    );

/// The progress of the next episode of [progress] in [view], which may
/// come from another source of the series.
WatchProgress? nextEpisodeProgress(
  EpisodeGroupView view,
  SeriesProgress progress,
) => switch (progress.nextEpisodeId) {
  final id? => view.progress(
    Episode(
      id: id,
      season: progress.nextSeason ?? 0,
      episodeNumber: progress.nextEpisodeNumber ?? 0,
      title: '',
    ),
  ),
  null => null,
};
