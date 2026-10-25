import 'dart:typed_data';

import 'title_parser.dart';

/// Accented letters by the plain letters they fold to.
const _foldTable = {
  'a': 'àáâãäåāăąǎÀÁÂÃÄÅĀĂĄǍ',
  'c': 'çćĉċčÇĆĈĊČ',
  'd': 'ďđĎĐ',
  'e': 'èéêëēĕėęěÈÉÊËĒĔĖĘĚ',
  'g': 'ĝğġģĜĞĠĢ',
  'h': 'ĥħĤĦ',
  'i': 'ìíîïĩīĭįıǐÌÍÎÏĨĪĬĮİǏ',
  'j': 'ĵĴ',
  'k': 'ķĶ',
  'l': 'ĺļľŀłĹĻĽĿŁ',
  'n': 'ñńņňŉÑŃŅŇ',
  'o': 'òóôõöøōŏőǒÒÓÔÕÖØŌŎŐǑ',
  'r': 'ŕŗřŔŖŘ',
  's': 'śŝşšșŚŜŞŠȘ',
  't': 'ţťŧțŢŤŦȚ',
  'u': 'ùúûüũūŭůűųǔÙÚÛÜŨŪŬŮŰŲǓ',
  'w': 'ŵŴ',
  'y': 'ýÿŷÝŸŶ',
  'z': 'źżžŹŻŽ',
  'ss': 'ß',
  'ae': 'æÆ',
  'oe': 'œŒ',
  'th': 'þÞ',
  'dh': 'ðÐ',
};

/// Below this code unit, normalisation uses [_table].
const _tableSize = 0x250;

const _separator = -1;
const _multiple = -2;

/// What each code unit below [_tableSize] becomes: its folded lower-case
/// form, [_separator], or [_multiple] when it folds to several letters
/// (see [_multi]).
final Int32List _table = () {
  final table = Int32List(_tableSize)..fillRange(0, _tableSize, _separator);
  for (var c = 0x30; c <= 0x39; c++) {
    table[c] = c;
  }
  for (var c = 0x41; c <= 0x5a; c++) {
    table[c] = c + 0x20;
  }
  for (var c = 0x61; c <= 0x7a; c++) {
    table[c] = c;
  }
  // Other Latin letters without a fold below keep their lower-case form.
  for (var c = 0xc0; c < _tableSize; c++) {
    if (c == 0xd7 || c == 0xf7) continue;
    final lower = String.fromCharCode(c).toLowerCase();
    if (lower.length == 1) table[c] = lower.codeUnitAt(0);
  }
  for (final MapEntry(:key, :value) in _foldTable.entries) {
    for (final c in value.codeUnits) {
      table[c] = key.length == 1 ? key.codeUnitAt(0) : _multiple;
    }
  }
  return table;
}();

/// Code units that fold to several letters, e.g. `ß` to `ss`.
final Map<int, List<int>> _multi = {
  for (final MapEntry(:key, :value) in _foldTable.entries)
    if (key.length > 1)
      for (final c in value.codeUnits) c: key.codeUnits,
};

/// A growable buffer of UTF-16 code units.
final class _Units {
  _Units([int capacity = 64]) : data = Uint16List(capacity);

  Uint16List data;
  int length = 0;

  void add(int unit) {
    if (length == data.length) {
      data = Uint16List(data.length * 2)..setRange(0, length, data);
    }
    data[length++] = unit;
  }

  /// Appends [text] normalised (see [normalizeForSearch]).
  void addNormalized(String text) {
    final start = length;
    var pendingSpace = false;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      int folded;
      if (c < _tableSize) {
        folded = _table[c];
      } else if (c >= 0x300 && c <= 0x36f) {
        // Combining marks (decomposed accents) are dropped.
        continue;
      } else if (_isOtherLetter(c)) {
        final lower = String.fromCharCode(c).toLowerCase();
        folded = lower.length == 1 ? lower.codeUnitAt(0) : c;
      } else {
        folded = _separator;
      }
      if (folded == _separator) {
        pendingSpace = length > start;
        continue;
      }
      if (pendingSpace) add(0x20);
      pendingSpace = false;
      if (folded == _multiple) {
        _multi[c]!.forEach(add);
      } else {
        add(folded);
      }
    }
  }

  @override
  String toString() => String.fromCharCodes(data, 0, length);
}

/// Lower-cases [text], folds diacritics (`é` → `e`, `ß` → `ss`) and turns
/// every run of other characters than letters and digits into one space.
String normalizeForSearch(String text) =>
    (_Units(text.length + 8)..addNormalized(text)).toString();

/// Letters of other scripts (Greek, Cyrillic, Arabic, CJK…); punctuation,
/// symbols and emoji (surrogates) are separators.
bool _isOtherLetter(int c) =>
    (c >= 0x370 && c < 0x2000) || (c >= 0x3040 && c < 0xd800);

/// A name prepared for matching: normalised (see [normalizeForSearch])
/// without the provider tag, once with and once without spaces.
final class SearchKey {
  factory SearchKey(String name) =>
      SearchKey._fromText(normalizeForSearch(ParsedTitle.withoutTagOf(name)));

  SearchKey._fromText(this.text) : compact = text.replaceAll(' ', '');

  final String text;
  final String compact;
}

/// What the user typed, prepared for matching against [SearchKey]s:
/// case- and diacritics-insensitive, and also with spaces removed, so
/// "svt1" finds "SVT 1".
final class SearchQuery {
  factory SearchQuery(String input) {
    final text = normalizeForSearch(input);
    final words = text.isEmpty ? const <String>[] : text.split(' ');
    return SearchQuery._(text, words, text.replaceAll(' ', ''));
  }

