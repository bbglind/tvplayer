import '../favourites/favourites_data.dart';
import '../favourites/favourites_logic.dart';
import '../models/movie.dart';
import '../models/series.dart';
import '../vod/vod_catalog.dart';
import '../vod/vod_query.dart';
import '../watch/watch_data.dart';
import '../watch/watch_logic.dart';

/// A movie or a series picked for the start page.
sealed class VodPick {
  const VodPick();

  String get name;
}

final class MoviePick extends VodPick {
  const MoviePick(this.movie);

  final Movie movie;

  @override
  String get name => movie.name;

  @override
  bool operator ==(Object other) =>
      other is MoviePick && other.movie.streamId == movie.streamId;

  @override
  int get hashCode => Object.hash(MoviePick, movie.streamId);
}

final class SeriesPick extends VodPick {
  const SeriesPick(this.series);

  final Series series;

  @override
  String get name => series.name;

  @override
  bool operator ==(Object other) =>
      other is SeriesPick && other.series.seriesId == series.seriesId;

  @override
  int get hashCode => Object.hash(SeriesPick, series.seriesId);
}

/// Lowest rating (0–10) for "Featured".
const featuredMinRating = 7.0;

/// How far back "Featured" looks, widened in turn until there are enough
/// items; null means any time.
const featuredWindows = [
  Duration(days: 30),
  Duration(days: 90),
  Duration(days: 365),
  null,
];

/// Items for "Featured" (until there is a metadata service): recently
/// added movies (by `added`) and recently updated series (by
/// `lastModified`) rated at least [featuredMinRating], that are not
/// favourites and not in hidden categories. Looks back through
/// [featuredWindows] until [count] are found; movies and series take turns,
/// newest first.
List<VodPick> featuredPicks({
  required VodCatalog<Movie>? movies,
  required VodCatalog<Series>? series,
  required FavouritesData favourites,
  required DateTime now,
  int count = 5,
}) {
  final hiddenMovies = favourites.hiddenIds(ContentKind.movie);
  final hiddenSeries = favourites.hiddenIds(ContentKind.series);
  final movieCandidates = <(DateTime, VodPick)>[
    for (final m in movies?.items ?? const <Movie>[])
      if (m.added case final added?
          when _rated(m.rating) &&
              !hiddenMovies.contains(m.categoryId) &&
              !favourites.isFavourite(movieItemRef(m)))
        (added, MoviePick(m)),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  final seriesCandidates = <(DateTime, VodPick)>[
    for (final s in series?.items ?? const <Series>[])
      if (s.lastModified case final modified?
          when _rated(s.rating) &&
              !hiddenSeries.contains(s.categoryId) &&
              !favourites.isFavourite(seriesItemRef(s)))
        (modified, SeriesPick(s)),
  ]..sort((a, b) => b.$1.compareTo(a.$1));

  List<VodPick> within(List<(DateTime, VodPick)> sorted, Duration? window) {
    if (window == null) return [for (final (_, p) in sorted) p];
    final since = now.subtract(window);
    return [
      for (final (_, p) in sorted.takeWhile((e) => e.$1.isAfter(since))) p,
    ];
  }

  var pickedMovies = const <VodPick>[];
  var pickedSeries = const <VodPick>[];
  for (final window in featuredWindows) {
    pickedMovies = within(movieCandidates, window);
    pickedSeries = within(seriesCandidates, window);
    if (pickedMovies.length + pickedSeries.length >= count) break;
  }
  final result = <VodPick>[];
  for (var i = 0; result.length < count; i++) {
    if (i >= pickedMovies.length && i >= pickedSeries.length) break;
    if (i < pickedMovies.length) result.add(pickedMovies[i]);
    if (i < pickedSeries.length && result.length < count) {
      result.add(pickedSeries[i]);
    }
  }
  return result;
}

bool _rated(double? rating) => rating != null && rating >= featuredMinRating;

/// The [limit] newest items of [catalog] outside the [hidden] categories
/// ("Recently added").
List<T> recentlyAdded<T extends Object>(
  VodCatalog<T> catalog, {
  Set<String> hidden = const {},
  int limit = 20,
}) => catalog
    .query(
      scope: VodScope.all(hidden: hidden),
      sort: VodSort.recent,
    )
    .take(limit)
    .toList();

/// A started movie or series for "Continue watching".
sealed class ContinueEntry {
  const ContinueEntry();

  DateTime get updatedAt;
}

final class ContinueMovie extends ContinueEntry {
  const ContinueMovie(this.streamId, this.progress);

  final int streamId;
  final WatchProgress progress;

  @override
  DateTime get updatedAt => progress.updatedAt;
}

final class ContinueSeries extends ContinueEntry {
  const ContinueSeries(this.seriesId, this.progress);

  final int seriesId;
  final SeriesProgress progress;

  @override
  DateTime get updatedAt => progress.updatedAt;
}

/// Started movies ([continueMovies]) and series ([continueSeries])
/// together, most recently watched first. With [movieGroups] and
/// [seriesGroups] (an id and those of its variants), one per group (see
/// [continueMovieGroups] and [continueSeriesGroups]).
List<ContinueEntry> continueAll(
  WatchData data, {
  List<int> Function(int)? movieGroups,
  List<int> Function(int)? seriesGroups,
}) => [
  for (final (id, p) in switch (movieGroups) {
    final g? => continueMovieGroups(data, g),
    null => continueMovies(data),
  })
    ContinueMovie(id, p),
  for (final (id, p) in switch (seriesGroups) {
    final g? => continueSeriesGroups(data, g),
    null => continueSeries(data),
  })
    ContinueSeries(id, p),
]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
