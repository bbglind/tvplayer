import '../models/category.dart';
import '../models/movie.dart';
import '../models/series.dart';
import '../text/search_text.dart';
import '../util/json.dart';
import 'vod_query.dart';

/// Which items of a [VodCatalog] a query looks at.
sealed class VodScope {
  const VodScope();

  /// All items except those in the [hidden] categories.
  const factory VodScope.all({Set<String> hidden}) = AllItems;

  /// The items in one provider category.
  const factory VodScope.category(String id) = CategoryItems;

  /// The items with these ids (movie stream ids or series ids), in this
  /// order; ids not in the catalogue are skipped.
  const factory VodScope.ids(List<Object> ids) = PickedItems;
}

final class AllItems extends VodScope {
  const AllItems({this.hidden = const {}});

  final Set<String> hidden;
}

final class CategoryItems extends VodScope {
  const CategoryItems(this.id);

  final String id;
}

final class PickedItems extends VodScope {
  const PickedItems(this.ids);

  final List<Object> ids;
}

/// Categories and items (movies or series) of one provider, with a
/// per-category index, a [SearchIndex] and per-item sort and filter
/// values. Built once per download, so queries stay fast for catalogues
/// with tens of thousands of items.
final class VodCatalog<T extends Object> {
  VodCatalog({
    required this.categories,
    required this.items,
    required this.fetchedAt,
    required String? Function(T) categoryOf,
    required String Function(T) nameOf,
    required Object Function(T) idOf,
    DateTime? Function(T)? dateOf,
    double? Function(T)? ratingOf,
    int? Function(T)? releaseYearOf,
    this.genreSource,
  }) : _nameOf = nameOf,
       _dateOf = dateOf,
       _ratingOf = ratingOf,
       _releaseYearOf = releaseYearOf {
    for (final (i, item) in items.indexed) {
      _byId[idOf(item)] = i;
      if (categoryOf(item) case final id?) (_byCategory[id] ??= []).add(i);
    }
  }

  /// A movie catalogue.
  static VodCatalog<Movie> movies({
    required List<Category> categories,
    required List<Movie> items,
    required DateTime fetchedAt,
  }) => VodCatalog(
    categories: categories,
    items: items,
    fetchedAt: fetchedAt,
    categoryOf: (m) => m.categoryId,
    nameOf: (m) => m.name,
    idOf: (m) => m.streamId,
    dateOf: (m) => m.added,
    ratingOf: (m) => m.rating,
    releaseYearOf: (m) => readYear(m.releaseDate),
  );

  /// A series catalogue.
  static VodCatalog<Series> series({
    required List<Category> categories,
    required List<Series> items,
    required DateTime fetchedAt,
  }) => VodCatalog(
    categories: categories,
    items: items,
    fetchedAt: fetchedAt,
    categoryOf: (s) => s.categoryId,
    nameOf: (s) => s.name,
    idOf: (s) => s.seriesId,
    dateOf: (s) => s.lastModified,
    ratingOf: (s) => s.rating,
    releaseYearOf: (s) => readYear(s.releaseDate),
    genreSource: (s) => splitGenres(s.genre),
  );

  final List<Category> categories;

  /// Items in provider order.
  final List<T> items;

  /// When the catalogue was downloaded (UTC).
  final DateTime fetchedAt;

  /// The provider's genres of an item; null when it sends none (movies).
  final GenreSource<T>? genreSource;

  final String Function(T) _nameOf;
  final DateTime? Function(T)? _dateOf;
  final double? Function(T)? _ratingOf;
  final int? Function(T)? _releaseYearOf;
  final Map<String, List<int>> _byCategory = {};
  final Map<Object, int> _byId = {};

  SearchIndex? _searchIndex;

  /// The search index of the item names, built on first use unless
  /// [attachSearchIndex] gave one (built in a background isolate).
  SearchIndex get searchIndex =>
      _searchIndex ??= SearchIndex([for (final item in items) _nameOf(item)]);

  /// Whether the search index is built (or attached).
  bool get hasSearchIndex => _searchIndex != null;

  /// Uses [index], built elsewhere from the item names in order, instead
  /// of building one on first use.
  void attachSearchIndex(SearchIndex index) {
    if (index.length != items.length) {
      throw ArgumentError(
        'Search index of ${index.length} names for '
        '${items.length} items',
      );
    }
    _searchIndex = index;
  }

  /// The item names in order, for building a [SearchIndex] elsewhere.
  List<String> get names => [for (final item in items) _nameOf(item)];

  /// The item with [id] (a movie's stream id or a series id), if present.
  T? byId(Object id) => switch (_byId[id]) {
    final i? => items[i],
    null => null,
  };

  /// Number of items in [categoryId].
  int countIn(String categoryId) => _byCategory[categoryId]?.length ?? 0;

  /// Number of items outside the [hidden] categories.
  int countExcluding(Set<String> hidden) =>
      items.length - hidden.fold(0, (n, id) => n + countIn(id));

  /// The release year of the item at [index]: from its release date, else
  /// from a `(YYYY)` at the end of its name.
  int? _yearAt(int index) =>
      _releaseYearOf?.call(items[index]) ?? searchIndex.titleYear(index);

  /// Positions of the items in [scope].
  List<int> _indexes(VodScope scope) => switch (scope) {
    AllItems(:final hidden) when hidden.isEmpty => List.generate(
      items.length,
      (i) => i,
    ),
    AllItems(:final hidden) => () {
      final skip = {for (final id in hidden) ...?_byCategory[id]};
      return [
        for (var i = 0; i < items.length; i++)
          if (!skip.contains(i)) i,
      ];
    }(),
    CategoryItems(:final id) => _byCategory[id] ?? const [],
    PickedItems(:final ids) => [for (final id in ids) ?_byId[id]],
  };

