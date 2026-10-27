import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/app_settings.dart';
import '../data/free_space.dart';
import '../data/videos_directory.dart';
import '../format.dart';
import 'providers.dart';

/// How many provider streams may be open at once. The provider of this
/// app's user allows one; to follow the account instead, return
/// `AccountInfo.maxConnections` from the login here.
final providerStreamLimitProvider = Provider<int>((ref) => 1);

/// The one place that hands out the provider's streams: the player and
/// the downloads queue both ask it.
final streamGuardProvider = Provider<StreamGuard>(
  (ref) => StreamGuard(limit: () => ref.read(providerStreamLimitProvider)),
);

/// Creates the downloads list store of a provider (by [providerKey]).
/// Overridden in tests.
final downloadsStoreProvider = Provider<DownloadsStore Function(String key)>(
  (ref) =>
      (key) => _FileDownloadsStore(key),
);

/// Free disk space. Overridden in tests.
final freeSpaceProvider = Provider<FreeSpace>((ref) => const DfFreeSpace());

/// The folder used when Settings names none. Overridden in tests.
final defaultDownloadFolderProvider = Provider<String>(
  (ref) => defaultDownloadFolder(),
);

/// Where new downloads and recordings are saved.
final downloadFolderProvider = Provider<String>((ref) {
  final settings = ref.watch(appSettingsProvider).value ?? const AppSettings();
  return settings.downloadFolder ?? ref.watch(defaultDownloadFolderProvider);
});

/// Runs one download over HTTP. Overridden in tests.
final transferRunnerProvider = Provider<TransferRunner>((ref) {
  final http = HttpDownload(client: ref.watch(httpClientProvider));
  return (item, control, onProgress) async {
    final url = await downloadUrl(ref, item);
    if (url == null) {
      return const TransferFailed(
        "The provider doesn't offer this for download.",
      );
    }
    return http.run(
      url: url,
      path: item.path,
      control: control,
      onProgress: onProgress,
    );
  };
});

/// The stream URL of [item], built from the provider's sources only when
/// it is needed. Contains credentials: never log or show it.
Future<Uri?> downloadUrl(Ref ref, DownloadItem item) async {
  switch (item.kind) {
    case DownloadKind.movie:
      final id = int.tryParse(item.sourceId);
      if (id == null) return null;
      return ref
          .read(vodSourceProvider)
          ?.movieUrl(
            Movie(
              streamId: id,
              name: item.title,
              containerExtension: item.extension,
            ),
          );
    case DownloadKind.episode:
      return ref
          .read(vodSourceProvider)
          ?.episodeUrl(
            Episode(
              id: item.sourceId,
              season: item.season ?? 1,
              episodeNumber: item.episode ?? 1,
              title: item.episodeTitle ?? '',
              containerExtension: item.extension,
            ),
          );
    case DownloadKind.replay:
      final from = item.from, minutes = item.minutes;
      if (from == null || minutes == null) return null;
      final zone = await ref.read(serverTimeZoneProvider.future);
      final location = GuideTime.findZone(zone) ?? GuideTime.findZone('UTC')!;
      return ref
          .read(liveSourceProvider)
          ?.replayUrl(
            LiveStream(id: item.sourceId, name: item.title, archiveDays: 1),
            TimeshiftStart.at(from, location),
            minutes,
          );
    case DownloadKind.recording:
      return null;
  }
}

/// The downloads list of the active provider, with what the running
/// download is doing.
@immutable
final class DownloadsState {
  const DownloadsState({
    this.items = const [],
    this.speed,
    this.timeLeft,
    this.loaded = false,
  });

  /// In queue order, finished ones and recordings included.
  final List<DownloadItem> items;

  /// Bytes per second of the running download.
  final double? speed;
  final Duration? timeLeft;
  final bool loaded;

  DownloadItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// The entry of the movie or episode with watch key [key].
  DownloadItem? forWatchKey(String key) {
    for (final item in items) {
      if (item.watchKey == key) return item;
    }
    return null;
  }

  /// The finished file of the movie or episode with watch key [key].
  DownloadItem? doneFor(String key) {
    final item = forWatchKey(key);
    return item != null && item.isDone ? item : null;
  }

  DownloadItem? get running {
    for (final item in items) {
      if (item.status == DownloadStatus.running) return item;
    }
    return null;
  }
}

/// Something the user should hear about from the downloads, shown in a
/// snack bar.
@immutable
final class DownloadNotice {
  const DownloadNotice(this.serial, this.text);

  final int serial;
  final String text;
}

