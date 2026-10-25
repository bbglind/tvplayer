import 'package:flutter/foundation.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// What a category list has selected: everything, a provider category or
/// one of the user's own categories.
@immutable
sealed class CategorySelection {
  const CategorySelection();

  /// This selection, or [AllCategories] when it points at one of my
  /// categories that no longer exists or at a hidden provider category.
  CategorySelection resolve(FavouritesData favourites, ContentKind kind) =>
      switch (this) {
        MyCategory(:final id) when favourites.category(id)?.kind != kind =>
          const AllCategories(),
        ProviderCategory(:final id)
            when favourites.hiddenIds(kind).contains(id) =>
          const AllCategories(),
        _ => this,
      };
}

/// All channels, movies or series, without hidden provider categories.
final class AllCategories extends CategorySelection {
  const AllCategories();

  @override
  bool operator ==(Object other) => other is AllCategories;

  @override
  int get hashCode => 0;
}

/// A provider category, by its id.
final class ProviderCategory extends CategorySelection {
  const ProviderCategory(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is ProviderCategory && other.id == id;

  @override
  int get hashCode => Object.hash(ProviderCategory, id);
}

/// One of my categories, by [FavouriteCategory.id].
final class MyCategory extends CategorySelection {
  const MyCategory(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is MyCategory && other.id == id;

  @override
  int get hashCode => Object.hash(MyCategory, id);
}