  const SearchQuery._(this.text, this.words, this.compact);

  /// The normalised query.
  final String text;

  /// Its words.
  final List<String> words;

  /// [text] without spaces.
  final String compact;

  /// True when nothing searchable was typed; it matches everything.
  bool get isEmpty => text.isEmpty;

  /// Whether [key] contains every word of the query, or the query without
  /// spaces.
  bool matches(SearchKey key) => _matches(key.text, key.compact);

  bool _matches(String text, String compact) {
    if (isEmpty || compact.contains(this.compact)) return true;
    if (words.length < 2) return false;
    for (final word in words) {
      if (!text.contains(word)) return false;
    }
    return true;
  }

  /// How well [key] matches, lower is better (see [SearchIndex.ranked]);
  /// null when it doesn't match.
  int? rank(SearchKey key) => matches(key) ? _rank(key.text) : null;

  int _rank(String t) {
    if (isEmpty) return 3;
    if (t == text) return 0;
    if (t.startsWith(text)) return 1;
    if (t.contains(' $text')) return 2;
    return 3;
  }
}

/// Search keys and title years for a list of names, by position.
///
/// The keys are kept as two long code-unit arrays (with and without
/// spaces, one name per line), scanned directly for each query instead of
/// checking name by name: fast enough to run on every key press for
/// catalogues with tens of thousands of names. It holds only typed lists,
/// so it can be built in a background isolate and passed back cheaply.
final class SearchIndex {
  factory SearchIndex(List<String> names) {
    final text = _Units(names.length * 40 + 16);
    final compact = _Units(names.length * 36 + 16);
    final textStarts = Int32List(names.length + 1);
    final compactStarts = Int32List(names.length + 1);
    final years = Uint16List(names.length);
    for (final (i, name) in names.indexed) {
      final parsed = ParsedTitle.parse(name);
      years[i] = parsed.year ?? 0;
      textStarts[i] = text.length;
      compactStarts[i] = compact.length;
      final from = text.length;
      text.addNormalized(parsed.withoutTag);
      for (var j = from; j < text.length; j++) {
        if (text.data[j] != 0x20) compact.add(text.data[j]);
      }
      text.add(_newline);
      compact.add(_newline);
    }
    textStarts[names.length] = text.length;
    compactStarts[names.length] = compact.length;
    return SearchIndex._(
      text.data.sublist(0, text.length),
      textStarts,
      compact.data.sublist(0, compact.length),
      compactStarts,
      years,
    );
  }

  SearchIndex._(
    this._text,
    this._textStarts,
    this._compact,
    this._compactStarts,
    this._years,
  );

  static const _newline = 0x0a;

  final Uint16List _text;
  final Int32List _textStarts;
  final Uint16List _compact;
  final Int32List _compactStarts;
  final Uint16List _years;

  /// Number of names.
  int get length => _years.length;

  /// The key of the name at [index].
  SearchKey operator [](int index) => SearchKey._fromText(sortKey(index));

  /// The normalised name at [index] without its tag: for sorting by name.
  String sortKey(int index) => String.fromCharCodes(
    _text,
    _textStarts[index],
    _textStarts[index + 1] - 1,
  );

  /// The year in the name at [index] (`"Title (2020)"`), if any.
  int? titleYear(int index) {
    final y = _years[index];
    return y == 0 ? null : y;
  }

  /// One flag per name: 1 when it matches [query]. All match an empty
  /// query.
  Uint8List matching(SearchQuery query) {
    final hits = Uint8List(length);
    if (query.isEmpty) return hits..fillRange(0, length, 1);
    // Every name containing the query without spaces. For one word that
    // is all of them: a word in a key is also in the key without spaces.
    _scan(_compact, _compactStarts, query.compact.codeUnits, (i) {
      hits[i] = 1;
    });
    if (query.words.length > 1) {
      // Names containing every word: count, per name, the words found so
      // far in order; a name matches when all were found.
      final found = Uint8List(length);
      for (final (n, word) in query.words.indexed) {
        _scan(_text, _textStarts, word.codeUnits, (i) {
          if (found[i] == n) found[i] = n + 1;
        });
      }
      final all = query.words.length;
      for (var i = 0; i < length; i++) {
        if (found[i] == all) hits[i] = 1;
      }
    }
    return hits;
  }

  /// Calls [found] once for each line (by index) of [all] that contains
  /// [needle].
  static void _scan(
    Uint16List all,
    Int32List starts,
    List<int> needle,
    void Function(int index) found,
  ) {
    final n = needle.length;
    if (n == 0) return;
    final first = needle[0];
    final last = all.length - n;
    var line = 0;
    var pos = 0;
    while (pos <= last) {
      if (all[pos] != first) {
        pos++;
        continue;
      }
      var j = 1;
      while (j < n && all[pos + j] == needle[j]) {
        j++;
      }
      if (j < n) {
        pos++;
        continue;
      }
      while (starts[line + 1] <= pos) {
        line++;
      }
      found(line);
      // Go on after this line: each is reported once.
      pos = starts[line + 1];
    }
  }

  /// Positions in [within] (all when null) matching [query], best match
  /// first: the whole name (0), then names starting with the query (1),
  /// then names with a word starting with it (2), then the rest (3).
  /// Equally good matches keep their order.
  List<int> ranked(SearchQuery query, {Iterable<int>? within}) {
    final hits = matching(query);
    final buckets = List.generate(4, (_) => <int>[]);
    for (final i in within ?? Iterable<int>.generate(length)) {
      if (hits[i] == 1) buckets[query._rank(sortKey(i))].add(i);
    }
    return [for (final b in buckets) ...b];
  }
}