/// The latest [DownloadNotice]; null before the first.
final downloadNoticeProvider =
    NotifierProvider<DownloadNotices, DownloadNotice?>(DownloadNotices.new);

class DownloadNotices extends Notifier<DownloadNotice?> {
  var _serial = 0;

  @override
  DownloadNotice? build() => null;

  void show(String text) => state = DownloadNotice(++_serial, text);
}

/// The downloads of the active provider.
final downloadsProvider = NotifierProvider<DownloadsController, DownloadsState>(
  DownloadsController.new,
);

/// The downloads list and queue of the active provider: one download at a
/// time, in order, while the app is open; partial files resume on the
/// next start. The list is saved per provider account.
class DownloadsController extends Notifier<DownloadsState> {
  /// How often waiting archive programmes and the disk are checked.
  static const checkInterval = Duration(seconds: 30);

  DownloadQueue? _queue;
  DownloadsStore? _store;
  Future<void> _saving = Future.value();
  String _savedShape = '';
  DateTime _savedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final _warned = <String>{};
  final _restartNoted = <String>{};

  @override
  DownloadsState build() {
    final key = ref.watch(providerKeyProvider);
    if (key == null) return const DownloadsState(loaded: true);
    final store = _store = ref.watch(downloadsStoreProvider)(key);
    Timer? timer;
    ref.onDispose(() {
      timer?.cancel();
      final queue = _queue;
      _queue = null;
      if (queue != null) unawaited(queue.dispose());
    });
    unawaited(
      _load(store).then((_) {
        if (!ref.mounted || !identical(store, _store)) return;
        timer = Timer.periodic(checkInterval, (_) => _check());
      }),
    );
    return const DownloadsState();
  }

  Future<void> _load(DownloadsStore store) async {
    List<DownloadItem> saved;
    try {
      saved = await store.load();
    } catch (e) {
      debugPrint('Could not read the downloads list (${e.runtimeType})');
      saved = const [];
    }
    if (!ref.mounted || !identical(store, _store)) return;
    final items = [
      for (final item in saved)
        // A recording still running when the app closed ended there.
        if (item.status == DownloadStatus.recording)
          item.copyWith(
            status: DownloadStatus.done,
            message: () => 'Stopped early: the app was closed.',
            bytes: _sizeOf(item.path) ?? item.bytes,
            finishedAt: () => item.finishedAt ?? _now,
          )
        else
          item,
    ];
    final queue = _queue = DownloadQueue(
      guard: ref.read(streamGuardProvider),
      run: (item, control, onProgress) =>
          ref.read(transferRunnerProvider)(item, control, onProgress),
      clock: () => _now,
      beforeStart: _checkBeforeStart,
      items: items,
    );
    queue.changes.listen((_) => _sync(queue));
    _sync(queue);
    queue.pump();
  }

  DateTime get _now => ref.read(clockProvider.notifier).now().toUtc();

  /// Completes when everything changed so far is saved.
  @visibleForTesting
  Future<void> get saved => _saving;

  void _sync(DownloadQueue queue) {
    if (!ref.mounted || !identical(queue, _queue)) return;
    final items = queue.items;
    for (final item in items) {
      if (item.message == DownloadNotes.restarted &&
          _restartNoted.add(item.id)) {
        ref
            .read(downloadNoticeProvider.notifier)
            .show(
              "Couldn't resume “${downloadName(item)}”: "
              'the server started it again from the beginning.',
            );
      }
    }
    state = DownloadsState(
      items: items,
      speed: queue.speed,
      timeLeft: queue.timeLeft,
      loaded: true,
    );
    _save(items);
  }

  /// Saves on every change of the list or a status, and progress at most
  /// every few seconds.
  void _save(List<DownloadItem> items) {
    final store = _store;
    if (store == null) return;
    final shape = items.map((i) => '${i.id}:${i.status.name}').join(',');
    final now = DateTime.now();
    if (shape == _savedShape &&
        now.difference(_savedAt) < const Duration(seconds: 5)) {
      return;
    }
    _savedShape = shape;
    _savedAt = now;
    _saving = _saving.then((_) async {
      try {
        await store.save(items);
      } catch (e) {
        debugPrint('Could not save the downloads list (${e.runtimeType})');
      }
    });
  }

  SpacePolicy get _policy =>
      (ref.read(appSettingsProvider).value ?? const AppSettings()).spacePolicy;

  String get _minFreeText => formatGb(_policy.minFree);

