import '../favourites/favourites_data.dart';
import '../home/home_picks.dart';
import '../live/live_source.dart';
import '../models/movie.dart';
import '../models/series.dart';
import '../vod/vod_catalog.dart';
import '../watch/watch_data.dart';
import '../watch/watch_logic.dart';

/// The user's items that the provider's current lists no longer have.
/// Nothing is deleted: favourites show them with their saved name, and
/// watch history comes back if the provider lists the item again.
final class MissingItems {
  const MissingItems({
    this.favourites = const [],
    this.continueWatching = 0,
    this.recentChannels = 0,
  });

  /// Favourite items, once each even when in several of my categories.
  final List<FavouriteMembership> favourites;

  /// Started movies and series in "Continue watching".
  final int continueWatching;

  /// Channels in "Recently viewed channels".
  final int recentChannels;

  static const none = MissingItems();

  bool get isEmpty =>
      favourites.isEmpty && continueWatching == 0 && recentChannels == 0;
}

/// What of [favourites] and [watch] the catalogues don't list. A null
/// catalogue isn't loaded (or the provider has none), so its items are
/// not counted.
MissingItems missingItems({
  required FavouritesData favourites,
  required WatchData watch,
  LiveCatalog? live,
  VodCatalog<Movie>? movies,
  VodCatalog<Series>? series,
}) {
  bool? listed(ItemRef item) => switch (item.kind) {
    ContentKind.live => live == null ? null : live.byStableId(item.id) != null,
    ContentKind.movie =>
      movies == null ? null : movies.byId(int.tryParse(item.id) ?? -1) != null,
    ContentKind.series =>
      series == null ? null : series.byId(int.tryParse(item.id) ?? -1) != null,
  };

  final seen = <ItemRef>{};
  final missingFavourites = [
    for (final kind in ContentKind.values)
      for (final category in favourites.categoriesOf(kind))
        for (final m in favourites.itemsIn(category.id))
          if (listed(m.item) == false && seen.add(m.item)) m,
  ];
  var continueWatching = 0;
  for (final entry in continueAll(watch)) {
    final gone = switch (entry) {
      ContinueMovie(:final streamId) =>
        movies != null && movies.byId(streamId) == null,
      ContinueSeries(:final seriesId) =>
        series != null && series.byId(seriesId) == null,
    };
    if (gone) continueWatching++;
  }
  var recent = 0;
  if (live != null) {
    for (final (id, _) in recentChannels(watch)) {
      if (live.byStableId(id) == null) recent++;
    }
  }
  return MissingItems(
    favourites: missingFavourites,
    continueWatching: continueWatching,
    recentChannels: recent,
  );
}
