import 'dart:async';
import 'dart:math' as math;

/// Requests per second sent to TMDB, in total. TMDB allows more; this keeps
/// the app a polite client.
const tmdbRequestsPerSecond = 10;

/// Requests to TMDB running at the same time, so slow answers don't lower
/// the rate.
const tmdbMaxInFlight = 4;

/// Spaces tasks evenly at [perSecond] with at most [maxInFlight] running,
/// and holds every task back while [backOff] asks for a pause (an HTTP 429).
class RateLimiter {
  RateLimiter({
    num perSecond = tmdbRequestsPerSecond,
    this.maxInFlight = tmdbMaxInFlight,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  }) : _interval = Duration(microseconds: 1000000 ~/ perSecond),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  final int maxInFlight;
  final Duration _interval;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  /// Tasks take their turn one after the other through this chain.
  Future<void> _gate = Future.value();
  DateTime _nextStart = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _inFlight = 0;
  Completer<void>? _slotFreed;

  /// Runs [task] when its turn comes.
  Future<T> run<T>(Future<T> Function() task) async {
    final turn = _gate.then((_) => _waitTurn());
    _gate = turn;
    await turn;
    try {
      return await task();
    } finally {
      _inFlight--;
      final freed = _slotFreed;
      _slotFreed = null;
      freed?.complete();
    }
  }

  /// Starts no task before [delay] has passed.
  void backOff(Duration delay) {
    final until = _now().add(delay);
    if (until.isAfter(_blockedUntil)) _blockedUntil = until;
  }

  /// Whether a [backOff] is still running.
  bool get backingOff => _blockedUntil.isAfter(_now());

  Future<void> _waitTurn() async {
    while (true) {
      if (_inFlight >= maxInFlight) {
        await (_slotFreed ??= Completer<void>()).future;
        continue;
      }
      final now = _now();
      final next = _nextStart.isAfter(_blockedUntil)
          ? _nextStart
          : _blockedUntil;
      if (next.isAfter(now)) {
        await _sleep(next.difference(now));
        // A back-off may have come in meanwhile.
        continue;
      }
      _nextStart = now.add(_interval);
      _inFlight++;
      return;
    }
  }
}

/// The wait before retry number [attempt] (0 for the first): 1, 2, 4 … s,
/// at most [max].
Duration exponentialBackOff(
  int attempt, {
  Duration max = const Duration(seconds: 60),
}) {
  final seconds = math.pow(2, math.min(attempt, 16)).toInt();
  final delay = Duration(seconds: seconds);
  return delay > max ? max : delay;
}
