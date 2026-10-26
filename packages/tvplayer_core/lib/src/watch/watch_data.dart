import 'dart:convert';
import 'dart:io';

import '../tracks/track_picker.dart';
import '../util/json.dart';

/// Key of a movie's [WatchProgress] in [WatchData.items].
String movieKey(int streamId) => 'movie:$streamId';

/// Key of an episode's [WatchProgress] in [WatchData.items].
String episodeKey(String episodeId) => 'episode:$episodeId';

/// Key of a series in [WatchData.played].
String seriesKey(int seriesId) => 'series:$seriesId';

/// How far one movie or episode was watched.
final class WatchProgress {
  const WatchProgress({
    required this.position,
    required this.updatedAt,
    this.duration,
    this.watched = false,
    this.seriesId,
    this.season,
    this.episode,
  });

  /// Where playback stopped.
  final Duration position;

  /// Total length, when known.
  final Duration? duration;

  /// Watched to the end (about 90 %) or marked as watched by hand. Stays
  /// set when watching again, until marked as unwatched.
  final bool watched;

  /// Last change (UTC). The newer record wins when merging copies.
  final DateTime updatedAt;

  /// For episodes: the series they belong to.
  final int? seriesId;

  /// For episodes: their season and episode number, to match them with
  /// the same episode of another variant of the series. Missing in
  /// records written before they were kept.
  final int? season;
  final int? episode;

