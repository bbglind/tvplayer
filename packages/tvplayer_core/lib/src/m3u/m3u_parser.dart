import 'dart:convert';

import '../models/m3u_entry.dart';

/// Parser for M3U/M3U8 playlists with `#EXTINF` metadata.
///
/// Works line by line, so large playlists can be streamed without holding
/// them in memory. Malformed lines are tolerated: unknown directives are
/// ignored, a missing `#EXTM3U` header is accepted, and a URL without a
/// preceding `#EXTINF` still yields an entry.
class M3uParser {
  const M3uParser();

  /// Parses a playlist from raw bytes (decoded as UTF-8).
  Stream<M3uEntry> parseBytes(Stream<List<int>> bytes) => parseLines(
    bytes
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter()),
  );

  /// Parses a playlist from a stream of lines.
  Stream<M3uEntry> parseLines(Stream<String> lines) async* {
    final state = _M3uState();
    await for (final line in lines) {
      final entry = state.add(line);
      if (entry != null) yield entry;
    }
  }

  /// Parses a playlist held in memory.
  Iterable<M3uEntry> parseString(String playlist) =>
      parseIterable(const LineSplitter().convert(playlist));

  /// Parses a playlist from an iterable of lines, lazily.
  Iterable<M3uEntry> parseIterable(Iterable<String> lines) sync* {
    final state = _M3uState();
    for (final line in lines) {
      final entry = state.add(line);
      if (entry != null) yield entry;
    }
  }
}

/// Accumulates directive lines until the URL line that completes an entry.
class _M3uState {
  _ExtInf? _pending;
  String? _group;
  bool _first = true;

  M3uEntry? add(String rawLine) {
    var line = rawLine;
    if (_first) {
      _first = false;
      if (line.startsWith('﻿')) line = line.substring(1);
    }
    line = line.trim();
    if (line.isEmpty) return null;

    if (line.startsWith('#')) {
      final upper = line.toUpperCase();
      if (upper.startsWith('#EXTINF')) {
        // A second #EXTINF without URL in between replaces the first.
        _pending = _ExtInf.parse(line);
        _group = null;
      } else if (upper.startsWith('#EXTGRP:')) {
        _group = line.substring('#EXTGRP:'.length).trim();
      }
      // #EXTM3U, #EXTVLCOPT, #KODIPROP and comments are ignored.
      return null;
    }

    final info = _pending;
    _pending = null;
    final group = _group;
    _group = null;
    final attributes = info?.attributes ?? const <String, String>{};
    String? attr(String key) {
      final value = attributes[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final groupTitle = attr('group-title') ?? _nonEmpty(group);
    final name =
        _nonEmpty(info?.name) ?? attr('tvg-name') ?? _nameFromUrl(line);
    return M3uEntry(
      name: name,
      url: line,
      tvgId: attr('tvg-id'),
      tvgName: attr('tvg-name'),
      tvgLogo: attr('tvg-logo'),
      groupTitle: groupTitle,
      duration: info?.duration,
      attributes: Map.unmodifiable(attributes),
    );
  }

  static String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;

  static String _nameFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    final last = segments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    return last.isEmpty ? 'Unknown' : last;
  }
}

/// The parsed contents of an `#EXTINF` line.
class _ExtInf {
  _ExtInf(this.duration, this.attributes, this.name);

  final int? duration;
  final Map<String, String> attributes;
  final String name;

  static final _durationPattern = RegExp(r'^\s*(-?\d+(?:\.\d+)?)');
  static final _attributePattern = RegExp(
    r'''([A-Za-z0-9_:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s",]+))''',
  );

  static _ExtInf parse(String line) {
    final colon = line.indexOf(':');
    var rest = colon < 0 ? '' : line.substring(colon + 1);

    int? duration;
    final durationMatch = _durationPattern.firstMatch(rest);
    if (durationMatch != null) {
      duration = double.tryParse(durationMatch.group(1)!)?.toInt();
      rest = rest.substring(durationMatch.end);
    }

    // The display name follows the first comma outside quotes. Attribute
    // values (e.g. tvg-name) may themselves contain commas.
    final comma = _firstUnquotedComma(rest);
    final attributePart = comma < 0 ? rest : rest.substring(0, comma);
    var name = comma < 0 ? '' : rest.substring(comma + 1).trim();
    if (comma < 0) {
      // Unbalanced quotes or no comma at all: fall back to the text after
      // the last comma, if any.
      final last = rest.lastIndexOf(',');
      if (last >= 0) name = rest.substring(last + 1).trim();
    }

    final attributes = <String, String>{};
    for (final m in _attributePattern.allMatches(attributePart)) {
      attributes[m.group(1)!.toLowerCase()] =
          (m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
    }
    return _ExtInf(duration, attributes, name);
  }

  static int _firstUnquotedComma(String s) {
    var inQuotes = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        return i;
      }
    }
    return -1;
  }
}
