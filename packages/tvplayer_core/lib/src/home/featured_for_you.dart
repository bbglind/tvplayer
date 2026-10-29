import 'dart:math' as math;

import '../favourites/favourites_data.dart';
import '../favourites/favourites_logic.dart';
import '../models/movie.dart';
import '../models/series.dart';
import '../tmdb/tmdb_genres.dart';
import '../tmdb/tmdb_links.dart';
import '../tmdb/tmdb_models.dart';
import '../vod/variants.dart';
import '../vod/vod_catalog.dart';
import '../watch/watch_data.dart';
import '../watch/watch_logic.dart';
import 'home_picks.dart';

/// Why an item is in "Featured".
enum FeaturedSource {
  /// Recently added and well rated ([featuredPicks]).
  fresh,

  /// On TMDB's trending list ([trendingPicks]).
  trending,
}

/// An item of "Featured" and why it is there.
final class FeaturedPick {
  const FeaturedPick(this.pick, this.source);

  final VodPick pick;
  final FeaturedSource source;

  @override
  bool operator ==(Object other) =>
      other is FeaturedPick && other.pick == pick && other.source == source;

  @override
  int get hashCode => Object.hash(pick, source);
}

/// The trending list is fetched again once it is this old.
const trendingRefreshAfter = Duration(hours: 24);

/// The stored trending list is used for at most this long after it was
/// fetched (so also offline); older, "Featured" shows only new items.
const trendingMaxAge = Duration(days: 7);

/// What to do about the trending list now.
enum TrendingDecision {
  /// TMDB is off.
  off,

  /// The user paused TMDB's background fetch.
  paused,

  /// Something is playing.
  playing,

  /// Fetched less than [trendingRefreshAfter] ago.
  fresh,

  /// Fetch it.
  refresh,
}

/// Whether to fetch the trending list now, given when it was [fetchedAt]
/// (null: never). Off, paused and playing win in that order.
TrendingDecision trendingDecision({
  required bool enabled,
  required bool paused,
  required bool playing,
  required DateTime? fetchedAt,
  required DateTime now,
}) {
  if (!enabled) return TrendingDecision.off;
  if (paused) return TrendingDecision.paused;
  if (playing) return TrendingDecision.playing;
  if (fetchedAt != null && now.difference(fetchedAt) < trendingRefreshAfter) {
    return TrendingDecision.fresh;
  }
  return TrendingDecision.refresh;
}

/// The titles of [list] while it is at most [trendingMaxAge] old at
/// [now]; none otherwise.
List<TmdbTrending> usableTrending(TmdbTrendingList list, DateTime now) {
  final at = list.fetchedAt;
  if (at == null || now.difference(at) > trendingMaxAge) return const [];
  return list.titles;
}

/// How far back [genreAffinity] looks.
const affinityWindow = Duration(days: 90);

/// Watching older than this counts half in [genreAffinity].
const affinityRecent = Duration(days: 30);

/// Watched this long (or to the end), a movie or episode counts.
const affinityMinWatch = Duration(minutes: 5);

/// The share (0–1) of what was watched in the last [affinityWindow] that
/// has each [genreFamily]: a movie counts 1, a series 1 plus 0.25 per
/// further episode (at most 3), half when last watched more than
/// [affinityRecent] ago. A movie or episode counts when watched for
/// [affinityMinWatch] or to the end. Empty without such watching.
Map<String, double> genreAffinity(
  WatchData watch, {
  required List<String> Function(int streamId) movieGenres,
  required List<String> Function(int seriesId) seriesGenres,
  required DateTime now,
}) {
  final since = now.subtract(affinityWindow);
  final recent = now.subtract(affinityRecent);
  bool counts(WatchProgress p) =>
      p.updatedAt.isAfter(since) &&
      (p.watched || p.position >= affinityMinWatch);
  double age(DateTime last) => last.isAfter(recent) ? 1 : 0.5;

  final weights = <String, double>{};
  var total = 0.0;
  void add(Iterable<String> genres, double weight) {
    total += weight;
    for (final family in {for (final g in genres) genreFamily(g)}) {
      weights[family] = (weights[family] ?? 0) + weight;
    }
  }

  final episodes = <int, ({int count, DateTime last})>{};
  for (final MapEntry(:key, :value) in watch.items.entries) {
    if (!counts(value)) continue;
    if (key.startsWith('movie:')) {
      final id = int.tryParse(key.substring('movie:'.length));
      if (id != null) add(movieGenres(id), age(value.updatedAt));
    } else if (value.seriesId case final id?) {
      final seen = episodes[id];
      episodes[id] = (
        count: (seen?.count ?? 0) + 1,
        last: seen == null || value.updatedAt.isAfter(seen.last)
            ? value.updatedAt
            : seen.last,
      );
    }
  }
  for (final MapEntry(key: id, value: e) in episodes.entries) {
    add(
      seriesGenres(id),
      math.min(3.0, 1 + 0.25 * (e.count - 1)) * age(e.last),
    );
  }
  if (total == 0) return const {};
  return {
    for (final MapEntry(:key, :value) in weights.entries) key: value / total,
  };
}

