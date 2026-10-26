import '../models/episode.dart';
import '../models/series.dart';
import 'watch_data.dart';

/// Share of a movie or episode after which it counts as watched.
const watchedThreshold = 0.9;

/// Positions before this aren't worth resuming from.
const minResumePosition = Duration(seconds: 10);

/// [previous] updated with a playback [position]. Becomes watched once
/// [watchedThreshold] of [duration] is reached, and stays watched.
WatchProgress updatedProgress(
  WatchProgress? previous, {
  required Duration position,
  required Duration? duration,
  required DateTime now,
  int? seriesId,
  int? season,
  int? episode,
}) {
  final total = duration ?? previous?.duration;
  final reached =
      total != null &&
      total > Duration.zero &&
      position.inMilliseconds >= total.inMilliseconds * watchedThreshold;
  return WatchProgress(
    position: position,
    duration: total,
    watched: (previous?.watched ?? false) || reached,
    seriesId: seriesId ?? previous?.seriesId,
    season: season ?? previous?.season,
    episode: episode ?? previous?.episode,
    updatedAt: now,
  );
}

/// Where to resume [progress]; null to start from the beginning (nothing
/// saved, barely started, or already watched).
Duration? resumePosition(WatchProgress? progress) {
  if (progress == null || progress.watched) return null;
  return progress.position >= minResumePosition ? progress.position : null;
}

/// Whether [progress] should show as started (a progress bar) rather than
/// unwatched or watched.
bool isInProgress(WatchProgress? progress) => resumePosition(progress) != null;

/// One item to mark by hand: its [key] ([movieKey] / [episodeKey]) and, for
/// episodes, its series, season and episode number.
typedef WatchTarget = ({
  String key,
  int? seriesId,
  Duration? duration,
  int? season,
  int? episode,
});

/// The [WatchTarget] of a movie.
WatchTarget movieTarget(int streamId) => (
  key: movieKey(streamId),
  seriesId: null,
  duration: null,
  season: null,
  episode: null,
);

/// [data] with [targets] marked as [watched] or unwatched. Unwatched items
/// start from the beginning again.
WatchData markWatched(
  WatchData data,
  Iterable<WatchTarget> targets, {
  required bool watched,
  required DateTime now,
}) => data.withItems({
  for (final t in targets)
    t.key: WatchProgress(
      position: watched
          ? data.items[t.key]?.position ?? Duration.zero
          : Duration.zero,
      duration: t.duration ?? data.items[t.key]?.duration,
      watched: watched,
      seriesId: t.seriesId ?? data.items[t.key]?.seriesId,
      season: t.season ?? data.items[t.key]?.season,
      episode: t.episode ?? data.items[t.key]?.episode,
      updatedAt: now,
    ),
});

/// [WatchTarget]s for [episodes] of [info].
List<WatchTarget> episodeTargets(SeriesInfo info, Iterable<Episode> episodes) =>
    [
      for (final e in episodes)
        (
          key: episodeKey(e.id),
          seriesId: info.series.seriesId,
          duration: e.duration,
          season: e.season,
          episode: e.episodeNumber,
        ),
    ];

/// A tab on the series screen: one season, or the specials (season 0).
final class SeasonTab {
  const SeasonTab(this.number, this.name);

  final int number;
  final String name;

  bool get isSpecials => number == 0;

  @override
  bool operator ==(Object other) =>
      other is SeasonTab && other.number == number && other.name == name;

  @override
  int get hashCode => Object.hash(number, name);

  @override
  String toString() => 'SeasonTab($number, $name)';
}

/// The season tabs of [info]: seasons that have episodes, in order, with
/// the specials (season 0) last as "Specials".
List<SeasonTab> seasonTabs(SeriesInfo info) {
  final numbers = info.episodes.map((e) => e.season).toSet().toList()
    ..sort((a, b) {
      if (a == 0) return 1;
      if (b == 0) return -1;
      return a.compareTo(b);
    });
  final names = {for (final s in info.seasons) s.seasonNumber: s.name};
  return [
    for (final n in numbers)
      SeasonTab(n, n == 0 ? 'Specials' : _seasonName(n, names[n])),
  ];
}

