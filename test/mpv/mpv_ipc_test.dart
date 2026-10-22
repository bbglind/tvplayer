import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/mpv_ipc.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mpv_ipc_test');
    path = '${dir.path}/s.sock';
  });

  tearDown(() => dir.delete(recursive: true));

  /// Binds [path] and hands each received JSON line to [onMessage].
  Future<ServerSocket> serve(
    void Function(Socket client, Map<String, Object?> msg) onMessage,
  ) async {
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    server.listen((client) {
      client
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (l) => onMessage(client, jsonDecode(l) as Map<String, Object?>),
          );
    });
    addTearDown(server.close);
    return server;
  }

  void reply(Socket client, Map<String, Object?> msg) =>
      client.write('${jsonEncode(msg)}\n');

  test('sends commands and returns reply data', () async {
    final received = <Object?>[];
    await serve((client, msg) {
      received.add(msg['command']);
      reply(client, {
        'request_id': msg['request_id'],
        'error': 'success',
        'data': 42.5,
      });
    });
    final ipc = await MpvIpc.connect(path);
    expect(await ipc.command(['get_property', 'time-pos']), 42.5);
    expect(received, [
      ['get_property', 'time-pos'],
    ]);
    await ipc.close();
  });

  test('mpv errors fail the command', () async {
    await serve((client, msg) {
      reply(client, {
        'request_id': msg['request_id'],
        'error': 'property unavailable',
      });
    });
    final ipc = await MpvIpc.connect(path);
    await expectLater(
      ipc.command(['get_property', 'duration']),
      throwsA(isA<MpvIpcException>()),
    );
    await ipc.close();
  });

  test('delivers events, including property changes', () async {
    await serve((client, msg) {
      reply(client, {
        'event': 'property-change',
        'id': 1,
        'name': 'pause',
        'data': true,
      });
      reply(client, {'request_id': msg['request_id'], 'error': 'success'});
    });
    final ipc = await MpvIpc.connect(path);
    final event = ipc.events.first;
    await ipc.observeProperty(1, 'pause');
    final e = await event;
    expect(e.name, 'property-change');
    expect(e.property, 'pause');
    expect(e.data, true);
    await ipc.close();
  });

  test('retries until the socket exists', () async {
    final connecting = MpvIpc.connect(path);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await serve((_, _) {});
    final ipc = await connecting;
    await ipc.close();
  });

  test('gives up when aborted', () async {
    final abort = Completer<void>();
    final connecting = MpvIpc.connect(path, abort: abort.future);
    abort.complete();
    await expectLater(connecting, throwsA(isA<MpvIpcException>()));
  });

  test('pending commands fail when the connection closes', () async {
    await serve((client, _) => client.destroy());
    final ipc = await MpvIpc.connect(path);
    await expectLater(ipc.command(['quit']), throwsA(isA<MpvIpcException>()));
  });
}
