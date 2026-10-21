// Lenient readers for JSON values as returned by real-world Xtream panels,
// which mix numbers and strings freely and often send null, "" or the wrong
// container type for missing data.
import 'dart:convert';

/// Reads an int from an int, double or numeric string; null otherwise.
int? readInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
  return null;
}

/// Reads a double from a number or numeric string; null otherwise.
double? readDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final s = value.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
  return null;
}

/// Reads a non-empty, trimmed string. Numbers are converted to strings.
String? readString(Object? value) {
  if (value is String) {
    final s = value.trim();
    return s.isEmpty ? null : s;
  }
  if (value is num || value is bool) return value.toString();
  return null;
}

/// Reads a boolean from bool, 0/1, "0"/"1" or "true"/"false".
bool readBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final s = value.trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }
  return false;
}

/// Reads a UTC [DateTime] from a Unix timestamp in seconds (int or string).
DateTime? readEpochSeconds(Object? value) {
  final seconds = readInt(value);
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// Reads a JSON object; anything else yields null.
Map<String, Object?>? readMap(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

/// Reads a JSON array. Panels sometimes send an object keyed by index
/// instead, in which case its values are used.
List<Object?> readList(Object? value) {
  if (value is List) return value.cast<Object?>();
  if (value is Map) return value.values.cast<Object?>().toList();
  return const [];
}

/// Reads a list of non-empty strings from an array or a single string.
List<String> readStringList(Object? value) {
  if (value is String) {
    final s = readString(value);
    return s == null ? const [] : [s];
  }
  return readList(value).map(readString).whereType<String>().toList();
}

final _base64Pattern = RegExp(r'^[A-Za-z0-9+/\s]+={0,2}$');

/// Decodes a base64 encoded UTF-8 string as used for Xtream EPG titles and
/// descriptions. Values that are not valid base64 or don't decode to valid
/// UTF-8 text are returned unchanged (trimmed), since some panels send plain
/// text.
String? readMaybeBase64(Object? value) {
  final s = readString(value);
  if (s == null) return null;
  if (!_base64Pattern.hasMatch(s)) return s;
  try {
    final compact = s.replaceAll(RegExp(r'\s'), '');
    final decoded = utf8.decode(base64.decode(base64.normalize(compact)));
    // Reject decodings that produce control characters: most likely the
    // input was plain text that merely looked like base64.
    if (decoded.runes.any(
      (r) => r < 0x20 && r != 0x0a && r != 0x0d && r != 0x09,
    )) {
      return s;
    }
    final trimmed = decoded.trim();
    return trimmed.isEmpty ? null : trimmed;
  } on FormatException {
    return s;
  }
}
