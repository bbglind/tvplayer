import '../util/json.dart';

/// A live, VOD or series category.
final class Category {
  const Category({required this.id, required this.name, this.parentId});

  /// Parses a category object; returns null when the id is missing.
  static Category? fromJson(Map<String, Object?> json) {
    final id = readString(json['category_id']);
    if (id == null) return null;
    return Category(
      id: id,
      name: readString(json['category_name']) ?? '',
      parentId: readString(json['parent_id']),
    );
  }

  final String id;
  final String name;
  final String? parentId;

  @override
  String toString() => 'Category($id, $name)';
}
