import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'providers.dart';

/// My categories, their items and the hidden provider categories of the
/// active provider. Changes apply at once and are saved in the background,
/// after the saved data has been read.
class FavouritesController extends Notifier<FavouritesData> {
  FavouritesStore? _store;
  Future<void> _saving = Future.value();

  @override
  FavouritesData build() {
    final key = ref.watch(providerKeyProvider);
    if (key == null) {
      _store = null;
      return FavouritesData.empty;
    }
    final store = _store = ref.watch(favouritesStoreProvider)(key);
    // Saves wait for the load, so they never replace unread data.
    _saving = _load(store);
    return FavouritesData.empty;
  }

  Future<void> _load(FavouritesStore store) async {
    FavouritesData saved;
    try {
      saved = await store.load();
    } catch (e) {
      debugPrint('Could not read the favourites (${e.runtimeType})');
      return;
    }
    if (!ref.mounted || !identical(store, _store)) return;
    // Keep anything changed while loading.
    state = saved.merge(state);
  }

  /// Completes when everything changed so far is saved.
  @visibleForTesting
  Future<void> get saved => _saving;

  void _update(FavouritesData data) {
    if (!ref.mounted || identical(data, state)) return;
    state = data;
    final store = _store;
    if (store == null) return;
    _saving = _saving.then((_) async {
      try {
        await store.save(state);
      } catch (e) {
        debugPrint('Could not save the favourites (${e.runtimeType})');
      }
    });
  }

  DateTime get _now => DateTime.now().toUtc();

  /// Creates a category at the end of [kind]'s list; null when [name] is
  /// empty.
  FavouriteCategory? create(ContentKind kind, String name, String icon) {
    final (data, category) = createCategory(
      state,
      kind: kind,
      name: name,
      icon: icon,
      now: _now,
    );
    _update(data);
    return category;
  }

  /// Renames category [id] and sets its icon.
  void edit(String id, {required String name, required String icon}) => _update(
    setCategoryIcon(
      renameCategory(state, id, name, now: _now),
      id,
      icon,
      now: _now,
    ),
  );

  void move(String id, int toIndex) =>
      _update(moveCategory(state, id, toIndex: toIndex, now: _now));

  void delete(String id) => _update(deleteCategory(state, id, now: _now));

  /// Adds [item] to category [categoryId] or removes it.
  void setMember(
    String categoryId,
    ItemRef item, {
    required String name,
    required bool member,
  }) => _update(
    setMembership(
      state,
      categoryId,
      item,
      name: name,
      member: member,
      now: _now,
    ),
  );

  /// Hides or shows the provider categories [ids] of [kind].
  void setHidden(ContentKind kind, Iterable<String> ids, bool hidden) =>
      _update(setCategoriesHidden(state, kind, ids, hidden: hidden, now: _now));
}