/// The panel's season name unless it is empty or names another number.
String _seasonName(int number, String? name) {
  final fallback = 'Season $number';
  if (name == null || name.trim().isEmpty) return fallback;
  final digits = RegExp(r'\d+').firstMatch(name)?.group(0);
  return digits == null || int.parse(digits) == number ? name : fallback;
}

/// Watched and total episodes of one season.
final class SeasonProgress {
  const SeasonProgress(this.watched, this.total);

  final int watched;
  final int total;

  bool get complete => total > 0 && watched >= total;

  /// E.g. `3/10`.
  String get label => '$watched/$total';

  @override
  bool operator ==(Object other) =>
      other is SeasonProgress &&
      other.watched == watched &&
      other.total == total;

  @override
  int get hashCode => Object.hash(watched, total);

  @override
  String toString() => 'SeasonProgress($label)';
}

/// How [episode] stands across the variants of its series: the same
/// series listed several times by the provider (see `VariantGroups`).
/// Episodes match by season and episode number; an episode without a
/// number or without a counterpart has only its own record.
final class EpisodeGroupView {
  /// The view of the episodes of series [seriesId] with its [variants]
  /// (the other series ids of its group).
  EpisodeGroupView(this.data, this.seriesId, Iterable<int> variants)
    : _others = _index(data, variants.where((v) => v != seriesId).toSet());

  final WatchData data;
  final int seriesId;
  final Map<(int, int), List<(String, WatchProgress)>> _others;

  static Map<(int, int), List<(String, WatchProgress)>> _index(
    WatchData data,
    Set<int> variants,
  ) {
    final index = <(int, int), List<(String, WatchProgress)>>{};
    if (variants.isEmpty) return index;
    for (final MapEntry(:key, :value) in data.items.entries) {
      if (!key.startsWith('episode:') ||
          !variants.contains(value.seriesId) ||
          value.season == null ||
          (value.episode ?? 0) <= 0) {
        continue;
      }
      (index[(value.season!, value.episode!)] ??= []).add((key, value));
    }
    return index;
  }

  List<WatchProgress> _records(Episode e) => [
    ?data.episode(e.id),
    for (final (_, p) in othersOf(e)) p,
  ];

  /// [e]'s progress across the group: watched when watched in any variant,
  /// otherwise position and time of the newest record.
  WatchProgress? progress(Episode e) {
    final records = _records(e);
    if (records.isEmpty) return null;
    if (records.length == 1) return records.single;
    final newest = _newest(records);
    return WatchProgress(
      position: newest.position,
      duration: newest.duration,
      watched: records.any((r) => r.watched),
      seriesId: newest.seriesId,
      season: e.season,
      episode: e.episodeNumber,
      updatedAt: newest.updatedAt,
    );
  }

  /// The series whose record [progress] takes its position from, when it
  /// is another variant's.
  int? sourceOf(Episode e) {
    final records = _records(e);
    if (records.isEmpty) return null;
    final from = _newest(records).seriesId;
    return from == seriesId ? null : from;
  }

  /// The records of other variants for the same episode as [e], with
  /// their keys.
  List<(String, WatchProgress)> othersOf(Episode e) =>
      e.episodeNumber > 0 ? _others[(e.season, e.episodeNumber)] ?? [] : [];

  static WatchProgress _newest(List<WatchProgress> records) => records.reduce(
    (a, b) => b.updatedAt.isAfter(a.updatedAt) ? b : a,
  );
}

/// Reads an episode's progress: across the [group] when there is one.
WatchProgress? Function(Episode) _reader(
  WatchData data,
  EpisodeGroupView? group,
) => group?.progress ?? (e) => data.episode(e.id);

/// How much of [season] of [info] is watched (across its [group]).
SeasonProgress seasonProgress(
  SeriesInfo info,
  int season,
  WatchData data, {
  EpisodeGroupView? group,
}) {
  final read = _reader(data, group);
  final episodes = info.episodesForSeason(season);
  final watched = episodes.where((e) => _watched(read, e)).length;
  return SeasonProgress(watched, episodes.length);
}

