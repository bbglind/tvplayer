import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  test('hands out one stream by default', () {
    final guard = StreamGuard();
    final play = guard.tryAcquire(StreamUse.playback);
    expect(play, isNotNull);
    expect(guard.available, isFalse);
    expect(guard.tryAcquire(StreamUse.download), isNull);
    expect(guard.holds(StreamUse.playback), isTrue);
    play!.release();
    expect(guard.available, isTrue);
    expect(guard.tryAcquire(StreamUse.download), isNotNull);
  });

  test('release is idempotent and doesn\'t free another lease', () {
    final guard = StreamGuard();
    final first = guard.tryAcquire(StreamUse.download)!;
    first.release();
    final second = guard.tryAcquire(StreamUse.playback)!;
    first.release();
    expect(guard.holders, [second]);
    expect(first.released, isTrue);
  });

  test('the limit comes from a function, at least 1', () {
    var limit = 2;
    final guard = StreamGuard(limit: () => limit);
    expect(guard.tryAcquire(StreamUse.playback), isNotNull);
    expect(guard.tryAcquire(StreamUse.download), isNotNull);
    expect(guard.tryAcquire(StreamUse.download), isNull);
    limit = 0;
    expect(guard.limit, 1);
  });

  test('reports changes', () {
    final guard = StreamGuard();
    var changes = 0;
    guard.changes.listen((_) => changes++);
    final lease = guard.tryAcquire(StreamUse.playback)!;
    lease.release();
    lease.release();
    expect(changes, 2);
  });
}
