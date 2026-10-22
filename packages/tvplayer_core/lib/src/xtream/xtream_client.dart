import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/account_info.dart';
import '../models/category.dart';
import '../models/episode.dart';
import '../models/epg_program.dart';
import '../models/live_channel.dart';
import '../models/movie.dart';
import '../models/provider_config.dart';
import '../models/series.dart';
import '../util/json.dart';

/// Error talking to an Xtream panel. Messages never contain the host,
/// credentials or request URLs.
class XtreamException implements Exception {
  const XtreamException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'XtreamException: $message'
      : 'XtreamException: $message (HTTP $statusCode)';
}

/// The panel rejected the username or password.
class XtreamAuthException extends XtreamException {
  const XtreamAuthException([super.message = 'Authentication failed']);
}

/// Client for the Xtream Codes `player_api.php` API.
///
/// Responses are parsed leniently: list entries that can't be parsed are
/// skipped instead of failing the whole request.
class XtreamClient {
  /// Creates a client for an Xtream [config]. Pass an [httpClient] to control
  /// transport (e.g. a mock in tests); a client created here is closed by
  /// [close].
  XtreamClient(
    ProviderConfig config, {
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _baseUri = _parseHost(config),
       _username = config.username ?? '',
       _password = config.password ?? '',
       _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  static Uri _parseHost(ProviderConfig config) {
    if (config.type != ProviderType.xtream) {
      throw ArgumentError('XtreamClient requires an xtream ProviderConfig');
    }
    var host = config.host?.trim() ?? '';
    if (!host.contains('://')) host = 'http://$host';
    final uri = Uri.tryParse(host);
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError('Invalid Xtream host');
    }
    // Keep any path prefix (some panels live under a sub path), minus
    // trailing slashes and a pasted-in player_api.php.
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/player_api.php')) {
      path = path.substring(0, path.length - '/player_api.php'.length);
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
  }

  final Uri _baseUri;
  final String _username;
  final String _password;
  final http.Client _http;
  final bool _ownsHttpClient;

  /// Timeout applied to each API request.
  final Duration timeout;

  /// Verifies the credentials and returns account details.
  ///
  /// Throws [XtreamAuthException] when the panel rejects the login.
  Future<AccountInfo> login() async {
    final json = readMap(await _get(null));
    final user = readMap(json?['user_info']);
    if (json == null || user == null || !readBool(user['auth'])) {
      throw const XtreamAuthException();
    }
    return AccountInfo.fromJson(json);
  }

  Future<List<Category>> getLiveCategories() =>
      _getList('get_live_categories', Category.fromJson);

  Future<List<Category>> getVodCategories() =>
      _getList('get_vod_categories', Category.fromJson);

  Future<List<Category>> getSeriesCategories() =>
      _getList('get_series_categories', Category.fromJson);

  Future<List<LiveChannel>> getLiveStreams({String? categoryId}) => _getList(
    'get_live_streams',
    LiveChannel.fromJson,
    {'category_id': ?categoryId},
  );

  Future<List<Movie>> getVodStreams({String? categoryId}) =>
      _getList('get_vod_streams', Movie.fromJson, {'category_id': ?categoryId});

  Future<List<Series>> getSeries({String? categoryId}) =>
      _getList('get_series', Series.fromJson, {'category_id': ?categoryId});

  /// Full details for one movie. Throws [XtreamException] if not found.
  Future<Movie> getVodInfo(int vodId) async {
    final json = readMap(await _get('get_vod_info', {'vod_id': '$vodId'}));
    final movie = json == null ? null : Movie.fromVodInfoJson(json);
    if (movie == null) throw XtreamException('Movie $vodId not found');
    return movie;
  }

  /// Seasons and episodes of one series. Throws [XtreamException] if not
  /// found.
  Future<SeriesInfo> getSeriesInfo(int seriesId) async {
    final json = readMap(
      await _get('get_series_info', {'series_id': '$seriesId'}),
    );
    final infoJson = readMap(json?['info']);
    final series = infoJson == null
        ? null
        : Series.fromJson(infoJson, seriesId: seriesId);
    if (json == null || series == null) {
      throw XtreamException('Series $seriesId not found');
    }

    final episodes = <Episode>[];
    final rawEpisodes = json['episodes'];
    if (rawEpisodes is Map) {
      // Usual shape: {"1": [episode, ...], "2": [...]}.
      for (final MapEntry(:key, :value) in rawEpisodes.entries) {
        final season = readInt(key);
        episodes.addAll(_parseEpisodes(value, season));
      }
    } else {
      // Some panels send a list of per-season lists instead.
      for (final value in readList(rawEpisodes)) {
        episodes.addAll(_parseEpisodes(value is List ? value : [value], null));
      }
    }
    episodes.sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      return bySeason != 0
          ? bySeason
          : a.episodeNumber.compareTo(b.episodeNumber);
    });