  Future<String?> _checkBeforeStart(DownloadItem item) async {
    final free = await ref
        .read(freeSpaceProvider)
        .at(File(item.path).parent.path);
    if (free == null) return null;
    final total = item.totalBytes;
    final needed = total == null ? 0 : total - item.bytes;
    switch (_policy.check(free, needed: needed)) {
      case SpaceStatus.full:
        return needed > 0
            ? 'Not enough disk space: needs ${formatBytes(needed)}, '
                  '${formatBytes(free)} free, keeps $_minFreeText free.'
            : 'Paused: less than $_minFreeText free on the disk.';
      case SpaceStatus.low:
        _warnLow(item);
      case SpaceStatus.ok:
    }
    return null;
  }

  void _warnLow(DownloadItem item) {
    if (!_warned.add(item.id)) return;
    ref
        .read(downloadNoticeProvider.notifier)
        .show(
          'The disk is almost full: downloads pause at $_minFreeText free.',
        );
  }

  Future<void> _check() async {
    final queue = _queue;
    if (queue == null) return;
    queue.pump();
    final running = queue.running;
    if (running == null) return;
    final free = await ref
        .read(freeSpaceProvider)
        .at(File(running.path).parent.path);
    if (free == null || !ref.mounted) return;
    switch (_policy.check(free)) {
      case SpaceStatus.full:
        queue.pauseForSpace(
          'Paused: less than $_minFreeText free on the disk.',
        );
        ref
            .read(downloadNoticeProvider.notifier)
            .show(
              'Downloads paused: less than $_minFreeText free on the disk. '
              'What was saved is kept.',
            );
      case SpaceStatus.low:
        _warnLow(running);
      case SpaceStatus.ok:
    }
  }

  // Adding.

  String get _folder => ref.read(downloadFolderProvider);

  /// [relative] under the downloads folder, with a number added when the
  /// name is in use.
  String _pathFor(String relative) {
    final inList = {for (final i in state.items) i.path};
    return uniquePath(
      '$_folder/$relative',
      (p) =>
          inList.contains(p) ||
          File(p).existsSync() ||
          File('$p.part').existsSync(),
    );
  }

  String _newId() =>
      '${_now.microsecondsSinceEpoch.toRadixString(36)}'
      '${(state.items.length + 1).toRadixString(36)}';

  void _add(DownloadItem item) => _queue?.add(item);

  /// Queues [movie]; null when it is in the list already.
  DownloadItem? addMovie(Movie movie, ProviderTags tags) {
    final key = movieKey(movie.streamId);
    if (state.forWatchKey(key) != null) return null;
    final display = tags.display(movie.name);
    final ext = safeExtension(movie.containerExtension, fallback: 'mp4');
    final item = DownloadItem(
      id: _newId(),
      kind: DownloadKind.movie,
      title: display.title,
      label: display.label,
      year: movie.year,
      sourceId: '${movie.streamId}',
      extension: ext,
      path: _pathFor(moviePath(display.title, movie.year, ext)),
      posterUrl: movie.posterUrl,
      addedAt: _now,
    );
    _add(item);
    return item;
  }

  /// Queues [episode] of [info]; null when it is in the list already.
  DownloadItem? addEpisode(
    SeriesInfo info,
    Episode episode,
    ProviderTags tags,
  ) {
    if (state.forWatchKey(episodeKey(episode.id)) != null) return null;
    final series = info.series;
    final display = tags.display(series.name);
    final name = episodeDisplayTitle(series, episode, tags);
    final ownName = RegExp(r'^Episode \d+$').hasMatch(name) ? null : name;
    final ext = safeExtension(episode.containerExtension, fallback: 'mp4');
    final item = DownloadItem(
      id: _newId(),
      kind: DownloadKind.episode,
      title: display.title,
      label: display.label,
      year: series.year,
      seriesId: series.seriesId,
      season: episode.season,
      episode: episode.episodeNumber,
      episodeTitle: ownName,
      sourceId: episode.id,
      extension: ext,
      path: _pathFor(
        episodePath(
          display.title,
          episode.season,
          episode.episodeNumber,
          ownName,
          ext,
        ),
      ),
      posterUrl: episode.coverUrl ?? series.coverUrl,
      addedAt: _now,
    );
    _add(item);
    return item;
  }

  /// Queues the episodes of [season] not in the list yet; returns how many.
  int addSeason(SeriesInfo info, int season, ProviderTags tags) {
    var added = 0;
    for (final e in info.episodesForSeason(season)) {
      if (addEpisode(info, e, tags) != null) added++;
    }
    return added;
  }

