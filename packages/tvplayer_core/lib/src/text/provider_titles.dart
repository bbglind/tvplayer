import '../models/episode.dart';
import '../models/series.dart';
import 'title_parser.dart';

/// A provider name as shown: the [title] without the provider's tag, year
/// and country, and the tag as a [label] (shown as-is, never translated).
final class DisplayTitle {
  const DisplayTitle({
    required this.raw,
    required this.title,
    this.label,
    this.year,
    this.country,
  });

  /// The name as the provider sent it.
  final String raw;
  final String title;
  final String? label;
  final int? year;
  final String? country;

  /// Whether something of [raw] is not in [title], so the full name is
  /// worth a tooltip.
  bool get shortened => title != raw.trim();

  @override
  String toString() => 'DisplayTitle($title, label: $label)';
}

/// The provider tags of one catalogue (`NF-DO`, `4K-SC`…), learned from
/// the names themselves, so that a title like `"CSI - Vegas"` keeps its
/// first word.
///
/// A tag-shaped prefix (see [ParsedTitle]) counts as a tag when
/// - at least [minShare] of all names have a tag-shaped prefix: a
///   catalogue without tags keeps every title whole, and
/// - it starts at least [minCount] names, or each of its `-` parts is part
///   of such a tag (`EN-DO` from `EN` and `NF-DO`).
///
/// Accepted tags are also removed when the provider got the separator
/// wrong (`"TOP: Title"`, `"SC -Title"`, `"EN  -  Title"`).
final class ProviderTags {
  ProviderTags._(this._tags, this._parts);

  factory ProviderTags.fromNames(
    Iterable<String> names, {
    double minShare = 0.2,
    int minCount = 3,
  }) {
    final counts = <String, int>{};
    var total = 0;
    var tagged = 0;
    for (final name in names) {
      total++;
      final tag = ParsedTitle.leadingTag(name)?.tag;
      if (tag == null) continue;
      tagged++;
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
    if (total == 0 || tagged < total * minShare) return empty;
    final tags = {
      for (final MapEntry(:key, :value) in counts.entries)
        if (value >= minCount) key,
    };
    return ProviderTags._(tags, {for (final t in tags) ...t.split('-')});
  }

  /// Knows no tags: names are shown whole (apart from year and country).
  static final empty = ProviderTags._(const {}, const {});

  final Set<String> _tags;
  final Set<String> _parts;

  bool get isEmpty => _tags.isEmpty;

  /// Whether [tag] is one of this catalogue's tags.
  bool accepts(String tag) =>
      _tags.contains(tag) ||
      (_parts.isNotEmpty && tag.split('-').every(_parts.contains));

  /// [name] split into its parts, without the tag only when it is one of
  /// this catalogue's.
  DisplayTitle display(String name) {
    final lead = _accepted(name);
    final rest = lead == null ? name : name.substring(lead.rest);
    final parsed = ParsedTitle.parse(rest, tag: false);
    return DisplayTitle(
      raw: name,
      title: parsed.title,
      label: lead?.tag,
      year: parsed.year,
      country: parsed.country,
    );
  }

  ({String tag, int rest})? _accepted(String name) {
    if (_tags.isEmpty) return null;
    final lead = ParsedTitle.leadingTag(name, loose: true);
    return lead != null && accepts(lead.tag) ? lead : null;
  }

  /// [name] without an accepted tag; year and country are kept.
  String withoutTag(String name) {
    final lead = _accepted(name);
    return lead == null ? name.trim() : name.substring(lead.rest).trim();
  }
}

final _episodeCode = RegExp(r'\bS\d{1,3}\s?E\d{1,4}\b', caseSensitive: false);

/// Characters around the parts of an episode title.
final _leadingSeparators = RegExp(r'^[\s\-–—:·.|_]+');
final _trailingSeparators = RegExp(r'[\s\-–—:·|_]+$');

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Year and country groups right at the start, e.g. `(2025) (GB)`.
final _leadingParens = RegExp(r'^(\s*\((\d{4}|[A-Z]{2,3})\))+');

/// The own name of [episode], without the series name and episode code
/// providers put in front: `"NF-DO - Show (2025) (GB) - S01E01 - Pilot"`
/// becomes `"Pilot"`. [title] replaces the episode's title, e.g. one from
/// a metadata source. Without a name of its own: `"Episode 3"`.
String episodeDisplayTitle(
  Series series,
  Episode episode,
  ProviderTags tags, {
  String? title,
}) {
  final seriesTitle = tags.display(series.name).title.toLowerCase();
  String stripSeries(String text) {
    var t = tags.withoutTag(text);
    // The series name as a whole word: "Show" isn't cut from "Showdown".
    if (seriesTitle.isNotEmpty &&
        t.toLowerCase().startsWith(seriesTitle) &&
        (t.length == seriesTitle.length ||
            !_wordChar.hasMatch(t[seriesTitle.length]))) {
      t = t.substring(seriesTitle.length).replaceFirst(_leadingParens, '');
    }
    return t
        .replaceFirst(_leadingSeparators, '')
        .replaceFirst(_trailingSeparators, '');
  }

  final full = (title ?? episode.title).trim();
  final codes = _episodeCode.allMatches(full).toList();
  var name = '';
  if (codes.isNotEmpty) {
    name = stripSeries(full.substring(codes.last.end));
    // "Show - Pilot - S01E01": the name comes before the code.
    if (name.isEmpty) name = stripSeries(full.substring(0, codes.first.start));
  } else {
    name = stripSeries(full);
  }
  if (name.isEmpty || name.toLowerCase() == seriesTitle) {
    return 'Episode ${episode.episodeNumber}';
  }
  return name;
}
