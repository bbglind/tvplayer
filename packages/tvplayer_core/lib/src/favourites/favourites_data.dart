import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../util/json.dart';

/// What a favourite category holds, and which provider list a hidden
/// category belongs to.
enum ContentKind { live, movie, series }

/// A new random id for a [FavouriteCategory]: 32 hex digits (128 bits), so
/// ids made on different devices never clash.
String newFavouriteId([Random? random]) {
  final r = random ?? Random.secure();
  return [
    for (var i = 0; i < 16; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// A provider item: a live channel ([LiveStream.stableId]), a movie's stream
/// id or a series id, as a string.
final class ItemRef {
  const ItemRef(this.kind, this.id);

  final ContentKind kind;
  final String id;

  String get key => '${kind.name}:$id';

  @override
  bool operator ==(Object other) =>
      other is ItemRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'ItemRef($key)';
}

/// One of the user's own categories ("My categories").
final class FavouriteCategory {
  const FavouriteCategory({
    required this.id,
    required this.kind,
    required this.name,
    required this.icon,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  /// Stable and unique ([newFavouriteId]).
  final String id;
  final ContentKind kind;
  final String name;

  /// Icon key; the UI maps it to an icon and falls back for unknown keys.
  final String icon;

  /// Position among the categories of the same [kind], ascending.
  final int sortOrder;
  final DateTime createdAt;

  /// Last change (UTC). The newer record wins when merging copies.
  final DateTime updatedAt;

  /// Tombstone: deleted, kept so the deletion survives a merge.
  final bool deleted;

  FavouriteCategory copyWith({
    String? name,
    String? icon,
    int? sortOrder,
    bool? deleted,
    required DateTime updatedAt,
  }) => FavouriteCategory(
    id: id,
    kind: kind,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted ?? this.deleted,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'icon': icon,
    'order': sortOrder,
    'created': createdAt.millisecondsSinceEpoch,
  };

  static FavouriteCategory? fromJson(
    Object? json,
    DateTime updatedAt, {
    required bool deleted,
  }) {
    final map = readMap(json);
    final id = readString(map?['id']);
    final kind = _kind(map?['kind']);
    if (map == null || id == null || kind == null) return null;
    final created = readInt(map['created']);
    return FavouriteCategory(
      id: id,
      kind: kind,
      name: readString(map['name']) ?? '',
      icon: readString(map['icon']) ?? '',
      sortOrder: readInt(map['order']) ?? 0,
      createdAt: created == null ? updatedAt : _time(created),
      updatedAt: updatedAt,
      deleted: deleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FavouriteCategory &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.icon == icon &&
      other.sortOrder == sortOrder &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    name,
    icon,
    sortOrder,
    createdAt,
    updatedAt,
    deleted,
  );

  @override
  String toString() =>
      'FavouriteCategory($id, $name${deleted ? ', deleted' : ''})';
}

/// An item in a [FavouriteCategory].
final class FavouriteMembership {
  const FavouriteMembership({
    required this.categoryId,
    required this.item,
    required this.name,
    required this.addedAt,
    required this.updatedAt,
    this.deleted = false,
  });

  final String categoryId;
  final ItemRef item;

  /// The item's name when it was added, shown when the provider no longer
  /// lists it.
  final String name;

  /// When the item was (last) added; items are listed in this order.
  final DateTime addedAt;
  final DateTime updatedAt;

  /// Tombstone: removed from the category.
  final bool deleted;

  String get key => membershipKey(categoryId, item);

  static String membershipKey(String categoryId, ItemRef item) =>
      '$categoryId|${item.key}';

  Map<String, Object?> toJson() => {
    'category': categoryId,
    'kind': item.kind.name,
    'item': item.id,
    'name': name,
    'added': addedAt.millisecondsSinceEpoch,
  };

  static FavouriteMembership? fromJson(
    Object? json,
    DateTime updatedAt, {
    required bool deleted,
  }) {
    final map = readMap(json);
    final category = readString(map?['category']);
    final kind = _kind(map?['kind']);
    final item = readString(map?['item']);
    if (map == null || category == null || kind == null || item == null) {
      return null;
    }
    final added = readInt(map['added']);
    return FavouriteMembership(
      categoryId: category,
      item: ItemRef(kind, item),
      name: readString(map['name']) ?? '',
      addedAt: added == null ? updatedAt : _time(added),
      updatedAt: updatedAt,
      deleted: deleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FavouriteMembership &&
      other.categoryId == categoryId &&
      other.item == item &&
      other.name == name &&
      other.addedAt == addedAt &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode =>
      Object.hash(categoryId, item, name, addedAt, updatedAt, deleted);
}

/// Whether a provider category is hidden. Showing it again keeps the
/// record with [hidden] false, so the change wins a merge.
final class HiddenCategory {
  const HiddenCategory({
    required this.kind,
    required this.categoryId,
    required this.hidden,
    required this.updatedAt,
  });

  final ContentKind kind;

  /// The provider's category id.
  final String categoryId;
  final bool hidden;
  final DateTime updatedAt;

  String get key => hiddenKey(kind, categoryId);

  static String hiddenKey(ContentKind kind, String categoryId) =>
      '${kind.name}:$categoryId';

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'category': categoryId,
    'hidden': hidden,
  };

  static HiddenCategory? fromJson(Object? json, DateTime updatedAt) {
    final map = readMap(json);
    final kind = _kind(map?['kind']);
    final category = readString(map?['category']);
    if (map == null || kind == null || category == null) return null;
    return HiddenCategory(
      kind: kind,
      categoryId: category,
      hidden: readBool(map['hidden']),
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HiddenCategory &&
      other.kind == kind &&
      other.categoryId == categoryId &&
      other.hidden == hidden &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(kind, categoryId, hidden, updatedAt);
}

ContentKind? _kind(Object? json) {
  final name = readString(json);
  for (final k in ContentKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

DateTime _time(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

/// The user's favourite categories, their items and the hidden provider
/// categories, for one provider.
///
/// Like [WatchData] it is a set of records with keys and change times, and
/// deletions are kept as tombstones, so copies from several devices can be
/// combined with [merge]. Change it with the functions in
/// `favourites_logic.dart`.
final class FavouritesData {
  FavouritesData({
    this.categories = const {},
    this.memberships = const {},
    this.hidden = const {},
  });

  /// Categories by id, including deleted ones.
  final Map<String, FavouriteCategory> categories;

  /// Memberships by [FavouriteMembership.key], including removed ones.
  final Map<String, FavouriteMembership> memberships;

  /// Hidden-category records by [HiddenCategory.key].
  final Map<String, HiddenCategory> hidden;

  static final empty = FavouritesData();

  /// The live categories of [kind] in display order.
  List<FavouriteCategory> categoriesOf(ContentKind kind) =>
      _sorted[kind] ?? const [];

  /// The category with [id], unless it is deleted.
  FavouriteCategory? category(String id) {
    final c = categories[id];
    return c == null || c.deleted ? null : c;
  }

  /// Items of category [id] in the order they were added.
  List<FavouriteMembership> itemsIn(String id) => _items[id] ?? const [];

  int countIn(String id) => itemsIn(id).length;

  /// Ids of the categories [item] is in.
  Set<String> categoriesContaining(ItemRef item) => _byItem[item] ?? const {};

  /// Whether [item] is in at least one category.
  bool isFavourite(ItemRef item) => _byItem.containsKey(item);

  /// Ids of the hidden provider categories of [kind].
  Set<String> hiddenIds(ContentKind kind) => _hidden[kind] ?? const {};

  late final Map<ContentKind, List<FavouriteCategory>> _sorted = () {
    final byKind = <ContentKind, List<FavouriteCategory>>{};
    for (final c in categories.values) {
      if (!c.deleted) (byKind[c.kind] ??= []).add(c);
    }
    for (final list in byKind.values) {
      list.sort(
        (a, b) => a.sortOrder != b.sortOrder
            ? a.sortOrder.compareTo(b.sortOrder)
            : a.createdAt != b.createdAt
            ? a.createdAt.compareTo(b.createdAt)
            : a.id.compareTo(b.id),
      );
    }
    return byKind;
  }();

  late final Map<String, List<FavouriteMembership>> _items = () {
    final byCategory = <String, List<FavouriteMembership>>{};
    for (final m in memberships.values) {
      // Only items whose category exists and matches their kind.
      if (m.deleted || category(m.categoryId)?.kind != m.item.kind) continue;
      (byCategory[m.categoryId] ??= []).add(m);
    }
    for (final list in byCategory.values) {
      list.sort(
        (a, b) => a.addedAt != b.addedAt
            ? a.addedAt.compareTo(b.addedAt)
            : a.key.compareTo(b.key),
      );
    }
    return byCategory;
  }();

  late final Map<ItemRef, Set<String>> _byItem = () {
    final byItem = <ItemRef, Set<String>>{};
    for (final MapEntry(:key, :value) in _items.entries) {
      for (final m in value) {
        (byItem[m.item] ??= {}).add(key);
      }
    }
    return byItem;
  }();

  late final Map<ContentKind, Set<String>> _hidden = () {
    final byKind = <ContentKind, Set<String>>{};
    for (final h in hidden.values) {
      if (h.hidden) (byKind[h.kind] ??= {}).add(h.categoryId);
    }
    return byKind;
  }();

  FavouritesData copyWith({
    Map<String, FavouriteCategory>? categories,
    Map<String, FavouriteMembership>? memberships,
    Map<String, HiddenCategory>? hidden,
  }) => FavouritesData(
    categories: categories ?? this.categories,
    memberships: memberships ?? this.memberships,
    hidden: hidden ?? this.hidden,
  );

  /// Combines two copies: for each record, the one changed last wins
  /// (tombstones included).
  FavouritesData merge(FavouritesData other) {
    Map<K, V> newest<K, V>(
      Map<K, V> a,
      Map<K, V> b,
      DateTime Function(V) time,
    ) => {
      ...a,
      for (final MapEntry(:key, :value) in b.entries)
        if (a[key] == null || time(value).isAfter(time(a[key] as V)))
          key: value,
    };
    return FavouritesData(
      categories: newest(categories, other.categories, (c) => c.updatedAt),
      memberships: newest(memberships, other.memberships, (m) => m.updatedAt),
      hidden: newest(hidden, other.hidden, (h) => h.updatedAt),
    );
  }

  /// The records as JSON: `{"version": 1, "records": [{"k", "t", "v",
  /// "d"}]}`, with `t` the change time in milliseconds since the epoch and
  /// `d` set on tombstones.
  Map<String, Object?> toJson() {
    Map<String, Object?> record(
      String key,
      DateTime time,
      Object? value, {
      bool deleted = false,
    }) => {
      'k': key,
      't': time.millisecondsSinceEpoch,
      'v': value,
      if (deleted) 'd': true,
    };
    return {
      'version': 1,
      'records': [
        for (final c in categories.values)
          record(
            'category:${c.id}',
            c.updatedAt,
            c.toJson(),
            deleted: c.deleted,
          ),
        for (final m in memberships.values)
          record(
            'member:${m.key}',
            m.updatedAt,
            m.toJson(),
            deleted: m.deleted,
          ),
        for (final h in hidden.values)
          record('hidden:${h.key}', h.updatedAt, h.toJson()),
      ],
    };
  }

  /// Lenient inverse of [toJson]; unreadable records are skipped. Null when
  /// [json] isn't favourites data at all (e.g. a damaged file).
  static FavouritesData? fromJson(Object? json) {
    final map = readMap(json);
    final records = map?['records'];
    if (map == null || records is! List) return null;
    final categories = <String, FavouriteCategory>{};
    final memberships = <String, FavouriteMembership>{};
    final hidden = <String, HiddenCategory>{};
    for (final r in records) {
      final record = readMap(r);
      final key = readString(record?['k']);
      final ms = readInt(record?['t']);
      if (record == null || key == null || ms == null) continue;
      final time = _time(ms);
      final value = record['v'];
      final deleted = readBool(record['d']);
      final colon = key.indexOf(':');
      if (colon < 0) continue;
      switch (key.substring(0, colon)) {
        case 'category':
          if (FavouriteCategory.fromJson(value, time, deleted: deleted)
              case final c?) {
            categories[c.id] = c;
          }
        case 'member':
          if (FavouriteMembership.fromJson(value, time, deleted: deleted)
              case final m?) {
            memberships[m.key] = m;
          }
        case 'hidden':
          if (HiddenCategory.fromJson(value, time) case final h?) {
            hidden[h.key] = h;
          }
      }
    }
    return FavouritesData(
      categories: categories,
      memberships: memberships,
      hidden: hidden,
    );
  }
}

/// Persists [FavouritesData] for one provider. The local file store is the
/// only one today; a sync server can be added like for `WatchStore`.
abstract interface class FavouritesStore {
  /// The saved data; empty when none is saved or it can't be read.
  Future<FavouritesData> load();

  Future<void> save(FavouritesData data);
}

/// [FavouritesStore] in a JSON file, with a backup.
///
/// After a successful load the file is copied to `<file>.bak`. A file that
/// can't be read is moved aside to `<file>.corrupt` (so it is never
/// overwritten and can be recovered by hand) and the backup is used
/// instead. Saving writes a temporary file and renames it, so a crash
/// never leaves a half-written file.
class JsonFileFavouritesStore implements FavouritesStore {
  JsonFileFavouritesStore(this.file);

  final File file;

  File get _backup => File('${file.path}.bak');

  File get _corrupt => File('${file.path}.corrupt');

  @override
  Future<FavouritesData> load() async {
    final (data, exists) = await _read(file);
    if (data != null) {
      try {
        await file.copy(_backup.path);
      } on Exception {
        // The data loaded; only the backup is missing.
      }
      return data;
    }
    if (exists) {
      try {
        await file.rename(_corrupt.path);
      } on Exception {
        // Left in place; the next save replaces it.
      }
    }
    return (await _read(_backup)).$1 ?? FavouritesData.empty;
  }

  /// The data in [f], and whether [f] exists.
  static Future<(FavouritesData?, bool)> _read(File f) async {
    try {
      if (!await f.exists()) return (null, false);
      return (
        FavouritesData.fromJson(jsonDecode(await f.readAsString())),
        true,
      );
    } on Exception {
      return (null, true);
    }
  }

  @override
  Future<void> save(FavouritesData data) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}