bool _watched(WatchProgress? Function(Episode) read, Episode e) =>
    read(e)?.watched ?? false;

/// Regular episodes (season 1 and up) in viewing order.
List<Episode> _regular(SeriesInfo info) => [
  for (final e in info.episodes)
    if (e.season != 0) e,
];

/// The episodes [episode] is watched in sequence with: the regular ones, or
/// for a special, the other specials.
List<Episode> _sequence(SeriesInfo info, Episode episode) =>
    episode.season == 0 ? info.episodesForSeason(0) : _regular(info);

/// The episode after [episode] in viewing order, watched or not ("Play next
/// episode"). Specials are followed by the next special; the last episode
/// by nothing.
Episode? episodeAfter(SeriesInfo info, Episode episode) {
  final sequence = _sequence(info, episode);
  final i = sequence.indexWhere((e) => e.id == episode.id);
  return i < 0 || i + 1 >= sequence.length ? null : sequence[i + 1];
}

/// The episode to continue [info] with: the most recently played (or
/// marked) one if it isn't watched, else the next unwatched one after it,
/// else the first unwatched regular episode. Null when nothing was played
/// yet or every regular episode is watched. With a [group], episodes
/// played in other variants count too.
Episode? upNext(SeriesInfo info, WatchData data, {EpisodeGroupView? group}) {
  final read = _reader(data, group);
  Episode? latest;
  DateTime? latestTime;
  for (final e in info.episodes) {
    final p = read(e);
    if (p != null && (latestTime == null || p.updatedAt.isAfter(latestTime))) {
      latest = e;
      latestTime = p.updatedAt;
    }
  }
  if (latest == null) return null;
  if (!_watched(read, latest)) return latest;
  final sequence = _sequence(info, latest);
  final start = sequence.indexWhere((e) => e.id == latest!.id);
  for (final e in sequence.skip(start + 1)) {
    if (!_watched(read, e)) return e;
  }
  for (final e in _regular(info)) {
    if (!_watched(read, e)) return e;
  }
  return null;
}

/// The season tab to show when [info] opens: the season of [upNext], or the
/// first season.
int? initialSeason(
  SeriesInfo info,
  WatchData data, {
  EpisodeGroupView? group,
}) {
  final next = upNext(info, data, group: group);
  if (next != null) return next.season;
  final tabs = seasonTabs(info);
  return tabs.isEmpty ? null : tabs.first.number;
}

/// The [SeriesProgress] of [info] (across its [group]); null when none of
/// its episodes has been played or marked. Its time is that of the latest
/// episode change, so recomputing it doesn't reorder "Continue watching".
SeriesProgress? summarizeSeries(
  SeriesInfo info,
  WatchData data, {
  EpisodeGroupView? group,
}) {
  final read = _reader(data, group);
  DateTime? latest;
  for (final e in info.episodes) {
    final t = read(e)?.updatedAt;
    if (t != null && (latest == null || t.isAfter(latest))) latest = t;
  }
  if (latest == null) return null;
  final counted = _regular(info).isEmpty ? info.episodes : _regular(info);
  final next = upNext(info, data, group: group);
  return SeriesProgress(
    nextEpisodeId: next?.id,
    nextSeason: next?.season,
    nextEpisodeNumber: next?.episodeNumber,
    nextTitle: next?.title,
    watchedEpisodes: counted.where((e) => _watched(read, e)).length,
    totalEpisodes: counted.length,
    updatedAt: latest,
  );
}

/// [data] with the stored [SeriesProgress] of [info] brought up to date,
/// across its [variants] (other series ids of its group). Records of its
/// episodes written before they kept their season and episode number get
/// them. Returns [data] itself when nothing changed.
WatchData refreshSeries(
  WatchData data,
  SeriesInfo info, {
  Iterable<int> variants = const [],
}) {
  final id = info.series.seriesId;
  final numbered = <String, WatchProgress>{
    for (final e in info.episodes)
      if (data.episode(e.id) case final p? when p.season == null)
        episodeKey(e.id): p.numbered(e.season, e.episodeNumber),
  };
  if (numbered.isNotEmpty) data = data.withItems(numbered);
  final group = variants.isEmpty ? null : EpisodeGroupView(data, id, variants);
  final summary = summarizeSeries(info, data, group: group);
  if (summary == null || summary == data.series[id]) return data;
  return data.withSeries(id, summary);
}

