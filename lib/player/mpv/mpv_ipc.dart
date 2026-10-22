import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An mpv IPC command failed, or the connection closed before its reply.
class MpvIpcException implements Exception {
  const MpvIpcException(this.message);

  final String message;

  @override
  String toString() => 'MpvIpcException: $message';
}

/// An asynchronous message from mpv, e.g. `property-change` or `end-file`.
class MpvEvent {
  const MpvEvent(this.name, this.fields);

  final String name;

  /// The whole JSON message, including `event`.
  final Map<String, Object?> fields;

  /// `name` of a `property-change` event.
  String? get property => fields['name'] as String?;
  Object? get data => fields['data'];
}

/// Client for mpv's JSON IPC protocol over a Unix socket.
///
/// Commands may carry the stream URL (`loadfile`), so neither commands nor
/// replies are ever logged.
class MpvIpc {
  MpvIpc._(this._socket) {
    _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onDone, onError: (_) => _onDone());
  }

  /// Connects to [path], retrying while mpv has not created the socket yet.
  /// Gives up after [timeout], or as soon as [abort] completes.
  static Future<MpvIpc> connect(
    String path, {
    Duration timeout = const Duration(seconds: 5),
    Future<void>? abort,
  }) async {
    var aborted = false;
    abort?.whenComplete(() => aborted = true).ignore();
    final deadline = DateTime.now().add(timeout);
    final address = InternetAddress(path, type: InternetAddressType.unix);
    while (true) {
      try {
        return MpvIpc._(await Socket.connect(address, 0));
      } on SocketException {
        if (aborted) throw const MpvIpcException('mpv exited');
        if (DateTime.now().isAfter(deadline)) {
          throw const MpvIpcException('Timed out connecting to mpv');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  final Socket _socket;
  final _events = StreamController<MpvEvent>.broadcast();
  final _pending = <int, Completer<Object?>>{};
  var _nextRequestId = 1;
  final _done = Completer<void>();
  var _closed = false;

  Stream<MpvEvent> get events => _events.stream;

  /// Completes once the connection has closed and every message received
  /// before that has been delivered.
  Future<void> get done => _done.future;

  /// Sends [args] as a command and returns the reply's `data`. Throws
  /// [MpvIpcException] if mpv reports an error or the connection closes.
  Future<Object?> command(List<Object?> args) {
    if (_closed) {
      return Future.error(const MpvIpcException('Connection closed'));
    }
    final id = _nextRequestId++;
    final completer = _pending[id] = Completer<Object?>();
    _socket.write('${jsonEncode({'command': args, 'request_id': id})}\n');
    return completer.future;
  }

  /// Asks mpv to send `property-change` events for [name].
  Future<void> observeProperty(int id, String name) =>
      command(['observe_property', id, name]);

  void _onLine(String line) {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (message is! Map<String, Object?>) return;
    final event = message['event'];
    if (event is String) {
      _events.add(MpvEvent(event, message));
      return;
    }
    final id = message['request_id'];
    final completer = id is int ? _pending.remove(id) : null;
    if (completer == null) return;
    final error = message['error'];
    if (error == 'success') {
      completer.complete(message['data']);
    } else {
      completer.completeError(MpvIpcException('$error'));
    }
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    for (final c in _pending.values) {
      c.completeError(const MpvIpcException('Connection closed'));
    }
    _pending.clear();
    _events.close();
    _socket.destroy();
    _done.complete();
  }

  Future<void> close() async => _onDone();
}