  /// Watched fraction (0–1), when the duration is known.
  double? get fraction {
    final d = duration;
    if (d == null || d <= Duration.zero) return null;
    return (position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
    'pos': position.inMilliseconds,
    'dur': ?duration?.inMilliseconds,
    if (watched) 'watched': true,
    'series': ?seriesId,
    's': ?season,
    'e': ?episode,
  };

  static WatchProgress fromJson(Object? json, DateTime updatedAt) {
    final map = readMap(json) ?? const {};
    final dur = readInt(map['dur']);
    return WatchProgress(
      position: Duration(milliseconds: readInt(map['pos']) ?? 0),
      duration: dur == null ? null : Duration(milliseconds: dur),
      watched: readBool(map['watched']),
      seriesId: readInt(map['series']),
      season: readInt(map['s']),
      episode: readInt(map['e']),
      updatedAt: updatedAt,
    );
  }

  /// This progress with [season] and [episode] set, same time.
  WatchProgress numbered(int season, int episode) => WatchProgress(
    position: position,
    duration: duration,
    watched: watched,
    seriesId: seriesId,
    season: season,
    episode: episode,
    updatedAt: updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is WatchProgress &&
      other.position == position &&
      other.duration == duration &&
      other.watched == watched &&
      other.updatedAt == updatedAt &&
      other.seriesId == seriesId &&
      other.season == season &&
      other.episode == episode;

  @override
  int get hashCode => Object.hash(
    position,
    duration,
    watched,
    updatedAt,
    seriesId,
    season,
    episode,
  );

  @override
  String toString() =>
      'WatchProgress($position/$duration${watched ? ', watched' : ''})';
}

/// Where a series stands, for its "Continue watching" card and poster
/// badge. Derived from the episodes' [WatchProgress] (see
/// `summarizeSeries`) and stored so the Series tab needn't fetch every
/// series' episode list.
final class SeriesProgress {
  const SeriesProgress({
    required this.updatedAt,
    required this.watchedEpisodes,
    required this.totalEpisodes,
    this.nextEpisodeId,
    this.nextSeason,
    this.nextEpisodeNumber,
    this.nextTitle,
  });

  /// The episode to continue with: the one in progress, or the next
  /// unwatched one. Null when there is none left.
  final String? nextEpisodeId;
  final int? nextSeason;
  final int? nextEpisodeNumber;
  final String? nextTitle;

  /// Watched and total regular episodes (specials don't count).
  final int watchedEpisodes;
  final int totalEpisodes;

  /// Time of the latest episode change.
  final DateTime updatedAt;

  bool get finished => totalEpisodes > 0 && watchedEpisodes >= totalEpisodes;

  /// Watched share of the episodes (0–1).
  double get fraction =>
      totalEpisodes == 0 ? 0 : watchedEpisodes / totalEpisodes;

  Map<String, Object?> toJson() => {
    'next': ?nextEpisodeId,
    'season': ?nextSeason,
    'episode': ?nextEpisodeNumber,
    'title': ?nextTitle,
    'watched': watchedEpisodes,
    'total': totalEpisodes,
  };

  static SeriesProgress fromJson(Object? json, DateTime updatedAt) {
    final map = readMap(json) ?? const {};
    return SeriesProgress(
      nextEpisodeId: readString(map['next']),
      nextSeason: readInt(map['season']),
      nextEpisodeNumber: readInt(map['episode']),
      nextTitle: readString(map['title']),
      watchedEpisodes: readInt(map['watched']) ?? 0,
      totalEpisodes: readInt(map['total']) ?? 0,
      updatedAt: updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SeriesProgress &&
      other.nextEpisodeId == nextEpisodeId &&
      other.nextSeason == nextSeason &&
      other.nextEpisodeNumber == nextEpisodeNumber &&
      other.nextTitle == nextTitle &&
      other.watchedEpisodes == watchedEpisodes &&
      other.totalEpisodes == totalEpisodes &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    nextEpisodeId,
    nextSeason,
    nextEpisodeNumber,
    nextTitle,
    watchedEpisodes,
    totalEpisodes,
    updatedAt,
  );
}

/// A track choice remembered for a series, with its change time.
final class SeriesTracks {
  const SeriesTracks(this.memory, this.updatedAt);

  final TrackMemory memory;
  final DateTime updatedAt;
}

/// When a live channel was last watched, for "Recently viewed channels".
/// [forgotten] is a tombstone: removed from the history by hand, kept so
/// the removal survives a merge.
final class ChannelVisit {
  const ChannelVisit(this.updatedAt, {this.forgotten = false});

  final DateTime updatedAt;
  final bool forgotten;

  @override
  bool operator ==(Object other) =>
      other is ChannelVisit &&
      other.updatedAt == updatedAt &&
      other.forgotten == forgotten;

  @override
  int get hashCode => Object.hash(updatedAt, forgotten);
}

/// A series taken out of "Continue watching" by hand. It stays out until
/// one of its episodes changes after [updatedAt]. Not [removed] after an
/// Undo; kept either way so the latest choice survives a merge.
final class ContinueRemoval {
  const ContinueRemoval(this.updatedAt, {this.removed = true});

  final DateTime updatedAt;
  final bool removed;

  @override
  bool operator ==(Object other) =>
      other is ContinueRemoval &&
      other.updatedAt == updatedAt &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(updatedAt, removed);
}

/// Everything remembered about watching, for one provider.
///
/// Stored as a flat list of records, each with a key and a change time, so
/// copies from several devices (e.g. through a sync server later) can be
/// combined with [merge]: per record, the newer one wins.
final class WatchData {
  const WatchData({
    this.items = const {},
    this.series = const {},
    this.seriesTracks = const {},
    this.channels = const {},
    this.continueRemovals = const {},
    this.played = const {},
  });

  /// Progress by [movieKey] / [episodeKey].
  final Map<String, WatchProgress> items;

  /// Series summaries by series id.
  final Map<int, SeriesProgress> series;

  /// Remembered track choices by series id.
  final Map<int, SeriesTracks> seriesTracks;

  /// Watched live channels by `LiveStream.stableId`, including forgotten
  /// ones.
  final Map<String, ChannelVisit> channels;

  /// Series removed from "Continue watching" (and undone removals) by
  /// series id.
  final Map<int, ContinueRemoval> continueRemovals;

  /// When playback of a movie ([movieKey]) or an episode of a series
  /// ([seriesKey]) last started, to mark the source played last.
  final Map<String, DateTime> played;

  static const empty = WatchData();

  WatchProgress? movie(int streamId) => items[movieKey(streamId)];

  WatchProgress? episode(String episodeId) => items[episodeKey(episodeId)];

  WatchData copyWith({
    Map<String, WatchProgress>? items,
    Map<int, SeriesProgress>? series,
    Map<int, SeriesTracks>? seriesTracks,
    Map<String, ChannelVisit>? channels,
    Map<int, ContinueRemoval>? continueRemovals,
    Map<String, DateTime>? played,
  }) => WatchData(
    items: items ?? this.items,
    series: series ?? this.series,
    seriesTracks: seriesTracks ?? this.seriesTracks,
    channels: channels ?? this.channels,
    continueRemovals: continueRemovals ?? this.continueRemovals,
    played: played ?? this.played,
  );

  /// This data with [progress] added, replacing records with the same key.
  WatchData withItems(Map<String, WatchProgress> progress) =>
      copyWith(items: {...items, ...progress});

  WatchData withSeries(int seriesId, SeriesProgress progress) =>
      copyWith(series: {...series, seriesId: progress});

  WatchData withTracks(int seriesId, SeriesTracks tracks) =>
      copyWith(seriesTracks: {...seriesTracks, seriesId: tracks});

  /// Combines two copies: for each record, the one changed last wins.
  WatchData merge(WatchData other) {
    Map<K, V> newest<K, V>(
      Map<K, V> a,
      Map<K, V> b,
      DateTime Function(V) time,
    ) => {
      ...a,
      for (final MapEntry(:key, :value) in b.entries)
        if (a[key] == null || time(value).isAfter(time(a[key] as V)))
          key: value,
    };
    return WatchData(
      items: newest(items, other.items, (p) => p.updatedAt),
      series: newest(series, other.series, (p) => p.updatedAt),
      seriesTracks: newest(
        seriesTracks,
        other.seriesTracks,
        (t) => t.updatedAt,
      ),
      channels: newest(channels, other.channels, (v) => v.updatedAt),
      continueRemovals: newest(
        continueRemovals,
        other.continueRemovals,
        (r) => r.updatedAt,
      ),
      played: newest(played, other.played, (t) => t),
    );
  }

  /// The records as JSON: `{"version": 1, "records": [{"k", "t", "v"}]}`,
  /// with `t` the change time in milliseconds since the epoch.
  Map<String, Object?> toJson() {
    Map<String, Object?> record(String key, DateTime time, Object? value) => {
      'k': key,
      't': time.millisecondsSinceEpoch,
      'v': value,
    };
    return {
      'version': 1,
      'records': [
        for (final MapEntry(:key, :value) in items.entries)
          record(key, value.updatedAt, value.toJson()),
        for (final MapEntry(:key, :value) in series.entries)
          record('series:$key', value.updatedAt, value.toJson()),
        for (final MapEntry(:key, :value) in seriesTracks.entries)
          record('tracks:$key', value.updatedAt, value.memory.toJson()),
        for (final MapEntry(:key, :value) in channels.entries)
          record(
            'channel:$key',
            value.updatedAt,
            value.forgotten ? {'forgotten': true} : const <String, Object?>{},
          ),
        for (final MapEntry(:key, :value) in continueRemovals.entries)
          record(
            'continue:$key',
            value.updatedAt,
            value.removed ? const <String, Object?>{} : {'undone': true},
          ),
        for (final MapEntry(:key, :value) in played.entries)
          record('played:$key', value, const <String, Object?>{}),
      ],
    };
  }

  /// Lenient inverse of [toJson]; unreadable records are skipped.
  factory WatchData.fromJson(Object? json) {
    final items = <String, WatchProgress>{};
    final series = <int, SeriesProgress>{};
    final tracks = <int, SeriesTracks>{};
    final channels = <String, ChannelVisit>{};
    final removals = <int, ContinueRemoval>{};
    final played = <String, DateTime>{};
    for (final r in readList(readMap(json)?['records'])) {
      final record = readMap(r);
      final key = readString(record?['k']);
      final ms = readInt(record?['t']);
      if (record == null || key == null || ms == null) continue;
      final time = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      final value = record['v'];
      final colon = key.indexOf(':');
      if (colon < 0) continue;
      final id = key.substring(colon + 1);
      switch (key.substring(0, colon)) {
        case 'movie' || 'episode':
          items[key] = WatchProgress.fromJson(value, time);
        case 'series' when int.tryParse(id) != null:
          series[int.parse(id)] = SeriesProgress.fromJson(value, time);
        case 'tracks' when int.tryParse(id) != null:
          tracks[int.parse(id)] = SeriesTracks(
            TrackMemory.fromJson(value),
            time,
          );
        case 'channel' when id.isNotEmpty:
          channels[id] = ChannelVisit(
            time,
            forgotten: readBool(readMap(value)?['forgotten']),
          );
        case 'continue' when int.tryParse(id) != null:
          removals[int.parse(id)] = ContinueRemoval(
            time,
            removed: !readBool(readMap(value)?['undone']),
          );
        case 'played'
            when id.startsWith('movie:') || id.startsWith('series:'):
          played[id] = time;
      }
    }
    return WatchData(
      items: items,
      series: series,
      seriesTracks: tracks,
      channels: channels,
      continueRemovals: removals,
      played: played,
    );
  }
}

/// Persists [WatchData] for one provider. The local file store is the only
/// one today; a sync server can be added as another implementation (or a
/// wrapper that [WatchData.merge]s the server's copy into the local one).
abstract interface class WatchStore {
  /// The saved data; empty when none is saved or it can't be read.
  Future<WatchData> load();

  Future<void> save(WatchData data);
}

/// [WatchStore] in a JSON file.
class JsonFileWatchStore implements WatchStore {
  JsonFileWatchStore(this.file);

  final File file;

  @override
  Future<WatchData> load() async {
    try {
      if (!await file.exists()) return WatchData.empty;
      return WatchData.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      return WatchData.empty;
    }
  }

  @override
  Future<void> save(WatchData data) async {
    await file.parent.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()));
    await tmp.rename(file.path);
  }
}
