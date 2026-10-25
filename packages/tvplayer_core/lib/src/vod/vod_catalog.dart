import '../models/category.dart';
import '../models/movie.dart';
import '../models/series.dart';
import '../util/json.dart';

/// Categories and items (movies or series) of one provider, with a
/// per-category index and name search. Built once per download, so lookups
/// stay fast for catalogues with tens of thousands of items.
final class VodCatalog<T extends Object> {
  VodCatalog({
    required this.categories,
    required this.items,
    required this.fetchedAt,
    required String? Function(T) categoryOf,
    required String Function(T) nameOf,
    required Object Function(T) idOf,
  }) : _names = [for (final item in items) nameOf(item).toLowerCase()] {
    for (final (i, item) in items.indexed) {
      _byId[idOf(item)] = item;
      _index[item] = i;
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
  );

  final List<Category> categories;

  /// Items in provider order.
  final List<T> items;

  /// When the catalogue was downloaded (UTC).
  final DateTime fetchedAt;

  /// Lower-case names, parallel to [items].
  final List<String> _names;
  final Map<String, List<int>> _byCategory = {};
  final Map<Object, T> _byId = {};
  final Map<T, int> _index = Map.identity();

  /// The item with [id] (a movie's stream id or a series id), if present.
  T? byId(Object id) => _byId[id];

  /// Number of items in [categoryId].
  int countIn(String categoryId) => _byCategory[categoryId]?.length ?? 0;

  /// Number of items outside the [hidden] categories.
  int countExcluding(Set<String> hidden) =>
      items.length - hidden.fold(0, (n, id) => n + countIn(id));

  /// Items in [categoryId] (all items when null) whose name contains
  /// [query], case-insensitively. With no [categoryId], items in the
  /// [hidden] categories are left out.
  List<T> filter({
    String? categoryId,
    String query = '',
    Set<String> hidden = const {},
  }) {
    final q = query.trim().toLowerCase();
    final Iterable<int> indexes;
    if (categoryId != null) {
      indexes = _byCategory[categoryId] ?? const [];
    } else if (hidden.isEmpty) {
      if (q.isEmpty) return items;
      indexes = Iterable.generate(items.length);
    } else {
      final skip = {for (final id in hidden) ...?_byCategory[id]};
      indexes = [
        for (var i = 0; i < items.length; i++)
          if (!skip.contains(i)) i,
      ];
    }
    return [
      for (final i in indexes)
        if (q.isEmpty || _names[i].contains(q)) items[i],
    ];
  }

  /// The items with [ids] that are in the catalogue, in that order, whose
  /// name contains [query].
  List<T> pick(Iterable<Object> ids, {String query = ''}) {
    final q = query.trim().toLowerCase();
    return [
      for (final id in ids)
        if (_byId[id] case final item?)
          if (q.isEmpty || _nameOf(item).contains(q)) item,
    ];
  }

  String _nameOf(T item) => _names[_index[item]!];

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
