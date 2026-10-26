import '../live/live_source.dart';
import '../models/epg_program.dart';
import 'channel_name.dart';

/// The programme airing at a moment and the one after it.
typedef NowNext = ({EpgProgram? now, EpgProgram? next});

/// A parsed TV guide: programmes per guide channel, sorted by start time and
/// without overlaps. All times are UTC.
///
/// Playlist channels are matched to guide channels by their EPG channel id
/// (exactly, then ignoring case and surrounding spaces) and, when that finds
/// nothing, by name (see [normalizeChannelName]) against the guide's display
/// names. A name that fits more than one guide channel matches none.
final class EpgGuide {
  /// [programs] maps a guide channel id to its programmes in any order;
  /// [displayNames] maps a guide channel id to its names.
  EpgGuide({
    required Map<String, List<EpgProgram>> programs,
    Map<String, List<String>> displayNames = const {},
    required this.fetchedAt,
  }) : _programs = {
         for (final MapEntry(:key, :value) in programs.entries)
           if (_tidy(value) case final list when list.isNotEmpty) key: list,
       },
       _displayNames = {
         for (final MapEntry(:key, :value) in displayNames.entries)
           if (programs.containsKey(key)) key: List.unmodifiable(value),
       } {
    for (final id in _programs.keys) {
      _byLowerId.putIfAbsent(_lowerId(id), () => id);
    }
    final byName = <String, Set<String>>{};
    for (final MapEntry(:key, :value) in _displayNames.entries) {
      if (!_programs.containsKey(key)) continue;
      for (final name in value) {
        final n = normalizeChannelName(name);
        if (n.isNotEmpty) (byName[n] ??= {}).add(key);
      }
    }
    for (final MapEntry(:key, :value) in byName.entries) {
      if (value.length == 1) _byName[key] = value.single;
    }
  }

  /// An empty guide.
  EpgGuide.empty({required DateTime fetchedAt})
    : this(programs: const {}, fetchedAt: fetchedAt);

  /// When the guide was downloaded (UTC).
  final DateTime fetchedAt;

  final Map<String, List<EpgProgram>> _programs;
  final Map<String, List<String>> _displayNames;
  final Map<String, String> _byLowerId = {};
  final Map<String, String> _byName = {};
  final Map<(String?, String?), String?> _resolved = {};

  static String _lowerId(String id) => id.trim().toLowerCase();

  /// Sorts by start, drops duplicates and cuts overlaps short.
  static List<EpgProgram> _tidy(List<EpgProgram> programs) {
    final sorted = [...programs]..sort((a, b) => a.start.compareTo(b.start));
    final result = <EpgProgram>[];
    for (final p in sorted) {
      if (result.isNotEmpty) {
        final last = result.last;
        if (!p.start.isAfter(last.start)) continue; // Same start: keep first.
        if (p.start.isBefore(last.stop)) {
          result.last = last.copyWith(stop: p.start);
        }
      }
      result.add(p);
    }
    return List.unmodifiable(result);
  }

  /// Guide channel ids that have programmes.
  Iterable<String> get channelIds => _programs.keys;

  /// Display names of guide channel [id].
  List<String> displayNamesOf(String id) => _displayNames[id] ?? const [];

  bool get isEmpty => _programs.isEmpty;

  /// Number of programmes over all channels.
  int get programCount =>
      _programs.values.fold(0, (sum, list) => sum + list.length);

  /// End of the last programme, or null for an empty guide.
  DateTime? get end {
    DateTime? result;
    for (final list in _programs.values) {
      final stop = list.last.stop;
      if (result == null || stop.isAfter(result)) result = stop;
    }
    return result;
  }

  /// Whether the guide as a whole reaches [time]: at least half of its
  /// channels have programmes ending after it. False for an empty guide.
  bool reaches(DateTime time) {
    final ends = _ends ??= [for (final list in _programs.values) list.last.stop]
      ..sort();
    if (ends.isEmpty) return false;
    // Sorted, so the ends from this index on are the later half (rounded up).
    return ends[ends.length ~/ 2].isAfter(time);
  }

  List<DateTime>? _ends;

