import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'store.dart';

/// Longest record key taken.
const maxKeyLength = 512;

/// The sync API (see `sync_protocol.dart` in tvplayer_core) on [store].
/// [log] gets one line per request: method, route, status, record count
/// and time; never a token, key or value.
Handler syncApi(
  SyncStore store, {
  DateTime Function()? clock,
  void Function(String line)? log,
}) {
  final now = clock ?? DateTime.now;
  return (request) async {
    final watch = Stopwatch()..start();
    final (response, route, count) = await _route(store, request, now);
    log?.call(
      '${request.method} $route ${response.statusCode}'
      '${count == null ? '' : ' · $count records'}'
      ' · ${watch.elapsedMilliseconds} ms',
    );
    return response;
  };
}

Response _json(Object body, [int status = 200]) => Response(
  status,
  body: jsonEncode({'service': syncServiceName, ...body as Map}),
  headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
);

Response _error(int status, String error) => _json({'error': error}, status);

/// The response, the route template for the log and the records handled.
Future<(Response, String, int?)> _route(
  SyncStore store,
  Request request,
  DateTime Function() now,
) async {
  final segments = request.url.pathSegments;
  final time = now().millisecondsSinceEpoch;
  if (segments.isEmpty || segments.first != 'v$syncApiVersion') {
    return (_error(404, 'not found'), '/?', null);
  }
  final path = segments.skip(1).toList();

  if (path case ['health']) {
    if (request.method != 'GET') {
      return (_error(405, 'method'), '/health', null);
    }
    return (_json({'api': syncApiVersion}), '/health', null);
  }

  final auth = request.headers['authorization'] ?? '';
  final token = auth.startsWith('Bearer ') ? auth.substring(7).trim() : '';
  if (token.isEmpty || store.authenticate(token) == null) {
    return (_error(401, 'auth'), _template(path), null);
  }

  switch (path) {
    case ['info']:
      if (request.method != 'GET') {
        return (_error(405, 'method'), '/info', null);
      }
      return (
        _json({'api': syncApiVersion, 'salt': store.salt, 'serverTime': time}),
        '/info',
        null,
      );

    case ['spaces', final space, 'changes']:
      const route = '/spaces/:space/changes';
      if (request.method != 'GET') return (_error(405, 'method'), route, null);
      if (!isSyncSpace(space)) return (_error(400, 'space'), route, null);
      final query = request.url.queryParameters;
      final since = int.tryParse(query['since'] ?? '0');
      final known = int.tryParse(query['head'] ?? '0');
      final limit = int.tryParse(query['limit'] ?? '$syncMaxRecords');
      if (since == null ||
          since < 0 ||
          known == null ||
          limit == null ||
          limit < 1) {
        return (_error(400, 'query'), route, null);
      }
      final page = store.changes(
        space,
        since,
        known: known,
        limit: limit.clamp(1, syncMaxRecords),
      );
      return (
        _json({
          'records': [for (final r in page.records) r.toJson()],
          'cursor': '${page.cursor}',
          'more': page.more,
          'head': '${page.head}',
          if (page.reset) 'reset': true,
          'serverTime': time,
        }),
        route,
        page.records.length,
      );

    case ['spaces', final space, 'records']:
      const route = '/spaces/:space/records';
      if (request.method != 'POST') return (_error(405, 'method'), route, null);
      if (!isSyncSpace(space)) return (_error(400, 'space'), route, null);
      final body = await _readBody(request);
      if (body == null) return (_error(413, 'too large'), route, null);
      final List<SyncRecord> records;
      try {
        final json = jsonDecode(utf8.decode(body));
        final list = json is Map ? json['records'] : null;
        if (list is! List) return (_error(400, 'body'), route, null);
        records = [
          for (final r in list)
            SyncRecord.fromJson(r) ?? (throw const FormatException()),
        ];
      } on FormatException {
        return (_error(400, 'body'), route, null);
      }
      if (records.length > syncMaxRecords) {
        return (_error(413, 'too many records'), route, records.length);
      }
      if (records.any((r) => r.key.length > maxKeyLength)) {
        return (_error(400, 'key'), route, records.length);
      }
      if (records.any((r) => r.t > time + syncMaxAhead.inMilliseconds)) {
        return (_error(422, 'clock'), route, records.length);
      }
      final stale = store.push(space, records);
      return (
        _json({
          'stale': [for (final r in stale) r.toJson()],
          'head': '${store.head}',
          'serverTime': time,
        }),
        route,
        records.length,
      );
  }
  return (_error(404, 'not found'), _template(path), null);
}

/// The route of [path] for the log, without ids.
String _template(List<String> path) => switch (path) {
  ['spaces', _, final action] => '/spaces/:space/$action',
  [final first, ...] => '/$first',
  [] => '/',
};

/// The body of [request], or null when it is larger than
/// [syncMaxRequestBytes].
Future<List<int>?> _readBody(Request request) async {
  final length = request.contentLength;
  if (length != null && length > syncMaxRequestBytes) return null;
  final bytes = <int>[];
  await for (final chunk in request.read()) {
    bytes.addAll(chunk);
    if (bytes.length > syncMaxRequestBytes) return null;
  }
  return bytes;
}
