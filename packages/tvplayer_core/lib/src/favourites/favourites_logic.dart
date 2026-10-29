import '../live/live_source.dart';
import '../models/category.dart';
import '../models/movie.dart';
import '../models/series.dart';
import 'favourites_data.dart';

/// The [ItemRef] of a live channel: its [LiveStream.stableId].
ItemRef liveItemRef(LiveStream channel) =>
    ItemRef(ContentKind.live, channel.stableId);

ItemRef movieItemRef(Movie movie) =>
    ItemRef(ContentKind.movie, '${movie.streamId}');

ItemRef seriesItemRef(Series series) =>
    ItemRef(ContentKind.series, '${series.seriesId}');

/// Longest allowed category name.
const maxFavouriteNameLength = 40;

/// [name] trimmed and shortened to [maxFavouriteNameLength]; null when
/// nothing is left.
String? cleanFavouriteName(String name) {
  final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return null;
  return trimmed.length <= maxFavouriteNameLength
      ? trimmed
      : trimmed.substring(0, maxFavouriteNameLength).trimRight();
}

/// [data] with a new category of [kind] at the end of the list. Returns
/// [data] unchanged and a null category when [name] is empty.
(FavouritesData, FavouriteCategory?) createCategory(
  FavouritesData data, {
  required ContentKind kind,
  required String name,
  required String icon,
  required DateTime now,
  String Function()? newId,
}) {
  final clean = cleanFavouriteName(name);
  if (clean == null) return (data, null);
  final existing = data.categoriesOf(kind);
  var id = (newId ?? newFavouriteId)();
  while (data.categories.containsKey(id)) {
    id = newFavouriteId();
  }
  final category = FavouriteCategory(
    id: id,
    kind: kind,
    name: clean,
    icon: icon,
    sortOrder: existing.isEmpty ? 0 : existing.last.sortOrder + 1,
    createdAt: now,
    updatedAt: now,
  );
  return (
    data.copyWith(categories: {...data.categories, id: category}),
    category,
  );
}

FavouritesData _updateCategory(
  FavouritesData data,
  String id,
  FavouriteCategory Function(FavouriteCategory) change,
) {
  final category = data.category(id);
  if (category == null) return data;
  final changed = change(category);
  if (changed == category) return data;
  return data.copyWith(categories: {...data.categories, id: changed});
}

/// [data] with category [id] renamed; unchanged when [name] is empty.
FavouritesData renameCategory(
  FavouritesData data,
  String id,
  String name, {
  required DateTime now,
}) {
  final clean = cleanFavouriteName(name);
  if (clean == null) return data;
  return _updateCategory(
    data,
    id,
    (c) => c.name == clean ? c : c.copyWith(name: clean, updatedAt: now),
  );
}

/// [data] with category [id] showing [icon].
FavouritesData setCategoryIcon(
  FavouritesData data,
  String id,
  String icon, {
  required DateTime now,
}) => _updateCategory(
  data,
  id,
  (c) => c.icon == icon ? c : c.copyWith(icon: icon, updatedAt: now),
);

/// [data] with category [id] moved to position [toIndex] among the
/// categories of its kind (clamped). Only categories whose position
/// changes are touched.
FavouritesData moveCategory(
  FavouritesData data,
  String id, {
  required int toIndex,
  required DateTime now,
}) {
  final category = data.category(id);
  if (category == null) return data;
  final list = [...data.categoriesOf(category.kind)];
  final from = list.indexWhere((c) => c.id == id);
  final to = toIndex.clamp(0, list.length - 1);
  if (from == to) return data;
  list.insert(to, list.removeAt(from));
  final changed = {...data.categories};
  for (final (i, c) in list.indexed) {
    if (c.sortOrder != i) {
      changed[c.id] = c.copyWith(sortOrder: i, updatedAt: now);
    }
  }
  return data.copyWith(categories: changed);
}

/// [data] with category [id] and its items deleted (as tombstones).
FavouritesData deleteCategory(
  FavouritesData data,
  String id, {
  required DateTime now,
}) {
  final category = data.category(id);
  if (category == null) return data;
  return data.copyWith(
    categories: {
      ...data.categories,
      id: category.copyWith(deleted: true, updatedAt: now),
    },
    memberships: {
      ...data.memberships,
      for (final m in data.itemsIn(id))
        m.key: FavouriteMembership(
          categoryId: id,
          item: m.item,
          name: m.name,
          addedAt: m.addedAt,
          updatedAt: now,
          order: m.order,
          deleted: true,
        ),
    },
  );
}

/// [data] with [item] added to ([member] true) or removed from category
/// [categoryId]. An added item goes first in the category. [name] is
/// remembered for when the provider drops the item. Unchanged when the
/// category doesn't exist or holds another kind.
FavouritesData setMembership(
  FavouritesData data,
  String categoryId,
  ItemRef item, {
  required String name,
  required bool member,
  required DateTime now,
}) {
  if (data.category(categoryId)?.kind != item.kind) return data;
  final key = FavouriteMembership.membershipKey(categoryId, item);
  final current = data.memberships[key];
  final isMember = current != null && !current.deleted;
  if (isMember == member) return data;
  final items = data.itemsIn(categoryId);
  final first = items.isEmpty ? 1 : items.first.order;
  return data.copyWith(
    memberships: {
      ...data.memberships,
      key: FavouriteMembership(
        categoryId: categoryId,
        item: item,
        name: name,
        addedAt: member ? now : current!.addedAt,
        updatedAt: now,
        order: member ? first - 1 : current!.order,
        deleted: !member,
      ),
    },
  );
}