    final seasons = readList(json['seasons'])
        .map(readMap)
        .whereType<Map<String, Object?>>()
        .map(Season.fromJson)
        .whereType<Season>()
        .toList();
    final known = seasons.map((s) => s.seasonNumber).toSet();
    for (final number in episodes.map((e) => e.season).toSet()) {
      if (known.add(number)) {
        seasons.add(Season(seasonNumber: number, name: 'Season $number'));
      }
    }
    seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

    return SeriesInfo(series: series, seasons: seasons, episodes: episodes);
  }

  static Iterable<Episode> _parseEpisodes(Object? value, int? season) =>
      readList(value)
          .map(readMap)
          .whereType<Map<String, Object?>>()
          .map((e) => Episode.fromJson(e, fallbackSeason: season))
          .whereType<Episode>();

  /// Upcoming programmes for one live stream, decoded from base64.
  Future<List<EpgProgram>> getShortEpg(int streamId, {int? limit}) async {
    final json = await _get('get_short_epg', {
      'stream_id': '$streamId',
      if (limit != null) 'limit': '$limit',
    });
    final listings = readMap(json)?['epg_listings'];
    return readList(listings)
        .map(readMap)
        .whereType<Map<String, Object?>>()
        .map(EpgProgram.fromXtreamJson)
        .whereType<EpgProgram>()
        .toList();
  }

  /// Playback URL of a live stream. [extension] is `ts` by default; `m3u8`
  /// is the other common choice. Contains credentials: never log it.
  Uri liveStreamUrl(int streamId, {String extension = 'ts'}) =>
      _streamUrl('live', '$streamId', extension);

  /// Playback URL of a movie, using its container extension from the API
  /// (`mp4` if unknown). Contains credentials: never log it.
  Uri movieUrl(Movie movie) => _streamUrl(
    'movie',
    '${movie.streamId}',
    movie.containerExtension ?? 'mp4',
  );

  /// Playback URL of a series episode, using its container extension from
  /// the API (`mp4` if unknown). Contains credentials: never log it.
  Uri episodeUrl(Episode episode) =>
      _streamUrl('series', episode.id, episode.containerExtension ?? 'mp4');

  /// URL of the full XMLTV guide (`xmltv.php`), for use with `XmltvParser`.
  /// Contains credentials: never log it.
  Uri xmltvUrl() => _baseUri.replace(
    path: '${_baseUri.path}/xmltv.php',
    queryParameters: {'username': _username, 'password': _password},
  );

  /// Downloads the full XMLTV guide (`xmltv.php`) into [target], streaming
  /// it so large guides are never held in memory. [idleTimeout] limits how
  /// long the panel may stay silent. Throws [XtreamException]; messages
  /// never contain the URL or credentials. A partial file is deleted.
  Future<void> downloadXmltv(
    File target, {
    Duration idleTimeout = const Duration(seconds: 60),
  }) async {
    const what = 'xmltv';
    final http.StreamedResponse response;
    try {
      response = await _http
          .send(http.Request('GET', xmltvUrl()))
          .timeout(timeout);
    } on TimeoutException {
      throw const XtreamException('Request timed out ($what)');
    } on http.ClientException catch (e) {
      throw XtreamException('Network error ($what): ${_redact(e.message)}');
    } catch (e) {
      throw XtreamException('Network error ($what): ${e.runtimeType}');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      await response.stream.drain<void>().catchError((_) {});
      throw const XtreamAuthException();
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw XtreamException(
        'Unexpected response ($what)',
        statusCode: response.statusCode,
      );
    }

    final sink = target.openWrite();
    try {
      await sink.addStream(response.stream.timeout(idleTimeout));
      await sink.close();
    } catch (e) {
      await sink.close().catchError((_) {});
      if (await target.exists()) await target.delete();
      throw switch (e) {
        TimeoutException() => const XtreamException('Download stalled ($what)'),
        http.ClientException(:final message) => XtreamException(
          'Network error ($what): ${_redact(message)}',
        ),
        FileSystemException(:final message) => XtreamException(
          'Could not save the guide: $message',
        ),
        _ => XtreamException('Download failed ($what): ${e.runtimeType}'),
      };
    }
  }

  Uri _streamUrl(String kind, String id, String extension) {
    final ext = extension.startsWith('.') ? extension.substring(1) : extension;
    return _baseUri.replace(
      pathSegments: [
        ..._baseUri.pathSegments,
        kind,
        _username,
        _password,
        '$id.$ext',
      ],
    );
  }

  /// Closes the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  /// Responses at least this large are decoded and parsed in a background
  /// isolate, so big catalogues don't block the caller's isolate (the UI).
  static const backgroundParseBytes = 256 * 1024;

  Future<List<T>> _getList<T>(
    String action,
    T? Function(Map<String, Object?>) parse, [
    Map<String, String> params = const {},
  ]) async {
    final bytes = await _fetch(action, params);
    if (bytes.length < backgroundParseBytes) {
      return _parseList(bytes, action, parse);
    }
    return Isolate.run(() => _parseList(bytes, action, parse));
  }

  static List<T> _parseList<T>(
    Uint8List bytes,
    String what,
    T? Function(Map<String, Object?>) parse,
  ) => readList(_decode(bytes, what))
      .map(readMap)
      .whereType<Map<String, Object?>>()
      .map(parse)
      .whereType<T>()
      .toList();

  /// Performs a `player_api.php` request and returns the decoded JSON.
  /// [action] null is the login/account request.
  Future<Object?> _get(
    String? action, [
    Map<String, String> params = const {},
  ]) async => _decode(await _fetch(action, params), action ?? 'login');

  /// Performs a `player_api.php` request and returns the response body.
  Future<Uint8List> _fetch(
    String? action, [
    Map<String, String> params = const {},
  ]) async {
    final uri = _baseUri.replace(
      path: '${_baseUri.path}/player_api.php',
      queryParameters: {
        'username': _username,
        'password': _password,
        'action': ?action,
        ...params,
      },
    );
    final what = action ?? 'login';

    final http.Response response;
    try {
      response = await _http.get(uri).timeout(timeout);
    } on TimeoutException {
      throw XtreamException('Request timed out ($what)');
    } on http.ClientException catch (e) {
      // ClientException.toString() includes the URL, so only use the message.
      throw XtreamException('Network error ($what): ${_redact(e.message)}');
    } catch (e) {
      throw XtreamException('Network error ($what): ${e.runtimeType}');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const XtreamAuthException();
    }
    if (response.statusCode != 200) {
      throw XtreamException(
        'Unexpected response ($what)',
        statusCode: response.statusCode,
      );
    }

    return response.bodyBytes;
  }

  static Object? _decode(Uint8List bytes, String what) {
    // Decode as UTF-8 regardless of the Content-Type header: panels often
    // omit the charset, which would make package:http fall back to Latin-1.
    var body = utf8.decode(bytes, allowMalformed: true).trim();
    if (body.startsWith('﻿')) body = body.substring(1);
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      // FormatException.toString() includes the body, which may echo the
      // credentials back; don't propagate it.
      throw XtreamException('Invalid JSON response ($what)');
    }
  }

  String _redact(String text) {
    var result = text;
    for (final secret in [_password, _username, _baseUri.host]) {
      if (secret.isNotEmpty) result = result.replaceAll(secret, '***');
    }
    return result;
  }

  @override
  String toString() => 'XtreamClient(<redacted>)';
}
