import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/m3u_entry.dart';
import '../util/provider_failure.dart';
import 'm3u_parser.dart';

/// Error fetching an M3U playlist. Messages never contain the playlist URL.
class M3uException implements Exception {
  const M3uException(this.message, {this.statusCode, ProviderFailure? kind})
    : _kind = kind;

  final String message;
  final int? statusCode;
  final ProviderFailure? _kind;

  /// What went wrong; from [statusCode] unless given.
  ProviderFailure get kind => _kind ?? ProviderFailure.forStatus(statusCode);

  @override
  String toString() => statusCode == null
      ? 'M3uException: $message'
      : 'M3uException: $message (HTTP $statusCode)';
}

/// Downloads and parses an M3U/M3U8 playlist over HTTP(S).
class M3uClient {
  /// Creates a client for [playlistUrl]. Pass an [httpClient] to control
  /// transport (e.g. a mock in tests); a client created here is closed by
  /// [close].
  ///
  /// Throws [ArgumentError] when the URL isn't an absolute http(s) URL.
  M3uClient(
    String playlistUrl, {
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _uri = _parseUrl(playlistUrl),
       _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static Uri _parseUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('Invalid playlist URL');
    }
    return uri;
  }

  final Uri _uri;
  final http.Client _http;
  final bool _ownsHttpClient;

  /// Timeout for the whole download.
  final Duration timeout;

  /// Downloads the playlist and returns its entries.
  ///
  /// Throws [M3uException] on network errors, non-200 responses, or when the
  /// response doesn't look like an M3U playlist.
  Future<List<M3uEntry>> fetch() async {
    try {
      return await _fetch().timeout(timeout);
    } on TimeoutException {
      throw const M3uException(
        'Request timed out',
        kind: ProviderFailure.timeout,
      );
    } on M3uException {
      rethrow;
    } on http.ClientException catch (e) {
      // ClientException.toString() includes the URL, so only use the message.
      throw M3uException(
        'Network error: ${_redact(e.message)}',
        kind: ProviderFailure.network,
      );
    } catch (e) {
      throw M3uException(
        'Network error: ${e.runtimeType}',
        kind: ProviderFailure.network,
      );
    }
  }

  Future<List<M3uEntry>> _fetch() async {
    final response = await _http.send(http.Request('GET', _uri));
    if (response.statusCode != 200) {
      // Drain so the connection can be reused.
      unawaited(response.stream.drain<void>().catchError((_) {}));
      throw M3uException(
        response.statusCode == 401 || response.statusCode == 403
            ? 'Access denied'
            : 'Unexpected response',
        statusCode: response.statusCode,
      );
    }
    final entries = await const M3uParser()
        .parseBytes(response.stream)
        .toList();
    // The parser is lenient (it accepts any non-directive line as a URL), so
    // an HTML error page would still "parse"; require at least one real URL.
    if (!entries.any((e) => _looksLikeUrl(e.url))) {
      throw const M3uException(
        'Playlist is empty or not an M3U file',
        kind: ProviderFailure.invalidData,
      );
    }
    return entries;
  }

  static bool _looksLikeUrl(String s) {
    if (s.contains(' ') || s.contains('<')) return false;
    final uri = Uri.tryParse(s);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  String _redact(String text) {
    var result = text.replaceAll(_uri.toString(), '***');
    if (_uri.host.isNotEmpty) result = result.replaceAll(_uri.host, '***');
    return result;
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  @override
  String toString() => 'M3uClient(<redacted>)';
}
