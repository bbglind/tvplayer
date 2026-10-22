import 'dart:convert';

import 'package:xml/xml.dart' show XmlException;
import 'package:xml/xml_events.dart';

import '../models/epg_program.dart';

/// A `<channel>` element of an XMLTV guide.
final class XmltvChannel {
  const XmltvChannel({required this.id, this.displayNames = const []});

  final String id;

  /// All `<display-name>`s, in document order.
  final List<String> displayNames;

  @override
  String toString() => 'XmltvChannel($id, $displayNames)';
}

/// Streaming parser for XMLTV guides (e.g. Xtream `xmltv.php`).
///
/// The document is processed as a stream of XML events and programmes are
/// emitted one at a time, so very large guides never need to be held in
/// memory. Programmes with a missing channel, title or unparsable start/stop
/// time are skipped. If the XML itself is cut off or malformed, the
/// programmes parsed up to that point are emitted and the stream ends.
class XmltvParser {
  /// When [channelIds] is given, only programmes for those channels are
  /// emitted.
  const XmltvParser({this.channelIds});

  final Set<String>? channelIds;

  /// Parses an XMLTV document from raw bytes (decoded as UTF-8).
  ///
  /// [onChannel] is called for every `<channel>` element (not filtered by
  /// [channelIds]); in XMLTV these come before the programmes.
  Stream<EpgProgram> parseBytes(
    Stream<List<int>> bytes, {
    void Function(XmltvChannel channel)? onChannel,
  }) => parseChunks(
    bytes.transform(const Utf8Decoder(allowMalformed: true)),
    onChannel: onChannel,
  );

  /// Parses an XMLTV document from a stream of text chunks.
  Stream<EpgProgram> parseChunks(
    Stream<String> chunks, {
    void Function(XmltvChannel channel)? onChannel,
  }) async* {
    final state = _XmltvState(channelIds, onChannel);
    try {
      await for (final events in chunks.toXmlEvents()) {
        for (final event in events) {
          final program = state.add(event);
          if (program != null) yield program;
        }
      }
    } on XmlException {
      // Truncated or malformed document: keep what was parsed so far.
    }
  }

  /// Parses an XMLTV document held in memory.
  Stream<EpgProgram> parseString(
    String xml, {
    void Function(XmltvChannel channel)? onChannel,
  }) => parseChunks(Stream.value(xml), onChannel: onChannel);

  static final _timePattern = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?'
    r'\s*(?:(Z|UTC|GMT)|([+-])(\d{2}):?(\d{2}))?$',
    caseSensitive: false,
  );

  /// Parses an XMLTV timestamp such as `20240101123000 +0100` into UTC.
  /// Missing time parts default to zero and a missing offset means UTC.
  /// Returns null for malformed or out-of-range values.
  static DateTime? parseTime(String? value) {
    if (value == null) return null;
    final m = _timePattern.firstMatch(value.trim());
    if (m == null) return null;
    int part(int group) => int.parse(m.group(group) ?? '0');
    final year = part(1), month = part(2), day = part(3);
    final hour = part(4), minute = part(5), second = part(6);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59 || second > 59) return null;
    final local = DateTime.utc(year, month, day, hour, minute, second);
    if (local.day != day) return null; // e.g. 31 February
    if (m.group(8) == null) return local;
    final offsetHours = part(9), offsetMinutes = part(10);
    if (offsetHours > 14 || offsetMinutes > 59) return null;
    final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
    return m.group(8) == '-' ? local.add(offset) : local.subtract(offset);
  }
}

/// Collects the parts of one `<programme>` (or `<channel>`) element from XML
/// events.
class _XmltvState {
  _XmltvState(this._channelIds, this._onChannel);

  final Set<String>? _channelIds;
  final void Function(XmltvChannel channel)? _onChannel;

  /// Id of the open `<channel>`, when one is open and [_onChannel] is set.
  String? _channelElementId;
  final _displayNames = <String>[];
  bool _inDisplayName = false;