/// [episodeTargets] of [episodes] of [info], plus the records of the same
/// episodes in the other variants of its [group]: marking an episode marks
/// it everywhere.
List<WatchTarget> groupEpisodeTargets(
  SeriesInfo info,
  Iterable<Episode> episodes,
  EpisodeGroupView? group,
) => [
  ...episodeTargets(info, episodes),
  if (group != null)
    for (final e in episodes)
      for (final (key, other) in group.othersOf(e))
        (
          key: key,
          seriesId: other.seriesId,
          duration: other.duration,
          season: other.season,
          episode: other.episode,
        ),
];

/// The progress of a movie seen together with its variants: [streamIds]
/// (itself included). Watched when any of them is; otherwise the position
/// of the one changed last, which is [from].
({WatchProgress progress, int from})? movieGroupProgress(
  WatchData data,
  Iterable<int> streamIds,
) {
  ({WatchProgress progress, int from})? newest;
  var watched = false;
  for (final id in streamIds) {
    final p = data.movie(id);
    if (p == null) continue;
    watched |= p.watched;
    if (newest == null || p.updatedAt.isAfter(newest.progress.updatedAt)) {
      newest = (progress: p, from: id);
    }
  }
  if (newest == null) return null;
  final p = newest.progress;
  return (
    progress: WatchProgress(
      position: p.position,
      duration: p.duration,
      watched: watched,
      updatedAt: p.updatedAt,
    ),
    from: newest.from,
  );
}

/// [continueMovies] with one entry per movie and its variants ([groupOf]
/// gives a movie's id and those of its variants): the most recent, and
/// none when one of them is watched.
List<(int, WatchProgress)> continueMovieGroups(
  WatchData data,
  List<int> Function(int) groupOf,
) {
  final seen = <int>{};
  return [
    for (final (id, progress) in continueMovies(data))
      if (_firstOfGroup(groupOf(id), seen) &&
          !(movieGroupProgress(data, groupOf(id))?.progress.watched ?? false))
        (id, progress),
  ];
}

/// [continueSeries] with one entry per series and its variants ([groupOf]
/// as for [continueMovieGroups]): the most recently watched.
List<(int, SeriesProgress)> continueSeriesGroups(
  WatchData data,
  List<int> Function(int) groupOf,
) {
  final seen = <int>{};
  return [
    for (final (id, progress) in continueSeries(data))
      if (_firstOfGroup(groupOf(id), seen)) (id, progress),
  ];
}

/// Whether none of [group] was [seen] yet; marks them seen.
bool _firstOfGroup(List<int> group, Set<int> seen) {
  var first = true;
  for (final id in group) {
    if (!seen.add(id)) first = false;
  }
  return first;
}

/// [data] with playback of [key] ([movieKey] / [seriesKey]) started at
/// [now], for "Last played".
WatchData recordPlayed(WatchData data, String key, DateTime now) =>
    data.copyWith(played: {...data.played, key: now});

/// Which of [keys] was played last; null when none was played.
String? lastPlayed(WatchData data, Iterable<String> keys) {
  String? last;
  DateTime? time;
  for (final key in keys) {
    final t = data.played[key];
    if (t != null && (time == null || t.isAfter(time))) {
      last = key;
      time = t;
    }
  }
  return last;
}

/// Movies to show under "Continue watching": started, not watched, most
/// recent first, as (stream id, progress).
List<(int, WatchProgress)> continueMovies(WatchData data) {
  final result = <(int, WatchProgress)>[];
  for (final MapEntry(:key, :value) in data.items.entries) {
    if (!key.startsWith('movie:') || !isInProgress(value)) continue;
    final id = int.tryParse(key.substring('movie:'.length));
    if (id != null) result.add((id, value));
  }
  result.sort((a, b) => b.$2.updatedAt.compareTo(a.$2.updatedAt));
  return result;
}

