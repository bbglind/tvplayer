import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A [Process] that never really runs; [exit] or [kill] ends it.
class FakeProcess implements Process {
  final _exit = Completer<int>();
  final killSignals = <ProcessSignal>[];

  void exit([int code = 0]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    exit(-15);
    return true;
  }

  @override
  int get pid => 0;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);
}

/// Stands in for mpv: binds the `--input-ipc-server` socket, records
/// commands, replies success and quits on `quit`.
class FakeMpv {
  FakeMpv(this.arguments);

  final List<String> arguments;
  final process = FakeProcess();
  final commands = <List<Object?>>[];

  /// Values returned for `get_property`; missing ones reply with an error,
  /// like mpv for an unavailable property.
  final properties = <String, Object?>{};

  /// Commands sent with `async`, in order.
  final asyncCommands = <List<Object?>>[];

  /// Command names mpv refuses (replies with an error).
  final refused = <String>{};

  /// Command names that, sent `async`, get no reply until they end (like a
  /// continuous `dump-cache`).
  final longRunning = <String>{'dump-cache'};
  final _clients = <Socket>[];
  ServerSocket? _server;
  final _loaded = Completer<void>();

  /// Completes once `loadfile` was received.
  Future<void> get loaded => _loaded.future;

  String get ipcPath => arguments
      .firstWhere((a) => a.startsWith('--input-ipc-server='))
      .substring('--input-ipc-server='.length);

  Future<void> listen() async {
    final server = _server = await ServerSocket.bind(
      InternetAddress(ipcPath, type: InternetAddressType.unix),
      0,
    );
    server.listen((client) {
      _clients.add(client);
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _onCommand(client, line));
    });
    unawaited(process.exitCode.then((_) => _close()));
  }

  void _onCommand(Socket client, String line) {
    final msg = jsonDecode(line) as Map<String, Object?>;
    final command = (msg['command']! as List).cast<Object?>();
    commands.add(command);
    final isAsync = msg['async'] == true;
    if (isAsync) asyncCommands.add(command);
    if (refused.contains(command.first)) {
      client.write(
        '${jsonEncode({'request_id': msg['request_id'], 'error': 'error running command'})}\n',
      );
      return;
    }
    if (isAsync && longRunning.contains(command.first)) return;
    final isGet = command.first == 'get_property';
    final known = !isGet || properties.containsKey(command[1]);
    client.write(
      '${jsonEncode({'request_id': msg['request_id'], 'error': known ? 'success' : 'property unavailable', 'data': isGet ? properties[command[1]] : null})}\n',
    );
    if (command.first == 'loadfile' && !_loaded.isCompleted) {
      _loaded.complete();
    }
    if (command.first == 'quit') process.exit();
  }

  void send(Map<String, Object?> event) {
    for (final c in _clients) {
      c.write('${jsonEncode(event)}\n');
    }
  }

  Future<void> _close() async {
    for (final c in _clients) {
      await c.close();
    }
    await _server?.close();
  }
}