/// [data] with [item] removed from all my categories ("Remove from
/// favourites"). Also returns its memberships as they were, for
/// [restoreMemberships].
(FavouritesData, List<FavouriteMembership>) removeFromMyCategories(
  FavouritesData data,
  ItemRef item, {
  required DateTime now,
}) {
  final previous = [
    for (final id in data.categoriesContaining(item))
      ?data.memberships[FavouriteMembership.membershipKey(id, item)],
  ];
  var result = data;
  for (final m in previous) {
    result = setMembership(
      result,
      m.categoryId,
      item,
      name: m.name,
      member: false,
      now: now,
    );
  }
  return (result, previous);
}

/// [data] with the [previous] memberships back, each at its old place in
/// its category (undoes [removeFromMyCategories]).
FavouritesData restoreMemberships(
  FavouritesData data,
  List<FavouriteMembership> previous, {
  required DateTime now,
}) {
  final restored = {
    for (final m in previous)
      if (data.category(m.categoryId) != null)
        m.key: FavouriteMembership(
          categoryId: m.categoryId,
          item: m.item,
          name: m.name,
          addedAt: m.addedAt,
          updatedAt: now,
          order: m.order,
        ),
  };
  if (restored.isEmpty) return data;
  return data.copyWith(memberships: {...data.memberships, ...restored});
}

/// [data] with the provider categories [ids] of [kind] hidden or shown.
FavouritesData setCategoriesHidden(
  FavouritesData data,
  ContentKind kind,
  Iterable<String> ids, {
  required bool hidden,
  required DateTime now,
}) {
  final current = data.hiddenIds(kind);
  final changed = {
    for (final id in ids)
      if (current.contains(id) != hidden)
        HiddenCategory.hiddenKey(kind, id): HiddenCategory(
          kind: kind,
          categoryId: id,
          hidden: hidden,
          updatedAt: now,
        ),
  };
  if (changed.isEmpty) return data;
  return data.copyWith(hidden: {...data.hidden, ...changed});
}

/// [data] with [item] moved to position [toIndex] (clamped) in category
/// [categoryId]. Only items whose position changes are touched.
FavouritesData moveFavouriteItem(
  FavouritesData data,
  String categoryId,
  ItemRef item, {
  required int toIndex,
  required DateTime now,
}) {
  final list = [...data.itemsIn(categoryId)];
  final from = list.indexWhere((m) => m.item == item);
  if (from < 0) return data;
  final to = toIndex.clamp(0, list.length - 1);
  if (from == to) return data;
  list.insert(to, list.removeAt(from));
  final changed = {...data.memberships};
  for (final (i, m) in list.indexed) {
    if (m.order != i) {
      changed[m.key] = FavouriteMembership(
        categoryId: m.categoryId,
        item: m.item,
        name: m.name,
        addedAt: m.addedAt,
        updatedAt: now,
        order: i,
      );
    }
  }
  return data.copyWith(memberships: changed);
}

/// [data] with the provider category [id] of [kind] moved to position
/// [toIndex] (clamped) of [categories], the provider's categories as
/// [FavouritesData.orderedCategories] lists them. The whole order is
/// saved, without categories the provider no longer has.
FavouritesData moveProviderCategory(
  FavouritesData data,
  ContentKind kind,
  List<Category> categories,
  String id, {
  required int toIndex,
  required DateTime now,
}) {
  final list = [...data.orderedCategories(kind, categories)];
  final from = list.indexWhere((c) => c.id == id);
  if (from < 0) return data;
  final to = toIndex.clamp(0, list.length - 1);
  if (from == to) return data;
  list.insert(to, list.removeAt(from));
  return _setCategoryOrder(data, kind, list, now);
}

FavouritesData _setCategoryOrder(
  FavouritesData data,
  ContentKind kind,
  List<Category> list,
  DateTime now,
) {
  final order = CategoryOrder(
    kind: kind,
    ids: [for (final c in list) c.id],
    names: [for (final c in list) c.name],
    updatedAt: now,
  );
  return data.copyWith(
    categoryOrders: {...data.categoryOrders, order.key: order},
  );
}

/// [data] with the provider categories of [kind] back in the provider's
/// order. Unchanged when they already are.
FavouritesData resetCategoryOrder(
  FavouritesData data,
  ContentKind kind, {
  required DateTime now,
}) {
  if (data.categoryOrder(kind) == null) return data;
  final reset = CategoryOrder(
    kind: kind,
    ids: const [],
    names: const [],
    updatedAt: now,
    deleted: true,
  );
  return data.copyWith(
    categoryOrders: {...data.categoryOrders, reset.key: reset},
  );
}

/// [data] with [previous] as the order again (undo of a reset); a null
/// [previous] resets.
FavouritesData restoreCategoryOrder(
  FavouritesData data,
  ContentKind kind,
  CategoryOrder? previous, {
  required DateTime now,
}) {
  if (previous == null) return resetCategoryOrder(data, kind, now: now);
  final order = CategoryOrder(
    kind: kind,
    ids: previous.ids,
    names: previous.names,
    updatedAt: now,
  );
  return data.copyWith(
    categoryOrders: {...data.categoryOrders, order.key: order},
  );
}
