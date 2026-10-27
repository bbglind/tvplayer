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

  /// Whether it plays from the provider, using one of its streams (see
  /// `StreamGuard`); a downloaded file doesn't.
  bool get usesProviderStream => true;

  /// Playback URL from the provider's sources (or the downloaded file);
  /// null when the needed source is missing. Contains credentials: never
  /// log or show it.
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

/// A live channel from the provider's archive (catch-up), from the real
/// moment [from] on: a past programme, or live TV behind live.
final class ReplayPlayback extends PlaybackRequest {
  /// [serverZone] is the zone the provider reads start times in;
  /// [requestedAt] is now, which decides how much is asked for.
  ReplayPlayback(
    this.channel, {
    required this.from,
    required this.serverZone,
    required this.requestedAt,
  }) : timeshift = TimeshiftStart.at(
         from,
         GuideTime.findZone(serverZone) ?? GuideTime.findZone('UTC')!,
       );

  final LiveStream channel;
  final DateTime from;
  final String serverZone;
  final DateTime requestedAt;

  /// The start as the provider wants it, and how far into the stream
  /// [from] is.
  final TimeshiftStart timeshift;

  @override
  String get name => channel.name;

  @override
  String title(ProviderTags tags) => withoutReplayMark(channel.name);

  /// The archive is a file of what was recorded: it has a length and can
  /// be sought in.
  @override
  bool get fixedLength => true;

  @override
  Duration? get start =>
      timeshift.offset > Duration.zero ? timeshift.offset : null;

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => live?.replayUrl(
    channel,
    timeshift,
    timeshiftMinutes(timeshift.floored, requestedAt),
  );
}

final class MoviePlayback extends PlaybackRequest {
  const MoviePlayback(this.movie, {this.start, this.localFile});

  final Movie movie;

  /// The downloaded file to play instead of the provider's stream.
  final String? localFile;

  MoviePlayback withLocalFile(String? path) =>
      MoviePlayback(movie, start: start, localFile: path);

  @override
  bool get usesProviderStream => localFile == null;

  @override
  final Duration? start;

  @override
  String get name => movie.name;

  @override
  String title(ProviderTags tags) => tags.display(movie.name).title;

  @override
  String get watchKey => movieKey(movie.streamId);

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => switch (localFile) {
    final path? => Uri.file(path),
    null => vod?.movieUrl(movie),
  };
}

final class EpisodePlayback extends PlaybackRequest {
  const EpisodePlayback(this.info, this.episode, {this.start, this.localFile});

  /// The series with all its episodes, to find the next one.
  final SeriesInfo info;
  final Episode episode;

  /// The downloaded file to play instead of the provider's stream.
  final String? localFile;

  EpisodePlayback withLocalFile(String? path) =>
      EpisodePlayback(info, episode, start: start, localFile: path);

  @override
  bool get usesProviderStream => localFile == null;

  @override
  final Duration? start;

  @override
  String get name => info.series.name;

  @override
  String title(ProviderTags tags) => episodeTitle(info.series, episode, tags);

  @override
  String get watchKey => episodeKey(episode.id);

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => switch (localFile) {
    final path? => Uri.file(path),
    null => vod?.episodeUrl(episode),
  };
}

/// A recording or a programme saved from the archive, played from its
/// file. It keeps no position and stays out of Continue watching, like a
/// replay.
final class RecordingPlayback extends PlaybackRequest {
  const RecordingPlayback(this.file, {required this.name});

  final String file;

  @override
  final String name;

  @override
  String title(ProviderTags tags) => name;

  @override
  bool get usesProviderStream => false;

  @override
  Uri? url({LiveSource? live, VodSource? vod}) => Uri.file(file);
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
