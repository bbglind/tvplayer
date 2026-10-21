import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:tvplayer/data/provider_storage.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// In-memory [ProviderStorage]. Set [failure] to simulate an unavailable
/// keyring.
class FakeProviderStorage implements ProviderStorage {
  FakeProviderStorage([this.saved]);

  ProviderConfig? saved;
  ProviderStorageException? failure;
  int saves = 0;

  @override
  Future<ProviderConfig?> load() async {
    if (failure case final f?) throw f;
    return saved;
  }

  @override
  Future<void> save(ProviderConfig config) async {
    if (failure case final f?) throw f;
    saves++;
    saved = config;
  }

  @override
  Future<void> delete() async {
    if (failure case final f?) throw f;
    saved = null;
  }
}

/// [LiveSource] serving a fixed catalog. Fails the first [failTimes] loads.
class FakeLiveSource implements LiveSource {
  FakeLiveSource(this.catalog, {this.failTimes = 0});

  final LiveCatalog catalog;
  int failTimes;
  int loads = 0;
  Completer<void>? gate;

  @override
  Future<LiveCatalog> load() async {
    loads++;
    if (gate case final g?) await g.future;
    if (failTimes > 0) {
      failTimes--;
      throw const XtreamException('Request timed out (get_live_streams)');
    }
    return catalog;
  }

  @override
  Uri streamUrl(LiveStream stream) =>
      Uri.parse('http://192.0.2.1/live/user/pass/${stream.id}.ts');

  @override
  void close() {}
}

/// [count] synthetic channels spread over [categories] categories.
LiveCatalog syntheticCatalog({int count = 5000, int categories = 10}) {
  return LiveCatalog(
    categories: [
      for (var c = 0; c < categories; c++)
        Category(id: 'c$c', name: 'Category $c'),
    ],
    channels: [
      for (var i = 0; i < count; i++)
        LiveStream(
          id: '$i',
          name: 'Channel ${i.toString().padLeft(4, '0')}',
          categoryIds: ['c${i % categories}'],
          number: i + 1,
        ),
    ],
  );
}

/// JSON response as UTF-8 bytes.
http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

/// Synthetic Xtream login response for an active account.
const activeAccountJson = {
  'user_info': {
    'auth': 1,
    'status': 'Active',
    'exp_date': '1893456000',
    'max_connections': '1',
    'active_cons': '0',
  },
  'server_info': {'timezone': 'UTC'},
};

/// Wraps [child] in a ProviderScope (no automatic retries) and MaterialApp.
Widget testApp({required List<Override> overrides, required Widget child}) {
  return ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: MaterialApp(home: child),
  );
}
