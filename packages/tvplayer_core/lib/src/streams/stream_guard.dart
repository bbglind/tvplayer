import 'dart:async';

/// What holds a provider stream.
enum StreamUse {
  /// The player, live or on demand. A recording made from what the player
  /// plays rides on this use and needs no stream of its own.
  playback,

  /// A download in the downloads queue.
  download,
}

/// One provider stream held by [use]; [release] gives it back.
final class StreamLease {
  StreamLease._(this._guard, this.use);

  final StreamGuard _guard;
  final StreamUse use;
  bool _released = false;

  bool get released => _released;

  /// Gives the stream back. Calling it again does nothing.
  void release() {
    if (_released) return;
    _released = true;
    _guard._release(this);
  }
}

/// The one place that hands out the provider's streams: playback and
/// downloads both have to ask it. Providers limit how many streams an
/// account may open at once; [limit] says how many (1 unless an account
/// says otherwise, e.g. from its `max_connections`).
///
/// Playing a downloaded file uses no provider stream and doesn't ask.
final class StreamGuard {
  StreamGuard({int Function()? limit}) : _limit = limit ?? (() => 1);

  final int Function() _limit;
  final _holders = <StreamLease>[];
  final _changes = StreamController<void>.broadcast(sync: true);

  /// The leases held now, oldest first.
  List<StreamLease> get holders => List.unmodifiable(_holders);

  /// How many streams may be open at once (at least 1).
  int get limit => _limit() < 1 ? 1 : _limit();

  /// Whether another stream may be opened now.
  bool get available => _holders.length < limit;

  /// Whether a lease for [use] is held.
  bool holds(StreamUse use) => _holders.any((l) => l.use == use);

  /// Fires after a lease is taken or released.
  Stream<void> get changes => _changes.stream;

  /// A lease for [use], or null while every stream is taken.
  StreamLease? tryAcquire(StreamUse use) {
    if (!available) return null;
    final lease = StreamLease._(this, use);
    _holders.add(lease);
    _changes.add(null);
    return lease;
  }

  void _release(StreamLease lease) {
    if (_holders.remove(lease)) _changes.add(null);
  }
}
