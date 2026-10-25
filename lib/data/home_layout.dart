import 'package:flutter/foundation.dart';

/// The rows of the start page.
enum HomeRowId {
  featured('Featured'),
  channels('Recently viewed channels'),
  myCategories('My categories'),
  continueWatching('Continue watching'),
  recentSeries('Recently added series'),
  recentMovies('Recently added movies');

  const HomeRowId(this.title);

  /// The row heading.
  final String title;
}

/// One row of the start page and whether it is shown.
@immutable
final class HomeRow {
  const HomeRow(this.id, {this.visible = true});

  final HomeRowId id;
  final bool visible;

  @override
  bool operator ==(Object other) =>
      other is HomeRow && other.id == id && other.visible == visible;

  @override
  int get hashCode => Object.hash(id, visible);
}

/// Order and visibility of the start page rows.
@immutable
final class HomeLayout {
  /// [rows] in this order, followed by any row they leave out (shown).
  HomeLayout(Iterable<HomeRow> rows)
    : rows = List.unmodifiable(_complete(rows));

  const HomeLayout._defaults() : rows = _defaultRows;

  static const defaults = HomeLayout._defaults();

  static const _defaultRows = [
    HomeRow(HomeRowId.featured),
    HomeRow(HomeRowId.channels),
    HomeRow(HomeRowId.myCategories),
    HomeRow(HomeRowId.continueWatching),
    HomeRow(HomeRowId.recentSeries),
    HomeRow(HomeRowId.recentMovies),
  ];

  final List<HomeRow> rows;

  static List<HomeRow> _complete(Iterable<HomeRow> rows) {
    final seen = <HomeRowId>{};
    return [
      for (final r in rows)
        if (seen.add(r.id)) r,
      for (final id in HomeRowId.values)
        if (!seen.contains(id)) HomeRow(id),
    ];
  }

  /// This layout with [id] moved [by] places (negative: up), within bounds.
  HomeLayout move(HomeRowId id, int by) {
    final list = [...rows];
    final from = list.indexWhere((r) => r.id == id);
    final to = (from + by).clamp(0, list.length - 1);
    if (from < 0 || from == to) return this;
    list.insert(to, list.removeAt(from));
    return HomeLayout(list);
  }

  /// This layout with [id] shown or hidden.
  HomeLayout withVisible(HomeRowId id, bool visible) => HomeLayout([
    for (final r in rows) r.id == id ? HomeRow(id, visible: visible) : r,
  ]);

  List<Map<String, Object?>> toJson() => [
    for (final r in rows) {'id': r.id.name, 'visible': r.visible},
  ];

  /// Lenient inverse of [toJson]: unknown rows are dropped and missing
  /// ones added at the end, shown.
  factory HomeLayout.fromJson(Object? json) {
    if (json is! List) return defaults;
    return HomeLayout([
      for (final item in json)
        if (item is Map)
          if (HomeRowId.values.asNameMap()[item['id']] case final id?)
            HomeRow(id, visible: item['visible'] != false),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is HomeLayout && listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hashAll(rows);
}