/// Series to show under "Continue watching": those with an episode to
/// continue with and not removed since their last episode change, most
/// recent first, as (series id, progress).
List<(int, SeriesProgress)> continueSeries(WatchData data) {
  final result = [
    for (final MapEntry(:key, :value) in data.series.entries)
      if (value.nextEpisodeId != null && !_removed(data, key, value))
        (key, value),
  ]..sort((a, b) => b.$2.updatedAt.compareTo(a.$2.updatedAt));
  return result;
}

bool _removed(WatchData data, int seriesId, SeriesProgress progress) {
  final removal = data.continueRemovals[seriesId];
  return removal != null &&
      removal.removed &&
      !progress.updatedAt.isAfter(removal.updatedAt);
}

/// [data] with movie [streamId] removed from "Continue watching": its
/// resume position is cleared at [now].
WatchData removeContinueMovie(WatchData data, int streamId, DateTime now) {
  final key = movieKey(streamId);
  final previous = data.items[key];
  if (previous == null) return data;
  return data.withItems({
    key: WatchProgress(
      position: Duration.zero,
      duration: previous.duration,
      updatedAt: now,
    ),
  });
}

/// [data] with movie [streamId]'s [previous] progress back, changed at
/// [now] (undoes [removeContinueMovie]).
WatchData restoreContinueMovie(
  WatchData data,
  int streamId,
  WatchProgress previous,
  DateTime now,
) => data.withItems({
  movieKey(streamId): WatchProgress(
    position: previous.position,
    duration: previous.duration,
    watched: previous.watched,
    seriesId: previous.seriesId,
    updatedAt: now,
  ),
});

/// [data] with series [seriesId] removed from "Continue watching" at
/// [now], until one of its episodes changes again. Its episodes keep their
/// progress and watched marks.
WatchData removeContinueSeries(WatchData data, int seriesId, DateTime now) =>
    data.copyWith(
      continueRemovals: {
        ...data.continueRemovals,
        seriesId: ContinueRemoval(now),
      },
    );

/// [data] with the removal of series [seriesId] undone at [now].
WatchData restoreContinueSeries(WatchData data, int seriesId, DateTime now) {
  if (data.continueRemovals[seriesId]?.removed != true) return data;
  return data.copyWith(
    continueRemovals: {
      ...data.continueRemovals,
      seriesId: ContinueRemoval(now, removed: false),
    },
  );
}

/// How many channels "Recently viewed channels" remembers.
const maxChannelHistory = 20;

/// [data] with channel [stableId] watched at [now]. Only the newest
/// [maxChannelHistory] channels (and as many removals) are kept.
WatchData recordChannel(WatchData data, String stableId, DateTime now) =>
    data.copyWith(
      channels: _trimChannels({...data.channels, stableId: ChannelVisit(now)}),
    );

/// [data] with channel [stableId] removed from the history at [now].
WatchData forgetChannel(WatchData data, String stableId, DateTime now) {
  final visit = data.channels[stableId];
  if (visit == null || visit.forgotten) return data;
  return data.copyWith(
    channels: _trimChannels({
      ...data.channels,
      stableId: ChannelVisit(now, forgotten: true),
    }),
  );
}

/// The newest [maxChannelHistory] visits and as many removals.
Map<String, ChannelVisit> _trimChannels(Map<String, ChannelVisit> channels) {
  final sorted = channels.entries.toList()
    ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
  var visits = 0;
  var removals = 0;
  return {
    for (final MapEntry(:key, :value) in sorted)
      if (value.forgotten
          ? ++removals <= maxChannelHistory
          : ++visits <= maxChannelHistory)
        key: value,
  };
}

/// Recently watched channels, newest first, as (stable id, time).
List<(String, DateTime)> recentChannels(WatchData data) {
  final result = [
    for (final MapEntry(:key, :value) in data.channels.entries)
      if (!value.forgotten) (key, value.updatedAt),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return result.take(maxChannelHistory).toList();
}
