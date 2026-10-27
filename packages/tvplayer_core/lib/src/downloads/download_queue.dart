import 'dart:async';

import '../streams/stream_guard.dart';
import 'disk_space.dart';
import 'download_item.dart';
import 'http_download.dart';

/// Runs one download: writes [item] to its path, reporting progress, until
/// it is done, fails or [control] stops it.
typedef TransferRunner =
    Future<TransferResult> Function(
      DownloadItem item,
      TransferControl control,
      void Function(TransferProgress progress) onProgress,
    );

/// Checked before a download starts: a message when it can't start for
/// lack of disk space, else null.
typedef StartCheck = Future<String?> Function(DownloadItem item);

/// Notes shown on a download.
abstract final class DownloadNotes {
  static const restarted =
      "Couldn't resume: the server started it again from the beginning.";
}

/// The downloads queue: one download at a time, in order, only while it
/// holds the provider stream from [guard].
///
/// Pausing for playback gives the stream back at once; the download goes
/// on when playback lets go of the stream. Pausing the running download
/// by the user pauses the whole queue ([paused]), and a pause for lack of
/// disk space holds it too: nothing starts until [resume] or [resumeAll].
/// Archive programmes
/// whose end hasn't passed yet wait for it ([DownloadStatus.waiting]);
/// [pump] (called on changes and periodically by the owner) starts them.
final class DownloadQueue {
  DownloadQueue({
    required this.guard,
    required TransferRunner run,
    required DateTime Function() clock,
    StartCheck? beforeStart,
    Iterable<DownloadItem> items = const [],
    bool paused = false,
  }) : _run = run,
       _paused = paused,
       _clock = clock,
       _beforeStart = beforeStart,
       _items = [for (final item in items) _restored(item)] {
    _guardChanges = guard.changes.listen((_) => scheduleMicrotask(_onGuard));
  }

  final StreamGuard guard;
  final TransferRunner _run;
  final DateTime Function() _clock;
  final StartCheck? _beforeStart;
  final List<DownloadItem> _items;
  final _changes = StreamController<void>.broadcast();
  late final StreamSubscription<void> _guardChanges;
  _Active? _active;
  final _rate = TransferRate();

  /// Set after a pause for lack of space: nothing starts by itself until
  /// the user resumes a download.
  bool _heldForSpace = false;

  /// Set when the user pauses the running download or the whole queue.
  bool _paused;

  /// The download [resume] asked for, started before the others.
  String? _startFirst;
  bool _disposed = false;

  /// After a restart a running download continues from the queue, and
  /// one paused for playback no longer waits for it.
  static DownloadItem _restored(DownloadItem item) => switch (item.status) {
    DownloadStatus.running => item.copyWith(status: DownloadStatus.queued),
    DownloadStatus.paused when item.pauseReason == PauseReason.playback =>
      item.copyWith(status: DownloadStatus.queued, pauseReason: () => null),
    _ => item,
  };

  /// Whether the user paused the queue: nothing starts until a resume.
  bool get paused => _paused;

  /// All entries, in queue order (finished ones included).
  List<DownloadItem> get items => List.unmodifiable(_items);

  /// Fires after any change, progress included.
  Stream<void> get changes => _changes.stream;

  /// The download running now.
  DownloadItem? get running => switch (_active) {
    final a? => byId(a.id),
    null => null,
  };

  /// Bytes per second of the running download.
  double? get speed => _active == null ? null : _rate.bytesPerSecond;

  /// The time left of the running download, when its size is known.
  Duration? get timeLeft {
    final item = running;
    final total = item?.totalBytes;
    if (item == null || total == null) return null;
    return _rate.timeLeft(total - item.bytes);
  }

  DownloadItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Adds [item] at the end of the queue (or as it is, for a finished
  /// recording) and starts it when it is its turn.
  void add(DownloadItem item) {
    _items.removeWhere((i) => i.id == item.id);
    _items.add(item);
    _changed();
    pump();
  }

  /// Whether [item] may start at [now]: an archive programme only once its
  /// end (with the margin) has passed.
  static bool _isReady(DownloadItem item, DateTime now) =>
      item.kind != DownloadKind.replay ||
      item.to == null ||
      !now.isBefore(item.to!);

  /// Replaces the entry with [item]'s id (recordings update theirs).
  void update(DownloadItem item) {
    final i = _items.indexWhere((e) => e.id == item.id);
    if (i < 0) return;
    _items[i] = item;
    _changed();
  }

  /// Pauses [id] until the user resumes it; when it is the running
  /// download, the whole queue pauses.
  void pause(String id) {
    if (_active?.id == id) _paused = true;
    _pause(id, PauseReason.user);
  }

  /// Pauses the queue, with the running download, until [resumeAll] or
  /// [resume].
  void pauseAll() {
    _paused = true;
    final item = running;
    if (item != null) _pause(item.id, PauseReason.user);
    _changed();
  }

  /// Puts the downloads paused by the user or for lack of space back in
  /// the queue and starts it again.
  void resumeAll() {
    _paused = false;
    _heldForSpace = false;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.status == DownloadStatus.paused &&
          item.pauseReason != PauseReason.playback) {
        _items[i] = item.copyWith(
          status: DownloadStatus.queued,
          pauseReason: () => null,
          message: () => null,
        );
      }
    }
    _changed();
    pump();
  }

  /// Pauses the running download for lack of disk space, keeping what was
  /// saved; nothing starts by itself afterwards.
  void pauseForSpace(String message) {
    final item = running;
    _heldForSpace = true;
    if (item != null) _pause(item.id, PauseReason.lowSpace, message: message);
  }

  /// Pauses the running download and gives its stream to the player. It
  /// continues when the player gives the stream back.
  void pauseForPlayback() {
    final item = running;
    if (item != null) _pause(item.id, PauseReason.playback);
  }

  void _pause(String id, PauseReason reason, {String? message}) {
    final item = byId(id);
    if (item == null || !item.isPending) return;
    if (item.status == DownloadStatus.failed) return;
    update(
      item.copyWith(
        status: DownloadStatus.paused,
        pauseReason: () => reason,
        message: message == null ? null : () => message,
      ),
    );
    final active = _active;
    if (active != null && active.id == id) {
      active.control.stop();
      active.lease.release();
    }
  }

  /// Puts a paused or failed download back in the queue and starts the
  /// queue again, with [id] first.
  void resume(String id) {
    final item = byId(id);
    if (item == null) return;
    if (item.status != DownloadStatus.paused &&
        item.status != DownloadStatus.failed) {
      return;
    }
    _heldForSpace = false;
    _paused = false;
    _startFirst = id;
    update(
      item.copyWith(
        status: DownloadStatus.queued,
        pauseReason: () => null,
        message: () => null,
      ),
    );
    pump();
  }

  /// Takes [id] out of the list, stopping it first when it runs, and
  /// returns it so its files can be deleted (after the transfer has let
  /// go of them).
  Future<DownloadItem?> remove(String id) async {
    final item = byId(id);
    if (item == null) return null;
    _items.removeWhere((i) => i.id == id);
    final active = _active;
    if (active != null && active.id == id) {
      active.control.stop();
      active.lease.release();
      await active.finished.future;
    }
    _changed();
    pump();
    return item;
  }

  /// Starts the next download when none runs and the stream is free;
  /// archive programmes whose time has come leave the waiting state.
  void pump() {
    if (_disposed) return;
    final now = _clock();
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      final ready = _isReady(item, now);
      if (item.status == DownloadStatus.waiting && ready) {
        _items[i] = item.copyWith(status: DownloadStatus.queued);
        _changed();
      } else if (item.status == DownloadStatus.queued && !ready) {
        // E.g. restored, or put back by resume before its time.
        _items[i] = item.copyWith(status: DownloadStatus.waiting);
        _changed();
      }
    }
    if (_active != null || _heldForSpace || _paused) return;
    bool startable(DownloadItem? item) =>
        item != null &&
        item.status == DownloadStatus.queued &&
        item.kind != DownloadKind.recording;
    var next = switch (_startFirst) {
      final id? => byId(id),
      null => null,
    };
    if (!startable(next)) {
      next = null;
      for (final item in _items) {
        if (startable(item)) {
          next = item;
          break;
        }
      }
    }
    if (next == null) return;
    final lease = guard.tryAcquire(StreamUse.download);
    if (lease == null) return;
    _startFirst = null;
    unawaited(_start(next, lease));
  }

  Future<void> _start(DownloadItem item, StreamLease lease) async {
    final control = TransferControl();
    final active = _active = _Active(item.id, control, lease);
    _rate.reset();
    try {
      final full = await _beforeStart?.call(item);
      if (full != null) {
        _heldForSpace = true;
        if (byId(item.id) case final current?) {
          update(
            current.copyWith(
              status: DownloadStatus.paused,
              pauseReason: () => PauseReason.lowSpace,
              message: () => full,
            ),
          );
        }
        return;
      }
      if (control.stopped) return;
      if (byId(item.id) case final current?) {
        update(current.copyWith(status: DownloadStatus.running));
      }
      final result = await _run(item, control, (p) {
        final current = byId(item.id);
        if (current == null) return;
        _rate.add(_clock(), p.bytes);
        update(
          current.copyWith(
            bytes: p.bytes,
            totalBytes: p.total == null ? null : () => p.total,
            message: p.restarted ? () => DownloadNotes.restarted : null,
          ),
        );
      });
      final current = byId(item.id);
      if (current == null) return;
      switch (result) {
        case TransferDone(:final bytes):
          update(
            current.copyWith(
              status: DownloadStatus.done,
              bytes: bytes,
              totalBytes: () => bytes,
              pauseReason: () => null,
              finishedAt: () => _clock(),
            ),
          );
        case TransferFailed(:final message, :final bytes):
          if (current.status == DownloadStatus.running) {
            update(
              current.copyWith(
                status: DownloadStatus.failed,
                message: () => message,
                bytes: bytes > 0 ? bytes : null,
              ),
            );
          }
        case TransferStopped(:final bytes):
          update(current.copyWith(bytes: bytes));
      }
    } finally {
      lease.release();
      if (identical(_active, active)) _active = null;
      active.finished.complete();
      _changed();
      scheduleMicrotask(pump);
    }
  }

  void _onGuard() {
    if (_disposed) return;
    if (!guard.holds(StreamUse.playback)) {
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item.status == DownloadStatus.paused &&
            item.pauseReason == PauseReason.playback) {
          _items[i] = item.copyWith(
            status: DownloadStatus.queued,
            pauseReason: () => null,
          );
          _changed();
        }
      }
    }
    pump();
  }

  void _changed() {
    if (!_disposed) _changes.add(null);
  }

  /// Stops the running download (it resumes next time) and lets go of
  /// the stream.
  Future<void> dispose() async {
    final active = _active;
    _disposed = true;
    await _guardChanges.cancel();
    if (active != null) {
      active.control.stop();
      active.lease.release();
      await active.finished.future;
    }
    await _changes.close();
  }
}

final class _Active {
  _Active(this.id, this.control, this.lease);

  final String id;
  final TransferControl control;
  final StreamLease lease;
  final finished = Completer<void>();
}
