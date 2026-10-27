import 'dart:async';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// A transfer the test finishes by hand.
class _Run {
  _Run(this.item, this.control, this.progress);

  final DownloadItem item;
  final TransferControl control;
  final void Function(TransferProgress) progress;
  final result = Completer<TransferResult>();
}

DownloadItem _item(
  String id, {
  DownloadKind kind = DownloadKind.movie,
  DownloadStatus status = DownloadStatus.queued,
  PauseReason? pause,
  DateTime? from,
  DateTime? to,
}) => DownloadItem(
  id: id,
  kind: kind,
  title: 'Title $id',
  sourceId: id,
  extension: 'mkv',
  path: '/downloads/$id.mkv',
  addedAt: DateTime.utc(2026, 10, 27),
  status: status,
  pauseReason: pause,
  from: from,
  to: to,
);

void main() {
  late StreamGuard guard;
  late List<_Run> runs;
  late DateTime now;
  late DownloadQueue queue;
  String? spaceProblem;

  DownloadQueue make([
    List<DownloadItem> items = const [],
    bool paused = false,
  ]) => DownloadQueue(
    guard: guard,
    clock: () => now,
    items: items,
    paused: paused,
    beforeStart: (_) async => spaceProblem,
    run: (item, control, progress) {
      final run = _Run(item, control, progress);
      runs.add(run);
      control.onStop.then((_) {
        if (!run.result.isCompleted) {
          run.result.complete(const TransferStopped(10));
        }
      });
      return run.result.future;
    },
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    guard = StreamGuard();
    runs = [];
    now = DateTime.utc(2026, 10, 27, 20);
    spaceProblem = null;
    queue = make();
  });

  tearDown(() => queue.dispose());

  test('runs one download at a time, in order', () async {
    queue
      ..add(_item('a'))
      ..add(_item('b'));
    await settle();
    expect(runs.map((r) => r.item.id), ['a']);
    expect(queue.byId('a')!.status, DownloadStatus.running);
    expect(queue.byId('b')!.status, DownloadStatus.queued);
    expect(guard.holds(StreamUse.download), isTrue);

    runs.single.progress(const TransferProgress(50, 100));
    expect(queue.byId('a')!.fraction, 0.5);
    runs.single.result.complete(const TransferDone(100));
    await settle();
    await settle();
    expect(queue.byId('a')!.status, DownloadStatus.done);
    expect(queue.byId('a')!.finishedAt, now);
    expect(runs.map((r) => r.item.id), ['a', 'b']);
  });

  test("doesn't start while the player holds the stream", () async {
    final play = guard.tryAcquire(StreamUse.playback)!;
    queue.add(_item('a'));
    await settle();
    expect(runs, isEmpty);
    play.release();
    await settle();
    await settle();
    expect(runs.map((r) => r.item.id), ['a']);
  });

  test('pausing for playback frees the stream and resumes after it', () async {
    queue.add(_item('a'));
    await settle();
    queue.pauseForPlayback();
    expect(guard.available, isTrue);
    expect(queue.byId('a')!.pauseReason, PauseReason.playback);
    final play = guard.tryAcquire(StreamUse.playback)!;
    await settle();
    await settle();
    expect(runs, hasLength(1));
    expect(queue.byId('a')!.status, DownloadStatus.paused);

    play.release();
    await settle();
    await settle();
    expect(runs, hasLength(2));
    expect(queue.byId('a')!.status, DownloadStatus.running);
    expect(queue.paused, isFalse);
  });

  test('pausing the running download pauses the queue', () async {
    queue
      ..add(_item('a'))
      ..add(_item('b'));
    await settle();
    queue.pause('a');
    await settle();
    await settle();
    expect(queue.paused, isTrue);
    expect(queue.byId('a')!.status, DownloadStatus.paused);
    expect(queue.byId('b')!.status, DownloadStatus.queued);
    expect(runs.map((r) => r.item.id), ['a']);
    expect(guard.available, isTrue);

    // Playback ending doesn't resume it either.
    guard.tryAcquire(StreamUse.playback)!.release();
    await settle();
    await settle();
    expect(runs, hasLength(1));

    queue.resume('a');
    await settle();
    expect(queue.paused, isFalse);
    expect(runs.map((r) => r.item.id), ['a', 'a']);
    runs.last.result.complete(const TransferDone(1));
    await settle();
    await settle();
    expect(runs.map((r) => r.item.id), ['a', 'a', 'b']);
  });

  test('pausing a queued download skips it; the queue goes on', () async {
    queue
      ..add(_item('a'))
      ..add(_item('b'))
      ..add(_item('c'));
    await settle();
    queue.pause('b');
    runs.single.result.complete(const TransferDone(1));
    await settle();
    await settle();
    expect(queue.paused, isFalse);
    expect(queue.byId('b')!.status, DownloadStatus.paused);
    expect(runs.map((r) => r.item.id), ['a', 'c']);
  });

  test('resume starts that download first, then the rest in order', () async {
    final to = now.add(const Duration(minutes: 10));
    queue
      ..add(_item('r', kind: DownloadKind.replay, from: now, to: to))
      ..add(_item('a'))
      ..add(_item('b'));
    await settle();
    expect(runs.map((r) => r.item.id), ['a']);
    queue.pause('a');
    now = to;
    queue.pump();
    await settle();
    await settle();
    // Its time has come, but the queue is paused.
    expect(queue.byId('r')!.status, DownloadStatus.queued);
    expect(runs, hasLength(1));

    queue.resume('a');
    await settle();
    expect(runs.map((r) => r.item.id), ['a', 'a']);
    runs.last.result.complete(const TransferDone(1));
    await settle();
    await settle();
    runs.last.result.complete(const TransferDone(1));
    await settle();
    await settle();
    expect(runs.map((r) => r.item.id), ['a', 'a', 'r', 'b']);
  });

  test('pause all holds the queue; resume all goes on in order', () async {
    final play = guard.tryAcquire(StreamUse.playback)!;
    queue
      ..add(_item('a'))
      ..add(_item('b'));
    queue.pauseAll();
    play.release();
    await settle();
    await settle();
    expect(queue.paused, isTrue);
    expect(runs, isEmpty);
    expect(queue.byId('a')!.status, DownloadStatus.queued);

    queue.resumeAll();
    await settle();
    expect(runs.map((r) => r.item.id), ['a']);
    queue.pauseAll();
    await settle();
    await settle();
    expect(queue.byId('a')!.pauseReason, PauseReason.user);
    expect(runs, hasLength(1));

    queue.resumeAll();
    await settle();
    expect(queue.byId('a')!.status, DownloadStatus.running);
    expect(runs.map((r) => r.item.id), ['a', 'a']);
  });

  test('a paused queue stays paused after a restart', () async {
    await queue.dispose();
    queue = make([
      _item('a', status: DownloadStatus.paused, pause: PauseReason.user),
      _item('b'),
    ], true);
    queue.pump();
    await settle();
    expect(queue.paused, isTrue);
    expect(runs, isEmpty);
    queue.resumeAll();
    await settle();
    expect(runs.map((r) => r.item.id), ['a']);
  });

  test('lack of space pauses and holds the queue until resume', () async {
    spaceProblem = 'Not enough disk space.';
    queue
      ..add(_item('a'))
      ..add(_item('b'));
    await settle();
    await settle();
    expect(runs, isEmpty);
    expect(queue.byId('a')!.pauseReason, PauseReason.lowSpace);
    expect(queue.byId('a')!.message, 'Not enough disk space.');
    expect(queue.byId('b')!.status, DownloadStatus.queued);
    expect(guard.available, isTrue);

    spaceProblem = null;
    queue.pump();
    await settle();
    expect(runs, isEmpty);
    queue.resume('a');
    await settle();
    await settle();
    expect(runs.map((r) => r.item.id), ['a']);
    expect(queue.byId('a')!.message, isNull);

    queue.pauseForSpace('Less than 5 GB free.');
    await settle();
    await settle();
    expect(queue.byId('a')!.status, DownloadStatus.paused);
    expect(runs, hasLength(1));
  });

  test('a failure moves on to the next download', () async {
    queue
      ..add(_item('a'))
      ..add(_item('b'));
    await settle();
    runs.single.result.complete(
      const TransferFailed('The provider refused the download (HTTP 403).'),
    );
    await settle();
    await settle();
    expect(queue.byId('a')!.status, DownloadStatus.failed);
    expect(queue.byId('a')!.message, contains('HTTP 403'));
    expect(runs.map((r) => r.item.id), ['a', 'b']);
  });

  test('a restart is noted', () async {
    queue.add(_item('a'));
    await settle();
    runs.single.progress(const TransferProgress(0, 100, restarted: true));
    expect(queue.byId('a')!.message, DownloadNotes.restarted);
    runs.single.progress(const TransferProgress(10, 100));
    expect(queue.byId('a')!.message, DownloadNotes.restarted);
  });

  test('remove stops a running download first', () async {
    queue
      ..add(_item('a'))
      ..add(_item('b'));
    await settle();
    final removed = await queue.remove('a');
    expect(removed!.id, 'a');
    expect(runs.first.control.stopped, isTrue);
    expect(queue.byId('a'), isNull);
    await settle();
    await settle();
    expect(runs.map((r) => r.item.id), ['a', 'b']);
  });

  test('archive programmes wait until their end has passed', () async {
    final to = now.add(const Duration(minutes: 10));
    queue
      ..add(
        _item(
          'r',
          kind: DownloadKind.replay,
          from: now.subtract(const Duration(hours: 1)),
          to: to,
        ),
      )
      ..add(_item('a'));
    await settle();
    expect(queue.byId('r')!.status, DownloadStatus.waiting);
    expect(runs.map((r) => r.item.id), ['a']);
    runs.single.result.complete(const TransferDone(1));
    await settle();
    await settle();
    expect(runs, hasLength(1));

    now = to;
    queue.pump();
    await settle();
    expect(runs.map((r) => r.item.id), ['a', 'r']);
  });

  test('a restored archive programme still waits for its end', () async {
    await queue.dispose();
    final to = now.add(const Duration(minutes: 5));
    queue = make([_item('r', kind: DownloadKind.replay, from: now, to: to)]);
    queue.pump();
    await settle();
    expect(runs, isEmpty);
    expect(queue.byId('r')!.status, DownloadStatus.waiting);
    now = to;
    queue.pump();
    await settle();
    expect(runs.map((r) => r.item.id), ['r']);
  });

  test('restored entries continue from the queue', () async {
    await queue.dispose();
    queue = make([
      _item('done', status: DownloadStatus.done),
      _item('rec', kind: DownloadKind.recording, status: DownloadStatus.done),
      _item('play', status: DownloadStatus.paused, pause: PauseReason.playback),
      _item('user', status: DownloadStatus.paused, pause: PauseReason.user),
      _item('run', status: DownloadStatus.running),
    ]);
    expect(queue.byId('play')!.status, DownloadStatus.queued);
    expect(queue.byId('run')!.status, DownloadStatus.queued);
    expect(queue.byId('user')!.status, DownloadStatus.paused);
    queue.pump();
    await settle();
    expect(runs.map((r) => r.item.id), ['play']);
  });

  test('dispose stops the transfer and frees the stream', () async {
    queue.add(_item('a'));
    await settle();
    await queue.dispose();
    expect(runs.single.control.stopped, isTrue);
    expect(guard.available, isTrue);
    queue = make();
  });
}