  /// Queues [programme] of [channel] from the archive, with the margins
  /// from Settings. [start] and [stop] are real instants (the guide's
  /// shift applied); [localStart] is the start in the guide's time zone,
  /// for the file name.
  DownloadItem addReplay({
    required LiveStream channel,
    required String programme,
    required DateTime start,
    required DateTime stop,
    required DateTime localStart,
  }) {
    final settings = ref.read(appSettingsProvider).value ?? const AppSettings();
    final clip = ReplayClip.forProgramme(
      start: start,
      stop: stop,
      startMargin: settings.startMargin,
      endMargin: settings.endMargin,
      window: ReplayWindow(channel.archiveDays),
      now: _now,
    );
    final name = withoutReplayMark(channel.name);
    final item = DownloadItem(
      id: _newId(),
      kind: DownloadKind.replay,
      title: name,
      programme: programme,
      sourceId: channel.id,
      extension: 'ts',
      from: clip.from,
      to: clip.to,
      path: _pathFor(recordingPath(name, programme, localStart, 'ts')),
      posterUrl: channel.logoUrl,
      addedAt: _now,
    );
    _add(item);
    return item;
  }

  /// A new recording entry of [channel] from [from]; its file is
  /// [DownloadItem.path].
  DownloadItem addRecording({
    required LiveStream channel,
    required String? programme,
    required DateTime from,
    required DateTime plannedEnd,
    required DateTime localStart,
  }) {
    final name = channel.hasReplay
        ? withoutReplayMark(channel.name)
        : channel.name;
    final item = DownloadItem(
      id: _newId(),
      kind: DownloadKind.recording,
      title: name,
      programme: programme,
      sourceId: channel.id,
      extension: 'ts',
      from: from,
      to: plannedEnd,
      path: _pathFor(recordingPath(name, programme, localStart, 'ts')),
      posterUrl: channel.logoUrl,
      addedAt: _now,
      status: DownloadStatus.recording,
    );
    _add(item);
    return item;
  }

  /// Marks recording [id] as finished at [end], with [note] if it stopped
  /// early.
  void finishRecording(String id, {required DateTime end, String? note}) {
    final item = state.byId(id);
    if (item == null) return;
    _queue?.update(
      item.copyWith(
        status: DownloadStatus.done,
        to: end,
        bytes: _sizeOf(item.path) ?? item.bytes,
        message: () => note,
        finishedAt: () => end,
      ),
    );
  }

  /// Updates the saved size of recording [id].
  void recordingProgress(String id, int bytes) {
    final item = state.byId(id);
    if (item == null || item.bytes == bytes) return;
    _queue?.update(item.copyWith(bytes: bytes));
  }

  // Controlling.

  void pause(String id) => _queue?.pause(id);

  void resume(String id) {
    _warned.remove(id);
    _restartNoted.remove(id);
    _queue?.resume(id);
  }

  /// Pauses the running download so the player can use the stream; it
  /// continues when the player stops.
  void pauseForPlayback() => _queue?.pauseForPlayback();

  /// Takes [id] out of the list and deletes its file and partial file.
  Future<void> remove(String id) async {
    final item = await _queue?.remove(id);
    if (item == null) return;
    for (final path in [item.path, item.partPath]) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException catch (e) {
        debugPrint('Could not delete a download (${e.runtimeType})');
      }
    }
  }

  /// The finished file of the movie or episode with watch key [key], if
  /// it is still on disk.
  String? localFile(String key) {
    final item = state.doneFor(key);
    if (item == null || !File(item.path).existsSync()) return null;
    return item.path;
  }

  static int? _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return null;
    }
  }
}

/// The name of [item] in messages: the movie, `Show S01E02`, or the
/// programme.
String downloadName(DownloadItem item) => switch (item.kind) {
  DownloadKind.movie => item.title,
  DownloadKind.episode =>
    '${item.title} ${formatEpisodeCode(item.season ?? 0, item.episode ?? 0)}',
  DownloadKind.replay || DownloadKind.recording => item.programme ?? item.title,
};

/// [_FileDownloadsStore] in the app support directory, resolved lazily.
class _FileDownloadsStore implements DownloadsStore {
  _FileDownloadsStore(this._key);

  final String _key;

  Future<DownloadsStore> get _store async => JsonFileDownloadsStore(
    File(
      '${(await getApplicationSupportDirectory()).path}/downloads/$_key.json',
    ),
  );

  @override
  Future<List<DownloadItem>> load() async => (await _store).load();

  @override
  Future<void> save(List<DownloadItem> items) async =>
      (await _store).save(items);
}
