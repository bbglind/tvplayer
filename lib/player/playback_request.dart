import 'package:tvplayer_core/tvplayer_core.dart';

import '../format.dart';

/// What the player should play.
sealed class PlaybackRequest {
  const PlaybackRequest();

  /// Shown in the app bar and as the mpv window title.
  String get title;

  /// Whether the content has a fixed length (a movie or an episode), so it
  /// gets a seek bar and a saved position. Live streams don't: mpv's
  /// duration there is only what is buffered.
  bool get fixedLength => true;

  /// Where to start; null for the beginning.
  Duration? get start => null;

  /// Key of the [WatchProgress] to update; null for live TV.
  String? get watchKey => null;

  /// Playback URL from the provider's sources; null when the needed source
  /// is missing. Contains credentials: never log or show it.
  Uri? url({LiveSource? live, VodSource? vod});
}

final class LivePlayback extends PlaybackRequest {
  const LivePlayback(this.channel);

  final LiveStream channel;

  @override
  String get title => channel.name;

  @override
  bool get fixedLength => false;

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => live?.streamUrl(channel);
}

final class MoviePlayback extends PlaybackRequest {
  const MoviePlayback(this.movie, {this.start});

  final Movie movie;

  @override
  final Duration? start;

  @override
  String get title => movie.name;

  @override
  String get watchKey => movieKey(movie.streamId);

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => vod?.movieUrl(movie);
}

final class EpisodePlayback extends PlaybackRequest {
  const EpisodePlayback(this.info, this.episode, {this.start});

  /// The series with all its episodes, to find the next one.
  final SeriesInfo info;
  final Episode episode;

  @override
  final Duration? start;

  @override
  String get title => episodeTitle(info.series, episode);

  @override
  String get watchKey => episodeKey(episode.id);

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => vod?.episodeUrl(episode);
}

/// E.g. `Series · S01E02 · Pilot`. Panels often put the series name and
/// code in the episode title already; those parts aren't repeated.
String episodeTitle(Series series, Episode episode) {
  final code = formatEpisodeCode(episode.season, episode.episodeNumber);
  final title = episode.title;
  final lower = title.toLowerCase();
  return [
    if (!lower.contains(series.name.toLowerCase())) series.name,
    if (!lower.contains(code.toLowerCase())) code,
    title,
  ].join(' · ');
}
