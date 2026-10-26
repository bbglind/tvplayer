import '../models/movie.dart';
import '../models/series.dart';
import '../text/provider_titles.dart';
import '../text/search_text.dart';

/// One movie or series as [VariantGroups] needs it.
typedef VariantItem = ({int id, String name, String? tmdbId, int? year});

/// The variants of the same movie or series in one catalogue (4K, SD, a
/// streaming service's copy…), which providers list as separate items.
///
/// Items match when they have the same TMDB id, unless both have a year
/// and those are more than a year apart (a remake under the same id).
/// Items without a TMDB id (or `0`) match on their title without the
/// provider's tag (see [ProviderTags]) and their year, which both must
/// have: weekly shows without a year are separate items, not variants. An
/// item without an id joins a TMDB group only when exactly one has its
/// title and year, so it never joins two different works into one.
final class VariantGroups {
  VariantGroups._(this._groupOf, this._groups);

  factory VariantGroups.build(Iterable<VariantItem> items, ProviderTags tags) {
    final byTmdb = <String, List<List<VariantItem>>>{};
    final untagged = <VariantItem>[];
    for (final item in items) {
      final tmdb = _validTmdb(item.tmdbId);
      if (tmdb == null) {
        untagged.add(item);
        continue;
      }
      final clusters = byTmdb[tmdb] ??= [];
      final fit = clusters.where((c) => _fits(c, item.year)).firstOrNull;
      if (fit != null) {
        fit.add(item);
      } else {
        clusters.add([item]);
      }
    }
    final groups = <List<int>>[];
    // Title and year of the TMDB clusters, to place items without an id.
    final clusterOf = <String, int>{};
    final ambiguous = <String>{};
    String? titleKey(VariantItem item) {
      final year = item.year;
      if (year == null) return null;
      final title = normalizeForSearch(tags.display(item.name).title);
      return title.isEmpty ? null : '$title\u0000$year';
    }

    for (final clusters in byTmdb.values) {
      for (final cluster in clusters) {
        final index = groups.length;
        groups.add([for (final item in cluster) item.id]);
        for (final key in {for (final i in cluster) ?titleKey(i)}) {
          if (clusterOf.containsKey(key)) ambiguous.add(key);
          clusterOf[key] = index;
        }
      }
    }
    final byTitle = <String, List<int>>{};
    for (final item in untagged) {
      final key = titleKey(item);
      if (key == null) continue;
      final cluster = clusterOf[key];
      if (cluster != null && !ambiguous.contains(key)) {
        groups[cluster].add(item.id);
      } else {
        (byTitle[key] ??= []).add(item.id);
      }
    }
    groups.addAll(byTitle.values);
    final multi = [
      for (final g in groups)
        if (g.length > 1) g,
    ];
    return VariantGroups._({
      for (final (i, g) in multi.indexed)
        for (final id in g) id: i,
    }, multi);
  }

  /// The variant groups of a movie catalogue.
  factory VariantGroups.movies(Iterable<Movie> movies, ProviderTags tags) =>
      VariantGroups.build([
        for (final m in movies)
          (id: m.streamId, name: m.name, tmdbId: m.tmdbId, year: m.year),
      ], tags);

  /// The variant groups of a series catalogue.
  factory VariantGroups.series(Iterable<Series> series, ProviderTags tags) =>
      VariantGroups.build([
        for (final s in series)
          (id: s.seriesId, name: s.name, tmdbId: s.tmdbId, year: s.year),
      ], tags);

  /// No variants at all.
  static final empty = VariantGroups._(const {}, const []);

  final Map<int, int> _groupOf;
  final List<List<int>> _groups;

  /// The other variants of [id], in catalogue order; empty when it has
  /// none.
  List<int> variantsOf(int id) => switch (_groupOf[id]) {
    final g? => [
      for (final other in _groups[g])
        if (other != id) other,
    ],
    null => const [],
  };

  /// [id] and its variants.
  List<int> groupOf(int id) => switch (_groupOf[id]) {
    final g? => _groups[g],
    null => [id],
  };

  /// The same number for the variants of one item; ids without variants
  /// are their own key.
  Object keyOf(int id) => switch (_groupOf[id]) {
    final g? => ('group', g),
    null => id,
  };

  static String? _validTmdb(String? id) {
    final n = id == null ? null : int.tryParse(id.trim());
    return n == null || n == 0 ? null : '$n';
  }

  /// Whether [year] is within a year of every known year in [cluster].
  static bool _fits(List<VariantItem> cluster, int? year) =>
      year == null ||
      cluster.every((i) => i.year == null || (i.year! - year).abs() <= 1);
}