  /// Items in [scope] matching [search] (see [SearchQuery]) and
  /// [filters], ordered by [sort] (null keeps the scope's order).
  ///
  /// Year filters use the release date, else a `(YYYY)` at the end of
  /// the name, and the [currentYear]; genre filters use
  /// [genres], or the provider's ([genreSource]) when null.
  List<T> query({
    VodScope scope = const VodScope.all(),
    String search = '',
    VodFilters filters = const VodFilters(),
    VodSort? sort,
    GenreSource<T>? genres,
    int? currentYear,
  }) {
    var indexes = _indexes(scope);
    final q = SearchQuery(search);
    if (!q.isEmpty) {
      final hits = searchIndex.matching(q);
      indexes = [
        for (final i in indexes)
          if (hits[i] == 1) i,
      ];
    }
    if (filters.years case final years?) {
      final now = currentYear ?? DateTime.now().year;
      indexes = [
        for (final i in indexes)
          if (_yearAt(i) case final y? when years.includes(y, now)) i,
      ];
    }
    final genreOf = genres ?? genreSource;
    if (filters.genres.isNotEmpty && genreOf != null) {
      final wanted = {for (final g in filters.genres) g.toLowerCase()};
      indexes = [
        for (final i in indexes)
          if (genreOf(items[i]).any((g) => wanted.contains(g.toLowerCase()))) i,
      ];
    }
    if (sort != null) indexes = _sorted(indexes, sort);
    return [for (final i in indexes) items[i]];
  }

  List<int> _sorted(List<int> indexes, VodSort sort) {
    // Ties keep their order: the position is the last comparison.
    final sorted = [...indexes];
    switch (sort) {
      case VodSort.recent:
        final dates = {
          for (final i in indexes)
            i: _dateOf?.call(items[i])?.millisecondsSinceEpoch,
        };
        sorted.sort((a, b) {
          final c = _compareDescNullsLast(dates[a], dates[b]);
          return c != 0 ? c : a.compareTo(b);
        });
      case VodSort.title:
        final keys = {for (final i in indexes) i: searchIndex.sortKey(i)};
        sorted.sort((a, b) {
          final c = keys[a]!.compareTo(keys[b]!);
          return c != 0 ? c : a.compareTo(b);
        });
      case VodSort.rating:
        // Panels send 0 for "not rated".
        final ratings = {
          for (final i in indexes)
            i: switch (_ratingOf?.call(items[i])) {
              final r? when r > 0 => r,
              _ => null,
            },
        };
        sorted.sort((a, b) {
          final c = _compareDescNullsLast(ratings[a], ratings[b]);
          return c != 0 ? c : a.compareTo(b);
        });
    }
    return sorted;
  }

  static int _compareDescNullsLast(num? a, num? b) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  /// The genres of the items in [scope] (from [genres], or the provider's
  /// when null) with how many items have each, most common first, then
  /// A to Z.
  List<({String genre, int count})> genreCounts({
    VodScope scope = const VodScope.all(),
    GenreSource<T>? genres,
  }) {
    final genreOf = genres ?? genreSource;
    if (genreOf == null) return const [];
    final counts = <String, int>{};
    final display = <String, String>{};
    for (final i in _indexes(scope)) {
      for (final g in genreOf(items[i])) {
        final key = g.toLowerCase();
        display.putIfAbsent(key, () => g);
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final list = [
      for (final MapEntry(:key, :value) in counts.entries)
        (genre: display[key]!, count: value),
    ];
    list.sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.genre.compareTo(b.genre);
    });
    return list;
  }

  /// The catalogue as JSON, for the disk cache. Pass [toJson] for the item
  /// type (e.g. [Movie.toJson]).
  Map<String, Object?> toJson(Map<String, Object?> Function(T) toJson) => {
    'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    'categories': [
      for (final c in categories)
        {
          'category_id': c.id,
          'category_name': c.name,
          'parent_id': ?c.parentId,
        },
    ],
    'items': [for (final item in items) toJson(item)],
  };

  /// Reads [toJson]'s output back; null when it isn't a catalogue.
  static VodCatalog<Movie>? moviesFromJson(Object? json) {
    final parts = _parts(json, Movie.fromJson);
    if (parts == null) return null;
    return VodCatalog.movies(
      categories: parts.categories,
      items: parts.items,
      fetchedAt: parts.fetchedAt,
    );
  }

  /// Reads [toJson]'s output back; null when it isn't a catalogue.
  static VodCatalog<Series>? seriesFromJson(Object? json) {
    final parts = _parts(json, Series.fromJson);
    if (parts == null) return null;
    return VodCatalog.series(
      categories: parts.categories,
      items: parts.items,
      fetchedAt: parts.fetchedAt,
    );
  }

  static ({List<Category> categories, List<I> items, DateTime fetchedAt})?
  _parts<I>(Object? json, I? Function(Map<String, Object?>) parse) {
    final map = readMap(json);
    final fetched = readInt(map?['fetchedAt']);
    if (map == null || fetched == null) return null;
    List<X> list<X>(Object? value, X? Function(Map<String, Object?>) f) =>
        readList(value)
            .map(readMap)
            .whereType<Map<String, Object?>>()
            .map(f)
            .whereType<X>()
            .toList();
    return (
      categories: list(map['categories'], Category.fromJson),
      items: list(map['items'], parse),
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetched, isUtc: true),
    );
  }
}