/// The catalogue titles of [trending] for "Featured", best first: those
/// whose genres were watched most ([affinity], from [genreAffinity]) lead,
/// TMDB's rank breaks ties (score = 2 × genre match + rank bonus). One per
/// variant group; none in hidden categories, favourites, watched movies,
/// finished series or anything in "Continue watching".
List<VodPick> trendingPicks({
  required List<TmdbTrending> trending,
  required VodCatalog<Movie>? movies,
  required VodCatalog<Series>? series,
  required TmdbLinks links,
  required VariantGroups movieGroups,
  required VariantGroups seriesGroups,
  required FavouritesData favourites,
  required WatchData watch,
  Map<String, double> affinity = const {},
}) {
  final perKind = <TmdbKind, int>{};
  for (final t in trending) {
    perKind[t.key.kind] = math.max(perKind[t.key.kind] ?? 0, t.rank);
  }
  double score(TmdbTrending t) {
    final match = {
      for (final g in t.genres) genreFamily(g),
    }.fold(0.0, (sum, f) => sum + (affinity[f] ?? 0));
    final total = perKind[t.key.kind] ?? 1;
    return 2 * math.min(1.0, match) + (1 - (t.rank - 1) / total);
  }

  final scored = [for (final t in trending) (t, score(t))]
    ..sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      final r = a.$1.rank.compareTo(b.$1.rank);
      return r != 0 ? r : a.$1.key.kind.index.compareTo(b.$1.key.kind.index);
    });
  final continuing = {
    for (final (id, _) in continueSeriesGroups(watch, seriesGroups.groupOf))
      ...seriesGroups.groupOf(id),
  };
  bool movieLeftOut(Movie m) {
    final group = movieGroups.groupOf(m.streamId);
    if (movies != null &&
        group.any(
          (id) => switch (movies.byId(id)) {
            final v? => favourites.isFavourite(movieItemRef(v)),
            null => false,
          },
        )) {
      return true;
    }
    final progress = movieGroupProgress(watch, group)?.progress;
    return progress != null && (progress.watched || isInProgress(progress));
  }

  bool seriesLeftOut(Series s) {
    final group = seriesGroups.groupOf(s.seriesId);
    if (series != null &&
        group.any(
          (id) => switch (series.byId(id)) {
            final v? => favourites.isFavourite(seriesItemRef(v)),
            null => false,
          },
        )) {
      return true;
    }
    if (group.any(continuing.contains)) return true;
    return seriesGroupProgress(watch, group)?.finished ?? false;
  }

  return [
    for (final title in catalogTitlesOf(
      [for (final (t, _) in scored) t.key],
      movies: movies,
      series: series,
      links: links,
      movieGroups: movieGroups,
      seriesGroups: seriesGroups,
      hiddenMovies: favourites.hiddenIds(ContentKind.movie),
      hiddenSeries: favourites.hiddenIds(ContentKind.series),
    ))
      ?switch (title) {
        final Movie m when !movieLeftOut(m) => MoviePick(m),
        final Series s when !seriesLeftOut(s) => SeriesPick(s),
        _ => null,
      },
  ];
}

/// Items of each kind in a mixed "Featured".
const featuredPerSource = 4;

/// "Featured" from [fresh] (e.g. `featuredPicks(count: 8)`) and [trending]
/// ([trendingPicks]): new and trending take turns, new first, up to
/// [featuredPerSource] each; when one runs short the other fills up to
/// twice that. An item in both shows once, as trending. Without trending,
/// the first five new items (as before there was trending).
List<FeaturedPick> mixFeatured(List<VodPick> fresh, List<VodPick> trending) {
  if (trending.isEmpty) {
    return [
      for (final p in fresh.take(5)) FeaturedPick(p, FeaturedSource.fresh),
    ];
  }
  final trendingSet = trending.toSet();
  final news = [
    for (final p in fresh)
      if (!trendingSet.contains(p)) p,
  ];
  const total = 2 * featuredPerSource;
  final newCount = math.min(
    news.length,
    math.max(featuredPerSource, total - trending.length),
  );
  final trendCount = math.min(trending.length, total - newCount);
  final result = <FeaturedPick>[];
  for (var i = 0; i < math.max(newCount, trendCount); i++) {
    if (i < newCount) result.add(FeaturedPick(news[i], FeaturedSource.fresh));
    if (i < trendCount) {
      result.add(FeaturedPick(trending[i], FeaturedSource.trending));
    }
  }
  return result;
}
