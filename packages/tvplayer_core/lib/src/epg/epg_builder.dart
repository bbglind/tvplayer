import 'dart:io';

import '../models/epg_program.dart';
import '../xmltv/xmltv_parser.dart';
import 'channel_name.dart';
import 'epg_guide.dart';

/// Collects XMLTV channels and programmes into an [EpgGuide], keeping only
/// what the playlist can use.
///
/// A guide channel is kept when its id equals one of [epgIds] (ignoring
/// case), or one of its display names matches one of [names] after
/// [normalizeChannelName]. With both null, every channel is kept.
/// Programmes that ended before [keepFrom] are dropped.
class EpgGuideBuilder {
  EpgGuideBuilder({
    Iterable<String>? epgIds,
    Iterable<String>? names,
    this.keepFrom,
  }) : _keepAll = epgIds == null && names == null,
       _ids = {
         for (final id in epgIds ?? const <String>[]) id.trim().toLowerCase(),
       },
       _names = {
         for (final name in names ?? const <String>[])
           if (normalizeChannelName(name) case final n when n.isNotEmpty) n,
       };

  final DateTime? keepFrom;
  final bool _keepAll;
  final Set<String> _ids;
  final Set<String> _names;

  final _displayNames = <String, List<String>>{};
  final _programs = <String, List<EpgProgram>>{};
  final _wanted = <String, bool>{};

  void addChannel(XmltvChannel channel) {
    _displayNames[channel.id] = channel.displayNames;
  }

  void addProgram(EpgProgram program) {
    final keepFrom = this.keepFrom;
    if (keepFrom != null && !program.stop.isAfter(keepFrom)) return;
    if (!_wanted.putIfAbsent(
      program.channelId,
      () => _isWanted(program.channelId),
    )) {
      return;
    }
    (_programs[program.channelId] ??= []).add(program);
  }

  bool _isWanted(String id) {
    if (_keepAll || _ids.contains(id.trim().toLowerCase())) return true;
    for (final name in _displayNames[id] ?? const <String>[]) {
      if (_names.contains(normalizeChannelName(name))) return true;
    }
    return false;
  }

  EpgGuide build({required DateTime fetchedAt}) => EpgGuide(
    programs: _programs,
    displayNames: _displayNames,
    fetchedAt: fetchedAt,
  );
}

/// Parses an XMLTV document into an [EpgGuide]; see [EpgGuideBuilder] for
/// the filters.
Future<EpgGuide> buildGuideFromXmltv(
  Stream<List<int>> bytes, {
  required DateTime fetchedAt,
  Iterable<String>? epgIds,
  Iterable<String>? names,
  DateTime? keepFrom,
}) async {
  final builder = EpgGuideBuilder(
    epgIds: epgIds,
    names: names,
    keepFrom: keepFrom,
  );
  await const XmltvParser()
      .parseBytes(bytes, onChannel: builder.addChannel)
      .forEach(builder.addProgram);
  return builder.build(fetchedAt: fetchedAt);
}

/// [buildGuideFromXmltv] for a file on disk. Only takes and returns plain
/// data, so it can run in a background isolate (`Isolate.run`).
Future<EpgGuide> buildGuideFromXmltvFile(
  String path, {
  required DateTime fetchedAt,
  Iterable<String>? epgIds,
  Iterable<String>? names,
  DateTime? keepFrom,
}) => buildGuideFromXmltv(
  File(path).openRead(),
  fetchedAt: fetchedAt,
  epgIds: epgIds,
  names: names,
  keepFrom: keepFrom,
);
