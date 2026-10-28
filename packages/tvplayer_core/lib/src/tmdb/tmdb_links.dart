import '../models/movie.dart';
import '../models/series.dart';
import '../text/provider_titles.dart';
import '../vod/variants.dart';
import 'title_match.dart';
import 'tmdb_models.dart';
import 'tmdb_store.dart';

/// [VariantItem]s of a movie catalogue, newest first.
List<VariantItem> tmdbMovieItems(Iterable<Movie> movies) => _newestFirst([
  for (final m in movies)
    (
      item: (id: m.streamId, name: m.name, tmdbId: m.tmdbId, year: m.year),
      added: m.added,
    ),
]);

/// [VariantItem]s of a series catalogue, most recently changed first.
List<VariantItem> tmdbSeriesItems(Iterable<Series> series) => _newestFirst([
  for (final s in series)
    (
      item: (id: s.seriesId, name: s.name, tmdbId: s.tmdbId, year: s.year),
      added: s.lastModified,
    ),
]);

List<VariantItem> _newestFirst(
  List<({VariantItem item, DateTime? added})> items,
) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  items.sort((a, b) => (b.added ?? epoch).compareTo(a.added ?? epoch));
  return [for (final i in items) i.item];
}

/// What the background fetch looks up for the catalogues: the provider's
/// TMDB ids, and searches for the titles without one. Newest titles first,
/// movies before series.
final class TmdbWork {
  const TmdbWork(this.wanted, this.searches);

  factory TmdbWork.of({
    required List<VariantItem> movies,
    required List<VariantItem> series,
    required ProviderTags tags,
  }) {
    final wanted = <TmdbKey>{};
    final searches = <TitleSearch>{};
    for (final (kind, items) in [
      (TmdbKind.movie, movies),
      (TmdbKind.tv, series),
    ]) {
      for (final item in items) {
        if (TmdbKey.fromProvider(kind, item.tmdbId) case final key?) {
          wanted.add(key);
        } else if (TitleSearch.of(kind, item.name, tags, year: item.year)
            case final search?) {
          searches.add(search);
        }
      }
    }
    return TmdbWork(wanted.toList(), searches.toList());
  }

  static const empty = TmdbWork([], []);

  final List<TmdbKey> wanted;
  final List<TitleSearch> searches;
}

/// How a provider title is linked to a TMDB title.
final class TmdbLink {
  const TmdbLink(this.key, {this.titleKey});

  final TmdbKey key;

  /// The title search the link comes from (see [titleKey]); null when the
  /// provider sent the TMDB id itself.
  final String? titleKey;

  bool get byTitle => titleKey != null;

  @override
  bool operator ==(Object other) =>
      other is TmdbLink && other.key == key && other.titleKey == titleKey;

  @override
  int get hashCode => Object.hash(key, titleKey);
}

/// The TMDB title of each catalogue item, and the items of each TMDB title:
/// from the provider's TMDB id unless the user removed that link, else
/// from a title search that matched (and wasn't removed).
final class TmdbLinks {
  TmdbLinks._(this._movies, this._series)
    : _moviesOf = _reverse(_movies),
      _seriesOf = _reverse(_series);

  factory TmdbLinks.build({
    required List<VariantItem> movies,
    required List<VariantItem> series,
    required ProviderTags tags,
    required Map<(TmdbKind, String), TitleMatch> matches,
    required Set<TmdbKey> removed,
  }) {
    Map<int, TmdbLink> link(TmdbKind kind, List<VariantItem> items) =>
        Map.fromEntries([
          for (final item in items)
            ?_linkOf(kind, item, tags, matches, removed),
        ]);
    return TmdbLinks._(link(TmdbKind.movie, movies), link(TmdbKind.tv, series));
  }

  static final empty = TmdbLinks._(const {}, const {});

  static MapEntry<int, TmdbLink>? _linkOf(
    TmdbKind kind,
    VariantItem item,
    ProviderTags tags,
    Map<(TmdbKind, String), TitleMatch> matches,
    Set<TmdbKey> removed,
  ) {
    if (TmdbKey.fromProvider(kind, item.tmdbId) case final key?) {
      return removed.contains(key) ? null : MapEntry(item.id, TmdbLink(key));
    }
    final search = TitleSearch.of(kind, item.name, tags, year: item.year);
    if (search == null) return null;
    return switch (matches[(kind, search.key)]) {
      TitleMatch(outcome: MatchOutcome.matched, :final tmdbId?) => MapEntry(
        item.id,
        TmdbLink(TmdbKey(kind, tmdbId), titleKey: search.key),
      ),
      _ => null,
    };
  }

  static Map<TmdbKey, List<int>> _reverse(Map<int, TmdbLink> links) {
    final reverse = <TmdbKey, List<int>>{};
    for (final MapEntry(key: id, value: link) in links.entries) {
      (reverse[link.key] ??= []).add(id);
    }
    return reverse;
  }

  final Map<int, TmdbLink> _movies;
  final Map<int, TmdbLink> _series;
  final Map<TmdbKey, List<int>> _moviesOf;
  final Map<TmdbKey, List<int>> _seriesOf;

  TmdbLink? movie(int streamId) => _movies[streamId];

  TmdbLink? series(int seriesId) => _series[seriesId];

  /// The catalogue items (movie stream ids or series ids) linked to [key],
  /// in catalogue order.
  List<int> itemsOf(TmdbKey key) => switch (key.kind) {
    TmdbKind.movie => _moviesOf[key] ?? const [],
    TmdbKind.tv => _seriesOf[key] ?? const [],
  };
}
