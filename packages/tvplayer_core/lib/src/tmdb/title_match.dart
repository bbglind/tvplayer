import '../text/provider_titles.dart';
import '../text/search_text.dart';
import 'tmdb_models.dart';

/// A provider title without a TMDB id, to be found by searching TMDB for
/// its [title] (without the provider's tag) and [year].
final class TitleSearch {
  const TitleSearch(this.kind, this.key, this.title, this.year);

  /// The search for a provider [name] in [kind]; null when nothing is left
  /// of the name once the tag is removed.
  static TitleSearch? of(
    TmdbKind kind,
    String name,
    ProviderTags tags, {
    int? year,
  }) {
    final display = tags.display(name);
    final key = titleKey(display.title, year ?? display.year);
    if (key == null) return null;
    return TitleSearch(kind, key, display.title, year ?? display.year);
  }

  final TmdbKind kind;

  /// What the outcome is stored under (see [titleKey]).
  final String key;
  final String title;
  final int? year;

  @override
  bool operator ==(Object other) =>
      other is TitleSearch && other.kind == kind && other.key == key;

  @override
  int get hashCode => Object.hash(kind, key);
}

/// The key a title search is stored under: the normalised title and the
/// year. Keyed by text, not by provider ids, so variants share it and it
/// survives a change of provider. Null for an empty title.
String? titleKey(String title, int? year) {
  final normalized = normalizeForSearch(title).trim();
  if (normalized.isEmpty) return null;
  return '$normalized|${year ?? ''}';
}

/// The result of a search for [title] ([year]) that is surely the same
/// work, or null. A result must have the same title (or original title)
/// once normalised and, when [year] is known, a year at most one off. When
/// several fit, only one with the exact year is taken: better no match than
/// a wrong one.
TmdbSearchResult? pickMatch(
  String title,
  int? year,
  List<TmdbSearchResult> results,
) {
  final wanted = normalizeForSearch(title).trim();
  if (wanted.isEmpty) return null;
  bool sameTitle(String? t) =>
      t != null && normalizeForSearch(t).trim() == wanted;
  final fits = [
    for (final r in results)
      if (sameTitle(r.title) || sameTitle(r.originalTitle))
        if (year == null || (r.year != null && (r.year! - year).abs() <= 1)) r,
  ];
  if (fits.length == 1) return fits.single;
  if (year == null) return null;
  final exact = fits.where((r) => r.year == year).toList();
  return exact.length == 1 ? exact.single : null;
}
