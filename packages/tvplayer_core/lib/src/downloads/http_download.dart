import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// How far a transfer got.
final class TransferProgress {
  const TransferProgress(this.bytes, this.total, {this.restarted = false});

  /// Bytes in the file so far.
  final int bytes;

  /// The full size, when the server says.
  final int? total;

  /// The server couldn't continue the partial file, so it started again
  /// from the beginning.
  final bool restarted;
}

sealed class TransferResult {
  const TransferResult();
}

/// The file is complete at its final path.
final class TransferDone extends TransferResult {
  const TransferDone(this.bytes, {this.restarted = false});

  final int bytes;
  final bool restarted;
}

/// Stopped by [TransferControl.stop]; the partial file is kept.
final class TransferStopped extends TransferResult {
  const TransferStopped(this.bytes);

  final int bytes;
}

/// Failed; the partial file is kept so it can be resumed. [message] is in
/// plain words and never contains the URL.
final class TransferFailed extends TransferResult {
  const TransferFailed(this.message, {this.bytes = 0});

  final String message;
  final int bytes;
}

/// Lets the owner of a transfer stop it (pause or cancel).
final class TransferControl {
  final _stop = Completer<void>();

  bool get stopped => _stop.isCompleted;

  Future<void> get onStop => _stop.future;

  void stop() {
    if (!_stop.isCompleted) _stop.complete();
  }
}

/// Downloads one file over HTTP, exactly as the server sends it, into
/// `<path>.part`, and renames it to [path] when complete. An existing part
/// file is resumed with a `Range` request; when the server can't do that
/// the file starts again from the beginning ([TransferProgress.restarted]).
///
/// The URL contains the account's credentials: it is never logged, and no
/// message or exception text that could contain it is passed on.
final class HttpDownload {
  HttpDownload({
    http.Client? client,
    this.connectTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 60),
    this.progressInterval = const Duration(milliseconds: 500),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration connectTimeout;

  /// No data for this long fails the transfer.
  final Duration idleTimeout;

  /// [run] reports progress at most this often (and at the end).
  final Duration progressInterval;

  Future<TransferResult> run({
    required Uri url,
    required String path,
    required TransferControl control,
    void Function(TransferProgress progress)? onProgress,
  }) async {
    final part = File('$path.part');
    var bytes = 0;
    try {
      await part.parent.create(recursive: true);
      var offset = await part.exists() ? await part.length() : 0;
      var restarted = false;
      var response = await _send(url, offset);
      int? total;
      if (offset > 0) {
        final range = ContentRange.parse(response.headers['content-range']);
        switch (response.statusCode) {
          case 416 when range?.total == offset:
            // Nothing left to send: the part file is complete.
            await _discard(response);
            await part.rename(path);
            onProgress?.call(TransferProgress(offset, offset));
            return TransferDone(offset);
          case 206 when range != null && range.start == offset:
            total = range.total;
          case 200:
            restarted = true;
            offset = 0;
          default:
            if (response.statusCode == 206 || response.statusCode == 416) {
              await _discard(response);
              restarted = true;
              offset = 0;
              response = await _send(url, 0);
            }
        }
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        await _discard(response);
        return TransferFailed(httpFailureMessage(response.statusCode));
      }
      if (offset == 0) total = response.contentLength;
      bytes = offset;
      onProgress?.call(TransferProgress(bytes, total, restarted: restarted));

      final file = await part.open(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      final chunks = StreamIterator(response.stream);
      final clock = Stopwatch()..start();
      var stopped = false;
      try {
        while (true) {
          final next = await Future.any([
            chunks.moveNext().timeout(idleTimeout),
            control.onStop.then((_) => false),
          ]);
          if (control.stopped) {
            stopped = true;
            break;
          }
          if (!next) break;
          await file.writeFrom(chunks.current);
          bytes += chunks.current.length;
          if (clock.elapsed >= progressInterval) {
            clock.reset();
            onProgress?.call(TransferProgress(bytes, total));
          }
        }
      } finally {
        await chunks.cancel();
        await file.close();
      }
      onProgress?.call(TransferProgress(bytes, total));
      if (stopped) return TransferStopped(bytes);
      if (total != null && bytes < total) {
        return TransferFailed(
          'The connection closed before the end.',
          bytes: bytes,
        );
      }
      await part.rename(path);
      return TransferDone(bytes, restarted: restarted);
    } on TimeoutException {
      return TransferFailed(
        'The download stalled: no data for ${idleTimeout.inSeconds} s.',
        bytes: bytes,
      );
    } on FileSystemException catch (e) {
      // The message holds the path; keep only the type.
      return TransferFailed(
        "Couldn't write the file (${e.runtimeType}).",
        bytes: bytes,
      );
    } catch (e) {
      // Socket and client errors may echo the URL; keep only the type.
      return TransferFailed(
        "Couldn't reach the provider (${e.runtimeType}).",
        bytes: bytes,
      );
    }
  }

  Future<http.StreamedResponse> _send(Uri url, int offset) {
    final request = http.Request('GET', url);
    if (offset > 0) request.headers['range'] = 'bytes=$offset-';
    return _client.send(request).timeout(connectTimeout);
  }

  static Future<void> _discard(http.StreamedResponse response) =>
      response.stream.listen(null).cancel();

  void close() => _client.close();
}

/// A failed HTTP status in plain words.
String httpFailureMessage(int status) => switch (status) {
  404 || 410 => 'The provider no longer has this file (HTTP $status).',
  401 || 403 => 'The provider refused the download (HTTP $status).',
  >= 500 => "The provider's server had a problem (HTTP $status).",
  _ => 'The provider answered HTTP $status.',
};

/// A `Content-Range: bytes start-end/total` header (`total` may be `*`;
/// `bytes */total` answers a range that can't be served).
final class ContentRange {
  const ContentRange(this.start, this.total);

  /// The first byte sent, or null for `bytes */total`.
  final int? start;
  final int? total;

  static final _pattern = RegExp(r'^bytes\s+(?:(\d+)-\d+|\*)/(\d+|\*)$');

  static ContentRange? parse(String? header) {
    final m = _pattern.firstMatch(header?.trim() ?? '');
    if (m == null) return null;
    return ContentRange(
      m.group(1) == null ? null : int.parse(m.group(1)!),
      int.tryParse(m.group(2)!),
    );
  }
}
