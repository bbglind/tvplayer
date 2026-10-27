import '../util/json.dart';
import '../watch/watch_data.dart';

/// What a download is.
enum DownloadKind {
  movie,
  episode,

  /// A programme saved from a channel's archive.
  replay,

  /// Live TV recorded from what the player plays.
  recording,
}

enum DownloadStatus {
  /// In the queue, waiting for its turn.
  queued,

  /// Being downloaded now.
  running,

  /// Stopped part way; see [DownloadItem.pauseReason].
  paused,

  /// An archive programme whose end (plus the end margin) hasn't passed
  /// yet; it starts after [DownloadItem.to].
  waiting,

  /// Stopped by an error; see [DownloadItem.message].
  failed,

  /// The file is complete.
  done,

  /// A recording in progress.
  recording,
}

/// Why a download is paused.
enum PauseReason {
  /// By the user; only the user resumes it.
  user,

  /// To let the player use the provider stream; resumes when it stops.
  playback,

  /// The disk is (nearly) full; resumes only when the user says so.
  lowSpace,
}

/// One entry of the downloads list.
///
/// Holds no URL: the stream URL contains the account's credentials and is
/// built from [sourceId] only when the download runs.
final class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.sourceId,
    required this.extension,
    required this.path,
    required this.addedAt,
    this.label,
    this.year,
    this.seriesId,
    this.season,
    this.episode,
    this.episodeTitle,
    this.programme,
    this.from,
    this.to,
    this.posterUrl,
    this.status = DownloadStatus.queued,
    this.pauseReason,
    this.message,
    this.bytes = 0,
    this.totalBytes,
    this.finishedAt,
  });

  final String id;
  final DownloadKind kind;

  /// The clean title: the movie, the series or the channel.
  final String title;

  /// The provider's stream id of the movie or episode, or the channel's id.
  final String sourceId;

  /// The file extension, without the dot.
  final String extension;

  /// Where the finished file goes (absolute).
  final String path;
  final DateTime addedAt;

  /// The provider's label of the title (`NF`), if any.
  final String? label;
  final int? year;
  final int? seriesId;
  final int? season;
  final int? episode;

  /// The episode's own name, already cleaned.
  final String? episodeTitle;

  /// The programme of a replay or recording.
  final String? programme;

  /// Start and end of a replay or recording (real instants, UTC).
  final DateTime? from;
  final DateTime? to;
  final String? posterUrl;
  final DownloadStatus status;
  final PauseReason? pauseReason;

  /// Why it failed, or a note such as "Couldn't resume: started again".
  final String? message;

  /// Bytes saved so far.
  final int bytes;

  /// The full size, when the server says.
  final int? totalBytes;
  final DateTime? finishedAt;

  /// Where the download is written until it is complete.
  String get partPath => '$path.part';

  /// The watch history key it shares with the streamed item; null for
  /// replays and recordings, which keep no position.
  String? get watchKey => switch (kind) {
    DownloadKind.movie => switch (int.tryParse(sourceId)) {
      final id? => movieKey(id),
      null => null,
    },
    DownloadKind.episode => episodeKey(sourceId),
    DownloadKind.replay || DownloadKind.recording => null,
  };

  bool get isDone => status == DownloadStatus.done;

  /// Still to be downloaded: in the queue, running, paused, waiting or
  /// failed.
  bool get isPending =>
      status != DownloadStatus.done && status != DownloadStatus.recording;

  /// Whole minutes from [from] to [to] (at least 1), as the archive wants
  /// them.
  int? get minutes {
    final f = from, t = to;
    if (f == null || t == null) return null;
    final m = (t.difference(f).inSeconds / 60).ceil();
    return m < 1 ? 1 : m;
  }

  /// The fraction downloaded, or null when the size isn't known.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytes / total).clamp(0.0, 1.0);
  }

  DownloadItem copyWith({
    String? path,
    DownloadStatus? status,
    PauseReason? Function()? pauseReason,
    String? Function()? message,
    int? bytes,
    int? Function()? totalBytes,
    DateTime? Function()? finishedAt,
    DateTime? to,
  }) => DownloadItem(
    id: id,
    kind: kind,
    title: title,
    sourceId: sourceId,
    extension: extension,
    path: path ?? this.path,
    addedAt: addedAt,
    label: label,
    year: year,
    seriesId: seriesId,
    season: season,
    episode: episode,
    episodeTitle: episodeTitle,
    programme: programme,
    from: from,
    to: to ?? this.to,
    posterUrl: posterUrl,
    status: status ?? this.status,
    pauseReason: pauseReason == null ? this.pauseReason : pauseReason(),
    message: message == null ? this.message : message(),
    bytes: bytes ?? this.bytes,
    totalBytes: totalBytes == null ? this.totalBytes : totalBytes(),
    finishedAt: finishedAt == null ? this.finishedAt : finishedAt(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'source': sourceId,
    'ext': extension,
    'path': path,
    'added': addedAt.toUtc().toIso8601String(),
    'label': ?label,
    'year': ?year,
    'seriesId': ?seriesId,
    'season': ?season,
    'episode': ?episode,
    'episodeTitle': ?episodeTitle,
    'programme': ?programme,
    'from': ?from?.toUtc().toIso8601String(),
    'to': ?to?.toUtc().toIso8601String(),
    'poster': ?posterUrl,
    'status': status.name,
    'pause': ?pauseReason?.name,
    'message': ?message,
    'bytes': bytes,
    'total': ?totalBytes,
    'finished': ?finishedAt?.toUtc().toIso8601String(),
  };

  /// Reads an entry written by [toJson]; null when it is unusable.
  static DownloadItem? fromJson(Object? json) {
    final map = readMap(json);
    if (map == null) return null;
    final id = readString(map['id']);
    final kind = _byName(DownloadKind.values, map['kind']);
    final title = readString(map['title']);
    final source = readString(map['source']);
    final ext = readString(map['ext']);
    final path = readString(map['path']);
    final added = _date(map['added']);
    if (id == null ||
        kind == null ||
        title == null ||
        source == null ||
        ext == null ||
        path == null ||
        added == null) {
      return null;
    }
    return DownloadItem(
      id: id,
      kind: kind,
      title: title,
      sourceId: source,
      extension: ext,
      path: path,
      addedAt: added,
      label: readString(map['label']),
      year: readInt(map['year']),
      seriesId: readInt(map['seriesId']),
      season: readInt(map['season']),
      episode: readInt(map['episode']),
      episodeTitle: readString(map['episodeTitle']),
      programme: readString(map['programme']),
      from: _date(map['from']),
      to: _date(map['to']),
      posterUrl: readString(map['poster']),
      status:
          _byName(DownloadStatus.values, map['status']) ??
          DownloadStatus.queued,
      pauseReason: _byName(PauseReason.values, map['pause']),
      message: readString(map['message']),
      bytes: readInt(map['bytes']) ?? 0,
      totalBytes: readInt(map['total']),
      finishedAt: _date(map['finished']),
    );
  }

  @override
  String toString() => 'DownloadItem($id, ${kind.name}, ${status.name})';
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
