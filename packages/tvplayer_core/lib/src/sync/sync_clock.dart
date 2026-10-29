import 'dart:math';

import '../util/json.dart';
import 'sync_protocol.dart';

/// The change times of synced data: a hybrid logical clock.
///
/// [now] is the device time corrected by [offset] (the difference to the
/// sync server's clock), but never earlier than a time it gave out or saw
/// in synced data ([observe]). So a change made after seeing another
/// device's change always wins over it, even when this device's clock is
/// a little behind, and two changes on one device never share a time.
class SyncClock {
  SyncClock({
    DateTime Function()? device,
    Duration offset = Duration.zero,
    int last = 0,
  }) : _device = device ?? DateTime.now,
       _offset = offset,
       _last = last;

  final DateTime Function() _device;
  Duration _offset;
  int _last;

  /// Times seen further ahead than this are ignored by [observe], so one
  /// device with a broken clock can't drag every later change along.
  static const maxAhead = syncMaxAhead;

  /// Server time minus device time.
  Duration get offset => _offset;

  /// The latest time given out or observed.
  int get last => _last;

  /// The device's own time, uncorrected, in milliseconds since the epoch.
  int get deviceTime => _device().millisecondsSinceEpoch;

  int get _corrected => deviceTime + _offset.inMilliseconds;

  /// A new change time (UTC), later than any before.
  DateTime now() {
    _last = max(_corrected, _last + 1);
    return DateTime.fromMillisecondsSinceEpoch(_last, isUtc: true);
  }

  /// Notes the time [t] of a record from another device.
  void observe(int t) {
    if (t > _last && t <= _corrected + maxAhead.inMilliseconds) _last = t;
  }

  /// Sets the server time offset from a request that started at device
  /// time [sent], ended at [received] and was answered at [serverTime]
  /// (all in milliseconds since the epoch).
  void calibrate({
    required int sent,
    required int received,
    required int serverTime,
  }) {
    _offset = Duration(milliseconds: serverTime - (sent + received) ~/ 2);
  }

  /// Whether [t] lies so far ahead of the corrected time that it must come
  /// from a wrong clock.
  bool isFarAhead(int t) => t > _corrected + maxAhead.inMilliseconds;

  /// Takes over a saved clock ([toJson]), keeping times given out since.
  void restore(Object? json) {
    final map = readMap(json);
    _offset = Duration(milliseconds: readInt(map?['offset']) ?? 0);
    _last = max(_last, readInt(map?['last']) ?? 0);
  }

  Map<String, Object?> toJson() => {
    'offset': _offset.inMilliseconds,
    'last': _last,
  };

  /// Inverse of [toJson]; an unreadable value gives a fresh clock.
  factory SyncClock.fromJson(Object? json, {DateTime Function()? device}) {
    final map = readMap(json);
    return SyncClock(
      device: device,
      offset: Duration(milliseconds: readInt(map?['offset']) ?? 0),
      last: readInt(map?['last']) ?? 0,
    );
  }
}