  bool _inProgramme = false;
  String? _channel;
  String? _start;
  String? _stop;
  final _fields = <String, String>{};

  /// Nesting depth below `<programme>`; 1 means a direct child.
  int _depth = 0;
  String? _capturing;
  final _text = StringBuffer();

  static const _capturedFields = {'title', 'desc', 'category'};

  EpgProgram? add(XmlEvent event) {
    switch (event) {
      case XmlStartElementEvent(name: 'programme'):
        // A new programme while one is open means broken nesting: drop the
        // unfinished one.
        _channelElementId = null;
        _begin(event);
        return event.isSelfClosing ? _finish() : null;
      case XmlStartElementEvent(name: 'channel') when _onChannel != null:
        _channelElementId = null;
        _displayNames.clear();
        _inDisplayName = false;
        for (final attribute in event.attributes) {
          if (attribute.name == 'id') {
            _channelElementId = attribute.value.trim();
          }
        }
        if (event.isSelfClosing) _finishChannel();
      case XmlStartElementEvent(name: 'display-name')
          when _channelElementId != null && !event.isSelfClosing:
        _inDisplayName = true;
        _text.clear();
      case XmlTextEvent() when _inDisplayName:
        _text.write(event.value);
      case XmlCDATAEvent() when _inDisplayName:
        _text.write(event.value);
      case XmlEndElementEvent(name: 'display-name') when _inDisplayName:
        _inDisplayName = false;
        final name = _text.toString().trim();
        if (name.isNotEmpty) _displayNames.add(name);
      case XmlEndElementEvent(name: 'channel') when _channelElementId != null:
        _finishChannel();
      case XmlStartElementEvent() when _inProgramme:
        if (event.isSelfClosing) return null;
        _depth++;
        if (_depth == 1 &&
            _capturedFields.contains(event.name) &&
            !_fields.containsKey(event.name)) {
          _capturing = event.name;
          _text.clear();
        }
      case XmlTextEvent() when _capturing != null:
        _text.write(event.value);
      case XmlCDATAEvent() when _capturing != null:
        _text.write(event.value);
      case XmlEndElementEvent(name: 'programme') when _inProgramme:
        return _finish();
      case XmlEndElementEvent() when _inProgramme:
        if (_depth == 1 && _capturing == event.name) {
          final value = _text.toString().trim();
          if (value.isNotEmpty) _fields[event.name] = value;
          _capturing = null;
        }
        if (_depth > 0) _depth--;
      default:
        break;
    }
    return null;
  }

  void _finishChannel() {
    final id = _channelElementId;
    _channelElementId = null;
    _inDisplayName = false;
    if (id == null || id.isEmpty) return;
    _onChannel?.call(
      XmltvChannel(id: id, displayNames: List.unmodifiable(_displayNames)),
    );
  }

  void _begin(XmlStartElementEvent event) {
    _inProgramme = true;
    _depth = 0;
    _capturing = null;
    _fields.clear();
    _channel = _start = _stop = null;
    for (final attribute in event.attributes) {
      switch (attribute.name) {
        case 'channel':
          _channel = attribute.value.trim();
        case 'start':
          _start = attribute.value;
        case 'stop':
          _stop = attribute.value;
      }
    }
  }

  EpgProgram? _finish() {
    _inProgramme = false;
    _capturing = null;
    final channel = _channel;
    final title = _fields['title'];
    if (channel == null || channel.isEmpty || title == null) return null;
    if (_channelIds != null && !_channelIds.contains(channel)) return null;
    final start = XmltvParser.parseTime(_start);
    final stop = XmltvParser.parseTime(_stop);
    if (start == null || stop == null || stop.isBefore(start)) return null;
    return EpgProgram(
      channelId: channel,
      title: title,
      description: _fields['desc'],
      category: _fields['category'],
      start: start,
      stop: stop,
    );
  }
}
