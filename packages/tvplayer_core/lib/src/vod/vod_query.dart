/// How a movie or series list is ordered.
enum VodSort {
  /// Newest first: movies by when they were added, series by when they
  /// were last updated.
  recent,

  /// By title without the provider tag, A to Z.
  title,

  /// Highest rating first; items without a rating last.
  rating;

  /// The sort with [name], or null.
  static VodSort? byName(String? name) =>
      values.where((s) => s.name == name).firstOrNull;
}

/// A release year filter: the last few years ([YearFilter.recent]) or a
/// range of years ([YearFilter.range]).
final class YearFilter {
  /// The current year and the [years] - 1 before it: 1 is this year only.
  const YearFilter.recent(int this.years) : from = null, to = null;

  /// [from] to [to], both included; either may be open.
  const YearFilter.range({this.from, this.to}) : years = null;

  final int? years;
  final int? from;
  final int? to;

  /// The first and last year included, given the [currentYear].
  (int? from, int? to) bounds(int currentYear) => switch (years) {
    final n? => (currentYear - n + 1, currentYear),
    null => (from, to),
  };

  bool includes(int year, int currentYear) {
    final (from, to) = bounds(currentYear);
    return (from == null || year >= from) && (to == null || year <= to);
  }

  @override
  bool operator ==(Object other) =>
      other is YearFilter &&
      other.years == years &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(years, from, to);

  @override
  String toString() => years != null
      ? 'YearFilter.recent($years)'
      : 'YearFilter.range($from, $to)';
}

/// The year and genre filters of a movie or series list. Items without a
/// year are left out only while [years] is set; with [genres] selected,
/// items having any of them are kept.
final class VodFilters {
  const VodFilters({this.years, this.genres = const {}});

  final YearFilter? years;
  final Set<String> genres;

  bool get isEmpty => years == null && genres.isEmpty;

  VodFilters withYears(YearFilter? years) =>
      VodFilters(years: years, genres: genres);

  VodFilters withGenres(Set<String> genres) =>
      VodFilters(years: years, genres: genres);

  @override
  bool operator ==(Object other) =>
      other is VodFilters &&
      other.years == years &&
      other.genres.length == genres.length &&
      other.genres.containsAll(genres);

  @override
  int get hashCode => Object.hash(years, Object.hashAllUnordered(genres));
}

/// The genres of an item. Series get theirs from the provider
/// ([splitGenres] of `Series.genre`); movies have none in the provider's
/// list, so another source (e.g. TMDB) can be plugged in later.
typedef GenreSource<T> = List<String> Function(T item);

/// The genres in a provider's genre text like `"Crime / Drama"` or
/// `"Action & Adventure / Mystery"`: split on `/` (and `,` or `|`, which
/// some panels use), trimmed, without duplicates. `"Action & Adventure"`
/// stays one genre.
List<String> splitGenres(String? genre) {
  if (genre == null || genre.isEmpty) return const [];
  final seen = <String>{};
  return [
    for (final part in genre.split(_genreSeparator))
      if (part.trim().replaceAll(_spaces, ' ') case final g
          when g.isNotEmpty && seen.add(g.toLowerCase()))
        g,
  ];
}

final _genreSeparator = RegExp('[/,|]');
final _spaces = RegExp(r'\s+');
