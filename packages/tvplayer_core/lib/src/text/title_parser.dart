/// A provider's name for a movie, series or channel, split into its parts:
/// `"4K-TOP - Some Title (2023) (US)"` has the tag `4K-TOP`, the title
/// `Some Title`, the year 2023 and the country `US`.
///
/// Parsing is conservative: a leading tag is only removed when it looks
/// like a provider tag (2–10 characters of upper-case letters, digits and
/// `+ - . _ |`, with at least one letter, followed by `" - "`), and a
/// trailing year or country only when it is in parentheses at the very
/// end. Whatever doesn't match stays in [title]. Hand-written rather than
/// regular expressions: it runs for every item of catalogues with tens of
/// thousands of entries.
final class ParsedTitle {
  const ParsedTitle({
    required this.raw,
    required this.title,
    this.tag,
    this.year,
    this.country,
  });

  /// Splits [raw]. With [tag] false a leading tag is not looked for, e.g.
  /// when it was already removed.
  factory ParsedTitle.parse(String raw, {bool tag = true}) {
    var start = 0;
    var end = raw.length;
    while (start < end && _isSpace(raw.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(raw.codeUnitAt(end - 1))) {
      end--;
    }
    String? leading;
    final tagLength = tag ? _tagLength(raw, start, end) : 0;
    if (tagLength > 0) {
      leading = raw.substring(start, start + tagLength);
      start += tagLength + 3;
      while (start < end && _isSpace(raw.codeUnitAt(start))) {
        start++;
      }
    }
    int? year;
    String? country;
    // Year and country may come in either order: "(2023) (US)" or
    // "(US) (2023)".
    for (var round = 0; round < 2; round++) {
      final open = _trailingParens(raw, start, end);
      if (open < 0) break;
      final inside = end - open - 2;
      var newEnd = open;
      while (newEnd > start && _isSpace(raw.codeUnitAt(newEnd - 1))) {
        newEnd--;
      }
      if (newEnd == start) break;
      if (year == null && inside == 4 && _allDigits(raw, open + 1, end - 1)) {
        final y = int.parse(raw.substring(open + 1, end - 1));
        if (y < minYear || y > maxYear) break;
        year = y;
      } else if (country == null &&
          (inside == 2 || inside == 3) &&
          _allUpper(raw, open + 1, end - 1)) {
        country = raw.substring(open + 1, end - 1);
      } else {
        break;
      }
      end = newEnd;
    }
    return ParsedTitle(
      raw: raw,
      title: raw.substring(start, end),
      tag: leading,
      year: year,
      country: country,
    );
  }

  /// Years outside this range are not taken as a release year.
  static const minYear = 1888;
  static const maxYear = 2100;

  /// The name as the provider sent it.
  final String raw;

  /// The name without the leading tag and the trailing year and country.
  final String title;

  /// The provider's leading tag, e.g. `4K-TOP` or `EN`.
  final String? tag;

  /// The year from a trailing `(YYYY)`.
  final int? year;

  /// The country code from a trailing `(US)`.
  final String? country;

  /// [raw] without the leading tag; year and country are kept.
  String get withoutTag => withoutTagOf(raw);

  /// [name] without a leading provider tag (see [ParsedTitle]), trimmed.
  static String withoutTagOf(String name) {
    var start = 0;
    var end = name.length;
    while (start < end && _isSpace(name.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(name.codeUnitAt(end - 1))) {
      end--;
    }
    final tagLength = _tagLength(name, start, end);
    if (tagLength > 0) {
      start += tagLength + 3;
      while (start < end && _isSpace(name.codeUnitAt(start))) {
        start++;
      }
    }
    return start == 0 && end == name.length ? name : name.substring(start, end);
  }

  /// The leading tag of [name] and where the rest starts, or null.
  ///
  /// Strict (the default): the tag is followed by exactly `" - "`, as in
  /// [ParsedTitle.parse]. [loose] also accepts the separators providers
  /// get wrong now and then: extra spaces around the dash, no space after
  /// it (`"SC -Title"`) or a colon (`"TOP: Title"`). Only use that for
  /// tags known to be tags, since `"CSI: Vegas"` looks the same.
  static ({String tag, int rest})? leadingTag(
    String name, {
    bool loose = false,
  }) {
    var start = 0;
    var end = name.length;
    while (start < end && _isSpace(name.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(name.codeUnitAt(end - 1))) {
      end--;
    }
    final strict = _tagLength(name, start, end);
    if (strict > 0) {
      var rest = start + strict + 3;
      while (rest < end && _isSpace(name.codeUnitAt(rest))) {
        rest++;
      }
      return (tag: name.substring(start, start + strict), rest: rest);
    }
    if (!loose) return null;
    // The tag word, then spaces and "-", or ":".
    var i = start;
    var letters = false;
    while (i < end && i - start <= 10) {
      final c = name.codeUnitAt(i);
      if (c >= 0x41 && c <= 0x5a) {
        letters = true;
      } else if (!_isTagSymbol(c)) {
        break;
      }
      i++;
    }
    final length = i - start;
    if (!letters || length < 2 || length > 10) return null;
    var j = start + length;
    if (j < end && name.codeUnitAt(j) == 0x3a) {
      j++;
    } else {
      while (j < end && _isSpace(name.codeUnitAt(j))) {
        j++;
      }
      if (j >= end || name.codeUnitAt(j) != 0x2d) return null;
      j++;
    }
    while (j < end && _isSpace(name.codeUnitAt(j))) {
      j++;
    }
    if (j >= end) return null;
    return (tag: name.substring(start, start + length), rest: j);
  }

  /// Length of the provider tag at [start], or 0 when there is none: up to
  /// 10 tag characters with at least one letter, then `" - "` and more
  /// text.
  static int _tagLength(String s, int start, int end) {
    var letters = false;
    var i = start;
    while (i < end && i - start <= 10) {
      final c = s.codeUnitAt(i);
      if (c == 0x20) break;
      if (c >= 0x41 && c <= 0x5a) {
        letters = true;
      } else if (!_isTagSymbol(c)) {
        return 0;
      }
      i++;
    }
    final length = i - start;
    if (!letters || length < 2 || length > 10) return 0;
    // " - " and at least one character after it.
    if (i + 3 >= end ||
        s.codeUnitAt(i + 1) != 0x2d ||
        s.codeUnitAt(i + 2) != 0x20) {
      return 0;
    }
    return length;
  }

  /// Digits and `+ - . _ |`.
  static bool _isTagSymbol(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      c == 0x2b ||
      c == 0x2d ||
      c == 0x2e ||
      c == 0x5f ||
      c == 0x7c;

  /// Position of the `(` when [s] ends (at [end]) with `(…)` of 2–4
  /// characters; otherwise -1.
  static int _trailingParens(String s, int start, int end) {
    if (end - start < 4 || s.codeUnitAt(end - 1) != 0x29) return -1;
    for (var i = end - 2; i >= start && i >= end - 6; i--) {
      if (s.codeUnitAt(i) == 0x28) return i;
    }
    return -1;
  }

  static bool _allDigits(String s, int from, int to) {
    for (var i = from; i < to; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  static bool _allUpper(String s, int from, int to) {
    for (var i = from; i < to; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x41 || c > 0x5a) return false;
    }
    return true;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0xa0;

  @override
  String toString() => 'ParsedTitle($title, tag: $tag, year: $year)';
}
