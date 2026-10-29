import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../util/json.dart';
import 'sync_backend.dart';
import 'sync_protocol.dart';
import 'sync_record.dart';

/// The address of a sync server as typed by the user: `http://` or
/// `https://` with a host, optionally a port and a path; a bare
/// `host[:port]` gets `http://`. Null when it isn't one.
Uri? parseSyncServerAddress(String text) {
  var s = text.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  // Without a trailing slash, so paths can be appended.
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return uri.replace(path: path);
}

/// [SyncBackend] on a tvplayer sync server (see `sync_protocol.dart`).
class HttpSyncBackend implements SyncBackend {
  HttpSyncBackend({
    required this.server,
    required String token,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _token = token,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// From [parseSyncServerAddress].
  final Uri server;
  final String _token;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String>? query]) => server.replace(
    path: '${server.path}/v$syncApiVersion/$path',
    queryParameters: query,
  );

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_token',
    'Accept': 'application/json',
  };

  /// Sends a request and reads the JSON object it answers, turning every
  /// failure into a [SyncException] (never with the address or token).
  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() request, {
    bool identify = false,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const SyncException(SyncFailure.timeout);
    } on SocketException {
      throw const SyncException(SyncFailure.network);
    } on HandshakeException {
      throw const SyncException(SyncFailure.network);
    } on http.ClientException {
      throw const SyncException(SyncFailure.network);
    }
    final status = response.statusCode;
    Map<String, Object?>? body;
    try {
      body = readMap(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException {
      body = null;
    }
    final ours = body?['service'] == syncServiceName;
    if (status == 401 || status == 403) {
      throw SyncException(
        ours ? SyncFailure.auth : SyncFailure.notSyncServer,
        statusCode: status,
      );
    }
    if (status == 422 && body?['error'] == 'clock') {
      throw SyncException(SyncFailure.clock, statusCode: status);
    }
    if (status >= 500) {
      throw SyncException(SyncFailure.server, statusCode: status);
    }
    if (status != 200) {
      throw SyncException(
        status == 404 && !ours ? SyncFailure.notSyncServer : SyncFailure.other,
        statusCode: status,
      );
    }
    if (body == null || (identify && !ours)) {
      throw SyncException(
        identify ? SyncFailure.notSyncServer : SyncFailure.invalidData,
      );
    }
    return body;
  }

  static int _serverTime(Map<String, Object?> body) =>
      switch (body['serverTime']) {
        final int t => t,
        _ => throw const SyncException(SyncFailure.invalidData),
      };

  static String? _head(Map<String, Object?> body) =>
      body['head'] is String ? body['head'] as String : null;

  static List<SyncRecord> _records(Object? json) {
    if (json is! List) throw const SyncException(SyncFailure.invalidData);
    return [
      for (final r in json)
        SyncRecord.fromJson(r) ??
            (throw const SyncException(SyncFailure.invalidData)),
    ];
  }

  @override
  Future<SyncInfo> info() async {
    final body = await _send(
      () => _client.get(_uri('info'), headers: _headers),
      identify: true,
    );
    final salt = body['salt'];
    if (salt is! String || salt.isEmpty) {
      throw const SyncException(SyncFailure.invalidData);
    }
    return SyncInfo(salt: salt, serverTime: _serverTime(body));
  }

  @override
  Future<SyncPage> pull(
    String space,
    String? cursor, {
    int limit = syncMaxRecords,
    String? head,
  }) async {
    final body = await _send(
      () => _client.get(
        _uri('spaces/$space/changes', {
          'since': ?cursor,
          'head': ?head,
          'limit': '$limit',
        }),
        headers: _headers,
      ),
    );
    final next = body['cursor'];
    return SyncPage(
      records: _records(body['records']),
      cursor: next is String ? next : null,
      more: body['more'] == true,
      serverTime: _serverTime(body),
      head: _head(body),
      reset: body['reset'] == true,
    );
  }

  @override
  Future<PushResult> push(String space, List<SyncRecord> records) async {
    final body = await _send(
      () => _client.post(
        _uri('spaces/$space/records'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'records': [for (final r in records) r.toJson()],
        }),
      ),
    );
    return PushResult(
      stale: _records(body['stale']),
      serverTime: _serverTime(body),
      head: _head(body),
    );
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}
