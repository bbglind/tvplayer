/// Bytes in a gigabyte, as shown in the UI (decimal, like file managers).
const bytesPerGb = 1000 * 1000 * 1000;

enum SpaceStatus {
  /// Enough room.
  ok,

  /// Close to the minimum: warn.
  low,

  /// At or below the minimum: stop, keeping what was saved.
  full,
}

/// Keeps at least [minFree] bytes free on the disk of the downloads.
final class SpacePolicy {
  const SpacePolicy(this.minFree, {this.warnMargin = bytesPerGb});

  final int minFree;

  /// Warn this much before the minimum is reached.
  final int warnMargin;

  /// The state with [free] bytes free and [needed] bytes still to be
  /// written (0 when unknown).
  SpaceStatus check(int free, {int needed = 0}) {
    final left = free - needed;
    if (left < minFree) return SpaceStatus.full;
    if (left < minFree + warnMargin) return SpaceStatus.low;
    return SpaceStatus.ok;
  }
}

/// A transfer rate over the last [window], from progress samples.
final class TransferRate {
  TransferRate({this.window = const Duration(seconds: 5)});

  final Duration window;
  final _samples = <(DateTime, int)>[];

  /// Records that [bytes] were saved in total at [at].
  void add(DateTime at, int bytes) {
    _samples.add((at, bytes));
    while (_samples.length > 2 && at.difference(_samples[1].$1) >= window) {
      _samples.removeAt(0);
    }
  }

  void reset() => _samples.clear();

  /// Bytes per second; null until there are two samples.
  double? get bytesPerSecond {
    if (_samples.length < 2) return null;
    final (t0, b0) = _samples.first;
    final (t1, b1) = _samples.last;
    final ms = t1.difference(t0).inMilliseconds;
    if (ms <= 0) return null;
    return (b1 - b0) * 1000 / ms;
  }

  /// The time left for [remaining] bytes at the current rate.
  Duration? timeLeft(int remaining) {
    final rate = bytesPerSecond;
    if (rate == null || rate <= 0) return null;
    return Duration(seconds: (remaining / rate).ceil());
  }
}
