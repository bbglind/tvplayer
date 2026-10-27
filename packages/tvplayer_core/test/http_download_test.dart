import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// A loopback server sending [body], honouring `Range` unless told not to.
class _Server {
  _Server._(this._server);

  static Future<_Server> start() async =>
      _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
        .._listen();

  final HttpServer _server;
  // Big enough to pass dart:io's output buffer, so parts arrive early.
  List<int> body = List.generate(200000, (i) => i % 256);
  bool ranges = true;

  /// Answer every request with this status instead.
  int? status;

  /// Send a wrong start in `Content-Range`.
  bool wrongStart = false;

  /// Close the connection after this many bytes.
  int? cutAfter;

  /// Stop sending after this many bytes, keeping the connection open.
  int? hangAfter;
  final rangeHeaders = <String?>[];
  final paths = <String>[];

  Uri get url =>
      Uri.parse('http://127.0.0.1:${_server.port}/movie/user/pass/1.mkv');

  void _listen() => _server.listen((request) async {
    paths.add(request.uri.path);
    final response = request.response;
    if (request.uri.path == '/redirect') {
      response.redirect(url);
      return;
    }
    final range = request.headers.value('range');
    rangeHeaders.add(range);
    if (status case final s?) {
      response.statusCode = s;
      await response.close();
      return;
    }
    var start = 0;
    if (range != null && ranges) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (start >= body.length) {
        response
          ..statusCode = 416
          ..headers.set('content-range', 'bytes */${body.length}');
        await response.close();
        return;
      }
      response
        ..statusCode = 206
        ..headers.set(
          'content-range',
          'bytes ${wrongStart ? 0 : start}-${body.length - 1}/${body.length}',
        );
      if (wrongStart) start = 0;
    }
    final data = body.sublist(start);
    response.contentLength = data.length;
    if (hangAfter case final n?) {
      response.add(data.sublist(0, n));
      await response.flush();
      return; // never closes
    }
    if (cutAfter case final n?) {
      // Less than the stated length: dart:io drops the connection.
      response.add(data.sublist(0, n));
      await response.close().catchError((_) {});
      return;
    }
    response.add(data);
    await response.close();
  });

  Future<void> close() => _server.close(force: true);
}

void main() {
  late _Server server;
  late Directory dir;
  late String path;

  setUp(() async {
    server = await _Server.start();
    dir = await Directory.systemTemp.createTemp('download_test');
    path = '${dir.path}/Movies/Title (2020).mkv';
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  Future<TransferResult> run({
    Uri? url,
    TransferControl? control,
    List<TransferProgress>? progress,
    Duration idle = const Duration(seconds: 5),
  }) => HttpDownload(idleTimeout: idle, progressInterval: Duration.zero).run(
    url: url ?? server.url,
    path: path,
    control: control ?? TransferControl(),
    onProgress: progress?.add,
  );

  test('downloads into a part file and renames it at the end', () async {
    final progress = <TransferProgress>[];
    final result = await run(progress: progress);
    expect(result, isA<TransferDone>());
    expect((result as TransferDone).restarted, isFalse);
    expect(await File(path).readAsBytes(), server.body);
    expect(File('$path.part').existsSync(), isFalse);
    expect(progress.last.bytes, 200000);
    expect(progress.first.total, 200000);
    expect(server.rangeHeaders, [null]);
  });

  test('resumes a part file with a range request', () async {
    await File('$path.part').create(recursive: true);
    await File('$path.part').writeAsBytes(server.body.sublist(0, 400));
    final progress = <TransferProgress>[];
    final result = await run(progress: progress);
    expect(result, isA<TransferDone>());
    expect(server.rangeHeaders, ['bytes=400-']);
    expect(progress.first.bytes, 400);
    expect(progress.first.total, 200000);
    expect(progress.any((p) => p.restarted), isFalse);
    expect(await File(path).readAsBytes(), server.body);
  });

  test('starts again when the server ignores the range', () async {
    server.ranges = false;
    await File('$path.part').create(recursive: true);
    await File('$path.part').writeAsBytes(List.filled(400, 7));
    final progress = <TransferProgress>[];
    final result = await run(progress: progress);
    expect((result as TransferDone).restarted, isTrue);
    expect(progress.first.restarted, isTrue);
    expect(await File(path).readAsBytes(), server.body);
  });

  test('starts again when the range starts elsewhere', () async {
    server.wrongStart = true;
    await File('$path.part').create(recursive: true);
    await File('$path.part').writeAsBytes(List.filled(400, 7));
    final result = await run();
    expect((result as TransferDone).restarted, isTrue);
    expect(server.rangeHeaders, ['bytes=400-', null]);
    expect(await File(path).readAsBytes(), server.body);
  });

  test('a complete part file just gets its name', () async {
    await File('$path.part').create(recursive: true);
    await File('$path.part').writeAsBytes(server.body);
    final result = await run();
    expect(result, isA<TransferDone>());
    expect(await File(path).readAsBytes(), server.body);
  });

  test('keeps the range across a redirect', () async {
    await File('$path.part').create(recursive: true);
    await File('$path.part').writeAsBytes(server.body.sublist(0, 400));
    final redirect = server.url.replace(path: '/redirect');
    final result = await run(url: redirect);
    expect(result, isA<TransferDone>());
    expect(server.rangeHeaders, ['bytes=400-']);
    expect(await File(path).readAsBytes(), server.body);
  });

  test('stopping keeps the part file', () async {
    server.hangAfter = 100000;
    final control = TransferControl();
    final progress = <TransferProgress>[];
    final done = run(control: control, progress: progress);
    while (progress.isEmpty || progress.last.bytes < 100000) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    control.stop();
    final result = await done;
    expect(result, isA<TransferStopped>());
    expect(File('$path.part').lengthSync(), 100000);
    expect(File(path).existsSync(), isFalse);
  });

  test('a connection closed early fails and keeps the part', () async {
    server.cutAfter = 100000;
    final result = await run();
    expect(result, isA<TransferFailed>());
    expect(File(path).existsSync(), isFalse);
    expect(File('$path.part').lengthSync(), 100000);
  });

  test('a stalled download fails', () async {
    server.hangAfter = 100000;
    final result = await run(idle: const Duration(milliseconds: 200));
    expect((result as TransferFailed).message, contains('stalled'));
  });

  test('failures say what happened without the URL', () async {
    for (final (status, words) in [
      (404, 'no longer has'),
      (403, 'refused'),
      (502, 'HTTP 502'),
    ]) {
      server.status = status;
      final result = await run();
      final message = (result as TransferFailed).message;
      expect(message, contains(words));
      expect(message, isNot(contains('127.0.0.1')));
      expect(message, isNot(contains('user')));
      expect(message, isNot(contains('pass')));
    }

    final url = server.url;
    await server.close();
    final result = await run(url: url);
    final message = (result as TransferFailed).message;
    expect(message, startsWith("Couldn't reach the provider"));
    expect(message, isNot(contains('127.0.0.1')));
    expect(message, isNot(contains('pass')));
  });

  test('reads Content-Range', () {
    final r = ContentRange.parse('bytes 400-999/1000')!;
    expect((r.start, r.total), (400, 1000));
    final unsatisfied = ContentRange.parse('bytes */1000')!;
    expect((unsatisfied.start, unsatisfied.total), (null, 1000));
    expect(ContentRange.parse('bytes 0-9/*')!.total, isNull);
    expect(ContentRange.parse('items 1-2/3'), isNull);
    expect(ContentRange.parse(null), isNull);
  });
}
