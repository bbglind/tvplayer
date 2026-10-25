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
/// episodes, its series.
typedef WatchTarget = ({String key, int? seriesId, Duration? duration});

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

/// How much of [season] of [info] is watched.
SeasonProgress seasonProgress(SeriesInfo info, int season, WatchData data) {
  final episodes = info.episodesForSeason(season);
  final watched = episodes.where((e) => _watched(data, e)).length;
  return SeasonProgress(watched, episodes.length);
}

bool _watched(WatchData data, Episode e) =>
    data.episode(e.id)?.watched ?? false;

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
/// marked) one if it isn't watched, else the next unwatched one after it, else the first
/// unwatched regular episode. Null when nothing was played yet or every
/// regular episode is watched.
Episode? upNext(SeriesInfo info, WatchData data) {
  Episode? latest;
  DateTime? latestTime;
  for (final e in info.episodes) {
    final p = data.episode(e.id);
    if (p != null && (latestTime == null || p.updatedAt.isAfter(latestTime))) {
      latest = e;
      latestTime = p.updatedAt;
    }
  }
  if (latest == null) return null;
  if (!_watched(data, latest)) return latest;
  final sequence = _sequence(info, latest);
  final start = sequence.indexWhere((e) => e.id == latest!.id);
  for (final e in sequence.skip(start + 1)) {
    if (!_watched(data, e)) return e;
  }
  for (final e in _regular(info)) {
    if (!_watched(data, e)) return e;
  }
  return null;
}

/// The season tab to show when [info] opens: the season of [upNext], or the
/// first season.
int? initialSeason(SeriesInfo info, WatchData data) {
  final next = upNext(info, data);
  if (next != null) return next.season;
  final tabs = seasonTabs(info);
  return tabs.isEmpty ? null : tabs.first.number;
}

/// The [SeriesProgress] of [info]; null when none of its episodes has been
/// played or marked. Its time is that of the latest episode change, so
/// recomputing it doesn't reorder "Continue watching".
SeriesProgress? summarizeSeries(SeriesInfo info, WatchData data) {
  DateTime? latest;
  for (final e in info.episodes) {
    final t = data.episode(e.id)?.updatedAt;
    if (t != null && (latest == null || t.isAfter(latest))) latest = t;
  }
  if (latest == null) return null;
  final counted = _regular(info).isEmpty ? info.episodes : _regular(info);
  final next = upNext(info, data);
  return SeriesProgress(
    nextEpisodeId: next?.id,
    nextSeason: next?.season,
    nextEpisodeNumber: next?.episodeNumber,
    nextTitle: next?.title,
    watchedEpisodes: counted.where((e) => _watched(data, e)).length,
    totalEpisodes: counted.length,
    updatedAt: latest,
  );
}

/// [data] with the stored [SeriesProgress] of [info] brought up to date.
/// Returns [data] itself when nothing changed.
WatchData refreshSeries(WatchData data, SeriesInfo info) {
  final id = info.series.seriesId;
  final summary = summarizeSeries(info, data);
  if (summary == null || summary == data.series[id]) return data;
  return data.withSeries(id, summary);
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
/// continue with, most recent first, as (series id, progress).
List<(int, SeriesProgress)> continueSeries(WatchData data) {
  final result = [
    for (final MapEntry(:key, :value) in data.series.entries)
      if (value.nextEpisodeId != null) (key, value),
  ]..sort((a, b) => b.$2.updatedAt.compareTo(a.$2.updatedAt));
  return result;
}

/// How many channels "Recently viewed channels" remembers.
const maxChannelHistory = 20;

/// [data] with channel [stableId] watched at [now]. Only the newest
/// [maxChannelHistory] channels (and as many removals) are kept.
WatchData recordChannel(WatchData data, String stableId, DateTime now) =>
    data.copyWith(
      channels: _trimChannels({
        ...data.channels,
        stableId: ChannelVisit(now),
      }),
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