  /// The guide channel id for a playlist channel with [epgChannelId] and
  /// [name], or null when the guide has nothing for it.
  String? resolve({String? epgChannelId, String? name}) =>
      _resolved.putIfAbsent((epgChannelId, name), () {
        final id = epgChannelId?.trim();
        if (id != null && id.isNotEmpty) {
          if (_programs.containsKey(id)) return id;
          if (_byLowerId[_lowerId(id)] case final match?) return match;
        }
        if (name == null) return null;
        final normalized = normalizeChannelName(name);
        return normalized.isEmpty ? null : _byName[normalized];
      });

  /// Guide channel id for [channel]; see [resolve].
  String? resolveStream(LiveStream channel) =>
      resolve(epgChannelId: channel.epgChannelId, name: channel.name);

  /// All programmes of [channel], sorted by start.
  List<EpgProgram> programsFor(LiveStream channel) =>
      _programs[resolveStream(channel)] ?? const [];

  /// Programmes of [channel] that overlap `[from, to)`.
  List<EpgProgram> between(LiveStream channel, DateTime from, DateTime to) =>
      overlapping(programsFor(channel), from, to);

  /// The programme of [channel] airing at [at] and the next one. `now` is
  /// null in a gap; `next` is then the first programme after [at].
  NowNext nowAndNext(LiveStream channel, DateTime at) =>
      nowAndNextIn(programsFor(channel), at);

  /// The programmes of [list] (sorted, without overlaps) that overlap
  /// `[from, to)`.
  static List<EpgProgram> overlapping(
    List<EpgProgram> list,
    DateTime from,
    DateTime to,
  ) {
    final result = <EpgProgram>[];
    for (var i = firstEndingAfter(list, from); i < list.length; i++) {
      if (!list[i].start.isBefore(to)) break;
      result.add(list[i]);
    }
    return result;
  }

  /// The programme of [list] (sorted, without overlaps) airing at [at] and
  /// the next one; see [nowAndNext].
  static NowNext nowAndNextIn(List<EpgProgram> list, DateTime at) {
    final i = firstEndingAfter(list, at);
    if (i >= list.length) return (now: null, next: null);
    final candidate = list[i];
    if (candidate.isAiringAt(at)) {
      return (now: candidate, next: i + 1 < list.length ? list[i + 1] : null);
    }
    return (now: null, next: candidate);
  }

  /// Index of the first programme whose stop is after [time] (binary search;
  /// programmes don't overlap, so stops are sorted too).
  static int firstEndingAfter(List<EpgProgram> list, DateTime time) {
    var lo = 0, hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].stop.isAfter(time)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Cache format version written by [toJson].
  static const jsonVersion = 1;

  /// Compact JSON for an on-disk cache. Times are UTC epoch seconds.
  Map<String, Object?> toJson() => {
    'v': jsonVersion,
    'fetchedAt': _seconds(fetchedAt),
    'channels': {
      for (final MapEntry(:key, :value) in _programs.entries)
        key: {
          if (_displayNames[key] case final names? when names.isNotEmpty)
            'names': names,
          'programs': [
            for (final p in value)
              [
                _seconds(p.start),
                _seconds(p.stop),
                p.title,
                p.description,
                p.category,
              ],
          ],
        },
    },
  };

  /// Inverse of [toJson]. Returns null for another version or unreadable
  /// data.
  static EpgGuide? fromJson(Object? json) {
    if (json is! Map || json['v'] != jsonVersion) return null;
    final fetchedAt = json['fetchedAt'];
    final channels = json['channels'];
    if (fetchedAt is! int || channels is! Map) return null;
    final programs = <String, List<EpgProgram>>{};
    final names = <String, List<String>>{};
    for (final MapEntry(:key, :value) in channels.entries) {
      if (key is! String || value is! Map) return null;
      final rawNames = value['names'];
      if (rawNames is List) names[key] = rawNames.whereType<String>().toList();
      final rawPrograms = value['programs'];
      if (rawPrograms is! List) return null;
      final list = programs[key] = [];
      for (final p in rawPrograms) {
        if (p is! List || p.length != 5) return null;
        final [start, stop, title, description, category] = p;
        if (start is! int || stop is! int || title is! String) return null;
        list.add(
          EpgProgram(
            channelId: key,
            title: title,
            description: description is String ? description : null,
            category: category is String ? category : null,
            start: _fromSeconds(start),
            stop: _fromSeconds(stop),
          ),
        );
      }
    }
    return EpgGuide(
      programs: programs,
      displayNames: names,
      fetchedAt: _fromSeconds(fetchedAt),
    );
  }

  static int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  static DateTime _fromSeconds(int s) =>
      DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
}
