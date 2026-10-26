import 'package:tvplayer_core/tvplayer_core.dart';

import '../format.dart';

/// What the player should play.
sealed class PlaybackRequest {
  const PlaybackRequest();

  /// The provider's name of what plays: the channel, movie or series.
  String get name;

  /// Shown in the app bar and as the mpv window title: [name] without the
  /// provider's tag (see [ProviderTags]).
  String title(ProviderTags tags);

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
  String get name => channel.name;

  @override
  String title(ProviderTags tags) => channel.name;

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
  String get name => movie.name;

  @override
  String title(ProviderTags tags) => tags.display(movie.name).title;

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
  String get name => info.series.name;

  @override
  String title(ProviderTags tags) => episodeTitle(info.series, episode, tags);

  @override
  String get watchKey => episodeKey(episode.id);

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => vod?.episodeUrl(episode);
}

/// E.g. `Series · S01E02 · Pilot`, without the provider's tag. Panels
/// often put the series name and code in the episode title already; those
/// parts aren't repeated (see [episodeDisplayTitle]).
String episodeTitle(Series series, Episode episode, ProviderTags tags) => [
  tags.display(series.name).title,
  formatEpisodeCode(episode.season, episode.episodeNumber),
  episodeDisplayTitle(series, episode, tags),
].join(' · ');

/// The provider's full name of [episode] for a tooltip: its title, with
/// the series name in front unless the title has it already.
String episodeFullName(Series series, Episode episode) =>
    episode.title.toLowerCase().contains(series.name.toLowerCase())
    ? episode.title
    : '${series.name} · ${episode.title}';
