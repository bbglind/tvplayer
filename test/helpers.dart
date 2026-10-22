import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/epg_repository.dart';
import 'package:tvplayer/data/provider_storage.dart';
import 'package:tvplayer/state/providers.dart';
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
/// Has a guide only when [hasGuide] is set; [downloadGuide] writes
/// [guideXml].
class FakeLiveSource implements LiveSource {
  FakeLiveSource(
    this.catalog, {
    this.failTimes = 0,
    this.hasGuide = false,
    this.guideXml = '<tv></tv>',
  });

  final LiveCatalog catalog;
  String guideXml;

  @override
  bool hasGuide;

  @override
  Future<void> downloadGuide(File target) => target.writeAsString(guideXml);

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

/// In-memory [SettingsStorage].
class FakeSettingsStorage implements SettingsStorage {
  FakeSettingsStorage([this.saved = const AppSettings()]);

  AppSettings saved;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

/// [EpgRepository] with an in-memory cache. [refresh] returns [next] (or
/// throws [failure]) after [gate] completes, if set.
class FakeEpgRepository implements EpgRepository {
  FakeEpgRepository({this.cached, this.next, this.failure});

  EpgGuide? cached;
  EpgGuide? next;
  Object? failure;
  Completer<void>? gate;
  int refreshes = 0;
  int clears = 0;
  List<LiveStream>? lastChannels;

  @override
  Future<EpgGuide?> loadCache() async => cached;

  @override
  Future<EpgGuide> refresh(
    LiveSource source,
    List<LiveStream> channels, {
    required DateTime now,
    required DateTime keepFrom,
  }) async {
    refreshes++;
    lastChannels = channels;
    if (gate case final g?) await g.future;
    if (failure case final f?) throw f;
    final guide = next ?? EpgGuide.empty(fetchedAt: now);
    cached = guide;
    return guide;
  }

  @override
  Future<void> clear() async {
    clears++;
    cached = null;
  }
}

/// A [Clock] that stays at [time] (UTC).
class FixedClock extends Clock {
  FixedClock(this.time);

  final DateTime time;

  @override
  DateTime build() => time;

  void set(DateTime value) => state = value;
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
///
/// Settings, the guide cache and the device time zone (`Europe/Stockholm`)
/// are always faked; pass [settings] or [epg] to inspect them. [now] fixes
/// the clock.
Widget testApp({
  required List<Override> overrides,
  required Widget child,
  SettingsStorage? settings,
  EpgRepository? epg,
  DateTime? now,
}) {
  return ProviderScope(
    overrides: [
      settingsStorageProvider.overrideWithValue(
        settings ?? FakeSettingsStorage(),
      ),
      epgRepositoryProvider.overrideWithValue(epg ?? FakeEpgRepository()),
      deviceTimeZoneProvider.overrideWithValue('Europe/Stockholm'),
      if (now != null) clockProvider.overrideWith(() => FixedClock(now)),
      ...overrides,
    ],
    retry: (_, _) => null,
    child: MaterialApp(home: child),
  );
}
