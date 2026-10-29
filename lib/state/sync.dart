import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/app_settings.dart';
import '../data/errors.dart';
import '../data/provider_storage.dart';
import '../data/service_credentials.dart';
import '../data/sync_storage.dart';
import '../data/synced_settings.dart';
import 'providers.dart';
import 'tmdb.dart';

/// How often sync runs on its own, besides at start, when playback
/// stops, when the app comes back and after changes.
const syncInterval = Duration(minutes: 5);

/// How long after a change sync waits, so a burst of changes goes in one.
const syncChangeDelay = Duration(seconds: 20);

/// Coming back to the app syncs only when the last sync is older.
const syncResumeGap = Duration(minutes: 1);

/// Where sync keeps its files. Overridden in tests.
final syncStorageProvider = Provider<SyncStorage>((ref) => FileSyncStorage());

/// Makes the backend for a server address and token. Overridden in tests.
final syncBackendFactoryProvider =
    Provider<SyncBackend Function(Uri server, String token)>((ref) {
      final client = ref.watch(httpClientProvider);
      return (server, token) =>
          HttpSyncBackend(server: server, token: token, client: client);
    });

/// The saved sync token; null when none is saved.
final syncTokenProvider = AsyncNotifierProvider<SyncTokenNotifier, String?>(
  SyncTokenNotifier.new,
);

class SyncTokenNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() =>
      ref.watch(serviceCredentialsProvider).read(MetadataService.syncToken);

  /// Saves the token in [text]. Throws [FormatException] when it doesn't
  /// look like one, or ProviderStorageException.
  Future<void> save(String text) async {
    final token = text.trim();
    if (!token.startsWith('tvps_') || token.length < 20) {
      throw const FormatException(
        "That doesn't look like a sync token. Tokens start with tvps_.",
      );
    }
    await ref
        .read(serviceCredentialsProvider)
        .write(MetadataService.syncToken, token);
    state = AsyncData(token);
  }

  Future<void> remove() async {
    await ref
        .read(serviceCredentialsProvider)
        .delete(MetadataService.syncToken);
    state = const AsyncData(null);
  }
}

/// What started a sync.
enum SyncReason { start, playbackStopped, resume, timer, change, manual }

/// Where sync stands, for Settings › Sync.
final class SyncStatus {
  const SyncStatus({this.running = false, this.lastSync, this.error});

  final bool running;

  /// When the last sync went through.
  final DateTime? lastSync;

  /// Why the last sync failed, in words; null when it went through.
  final String? error;

  SyncStatus copyWith({
    bool? running,
    DateTime? lastSync,
    String? Function()? error,
  }) => SyncStatus(
    running: running ?? this.running,
    lastSync: lastSync ?? this.lastSync,
    error: error == null ? this.error : error(),
  );
}

/// Syncs watch data, favourites and the synced settings with the user's
/// sync server, when sync is on and set up; does nothing at all
/// otherwise. Runs at start, when playback stops, when the app comes back,
/// every [syncInterval], [syncChangeDelay] after a change and on "Sync
/// now"; never while a player is open (it runs when the player closes).
/// One sync at a time; a request during one runs once more after it.
final syncProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends Notifier<SyncStatus> {
  Timer? _timer;
  Timer? _debounce;
  Future<void>? _running;
  bool _again = false;

  /// Set while sync itself changes data, so that isn't a new change.
  bool _applying = false;

  /// Loaded once; changes are saved as they happen.
  Future<SyncMeta>? _meta;
  Future<void> _metaSaving = Future.value();

  @override
  SyncStatus build() {
    final enabled = ref.watch(
      appSettingsProvider.select((s) => s.value?.syncEnabled ?? false),
    );
    ref.watch(appSettingsProvider.select((s) => s.value?.syncServer));
    ref.onDispose(() {
      _timer?.cancel();
      _debounce?.cancel();
    });
    if (!enabled) return const SyncStatus();
    _timer = Timer.periodic(syncInterval, (_) => request(SyncReason.timer));
    ref.listen(playerOpenProvider, (was, open) {
      if (was == true && !open) request(SyncReason.playbackStopped);
    });
    ref.listen(watchProvider, (_, _) => _changed());
    ref.listen(favouritesProvider, (_, _) => _changed());
    ref.listen(
      appSettingsProvider,
      (was, now) => _settingsChanged(was?.value, now.value),
    );
    unawaited(_start());
    return const SyncStatus();
  }

  Future<void> _start() async {
    final meta = await _loadMeta();
    if (!ref.mounted) return;
    state = state.copyWith(lastSync: meta.lastSync);
    request(SyncReason.start);
  }

  Future<SyncMeta> _loadMeta() => _meta ??= () async {
    final meta = await ref.read(syncStorageProvider).loadMeta();
    ref.read(syncClockProvider).restore(meta.clock);
    return meta;
  }();

  void _saveMeta(SyncMeta meta) {
    _meta = Future.value(meta);
    final storage = ref.read(syncStorageProvider);
    _metaSaving = _metaSaving.then((_) async {
      try {
        await storage.saveMeta(meta);
      } catch (e) {
        debugPrint('Sync: could not save its state (${e.runtimeType})');
      }
    });
  }

  void _changed() {
    if (_applying) return;
    _debounce?.cancel();
    _debounce = Timer(syncChangeDelay, () => request(SyncReason.change));
  }

  /// Notes when synced settings were changed on this device.
  Future<void> _settingsChanged(AppSettings? was, AppSettings? now) async {
    if (_applying || was == null || now == null) return;
    final before = syncedValues(was);
    final after = syncedValues(now);
    final changed = [
      for (final name in syncedSettingNames)
        if (canonicalJson(before[name]) != canonicalJson(after[name])) name,
    ];
    if (changed.isEmpty) return;
    final t = ref.read(syncClockProvider).now().millisecondsSinceEpoch;
    final meta = await _loadMeta();
    if (!ref.mounted) return;
    _saveMeta(
      meta.copyWith(stamps: {...meta.stamps, for (final n in changed) n: t}),
    );
    _changed();
  }

  /// Syncs soon for [reason], unless a player is open (except for "Sync
  /// now"): then when it closes.
  void request(SyncReason reason) {
    if (!ref.mounted ||
        !(ref.read(appSettingsProvider).value?.syncEnabled ?? false)) {
      return;
    }
    if (reason != SyncReason.manual && ref.read(playerOpenProvider)) return;
    final last = state.lastSync;
    if (reason == SyncReason.resume &&
        last != null &&
        DateTime.now().difference(last) < syncResumeGap) {
      return;
    }
    if (reason != SyncReason.change) _debounce?.cancel();
    unawaited(_run());
  }

  /// Syncs now ("Sync now"); the error in words, or null when it went
  /// through.
  Future<String?> syncNow() async {
    await _run();
    return ref.mounted ? state.error : null;
  }

  Future<void> _run() {
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = () async {
      try {
        do {
          _again = false;
          await _syncOnce();
        } while (_again && ref.mounted);
      } finally {
        _running = null;
      }
    }();
  }

  /// The server, token and provider to sync with; null when sync is off
  /// or not set up.
  Future<(Uri, String)?> _target() async {
    final settings = await ref.read(appSettingsProvider.future);
    final server = parseSyncServerAddress(settings.syncServer ?? '');
    if (!settings.syncEnabled || server == null) return null;
    final token = await ref.read(syncTokenProvider.future);
    return token == null ? null : (server, token);
  }

  Future<void> _syncOnce() async {
    final watch = Stopwatch()..start();
    SyncBackend? backend;
    try {
      final target = await _target();
      if (target == null || !ref.mounted) return;
      state = state.copyWith(running: true);
      backend = ref.read(syncBackendFactoryProvider)(target.$1, target.$2);
      final report = await _sync(backend);
      if (!ref.mounted) return;
      final now = DateTime.now().toUtc();
      final meta = await _loadMeta();
      _saveMeta(
        meta.copyWith(
          lastSync: now,
          clock: ref.read(syncClockProvider).toJson(),
        ),
      );
      if (ref.mounted) {
        state = SyncStatus(lastSync: now);
      }
      debugPrint(
        'Sync: ok · pulled ${report.pulled} · pushed ${report.pushed} · '
        '${report.spaces.length} spaces'
        '${report.skipped > 0 ? ' · ${report.skipped} too large' : ''}'
        ' · ${watch.elapsedMilliseconds} ms',
      );
    } catch (e) {
      final message = switch (e) {
        ProviderStorageException(:final message) => message,
        _ => describeSyncError(e),
      };
      debugPrint(
        'Sync: failed (${e is SyncException ? e.message : e.runtimeType})'
        ' · ${watch.elapsedMilliseconds} ms',
      );
      if (ref.mounted) {
        state = state.copyWith(running: false, error: () => message);
      }
    } finally {
      backend?.close();
      if (ref.mounted && state.running) {
        state = state.copyWith(running: false);
      }
    }
  }

  Future<SyncReport> _sync(SyncBackend backend) async {
    final storage = ref.read(syncStorageProvider);
    final clock = ref.read(syncClockProvider);
    final states = await storage.states();
    var meta = await _loadMeta();
    ProviderConfig? config;
    try {
      config = await ref.read(savedProviderProvider.future);
    } on ProviderStorageException {
      config = null;
    }
    await ref.read(appSettingsProvider.future);
    await ref.read(watchProvider.notifier).loaded;
    await ref.read(favouritesProvider.notifier).loaded;
    final engine = SyncEngine(backend: backend, states: states, clock: clock);
    final info = await engine.connect();
    if (meta.salt != info.salt) {
      // Another server (or one set up again): start over.
      if (meta.salt != null) await states.clear();
      _saveMeta(meta = meta.copyWith(salt: () => info.salt));
    }

    Future<void>? backup;
    Future<void> backupOnce() => backup ??= _backup(storage, config);

    final spaces = <SyncSpace>[
      SettingsSyncSpace(
        id: settingsSpace,
        values: () => syncedValues(_settings),
        stamps: () => _stamps,
        write: _writeSettings,
        clock: clock,
        backup: backupOnce,
      ),
      if (config != null) ...[
        WatchSyncSpace(
          id: watchSpace(syncAccountId(info.salt, config)),
          read: () => ref.read(watchProvider),
          write: (data) =>
              _apply(() => ref.read(watchProvider.notifier).applySynced(data)),
          clock: clock,
          backup: backupOnce,
        ),
        FavouritesSyncSpace(
          id: favouritesSpace(syncAccountId(info.salt, config)),
          read: () => ref.read(favouritesProvider),
          write: (data) => _apply(
            () => ref.read(favouritesProvider.notifier).applySynced(data),
          ),
          clock: clock,
          backup: backupOnce,
        ),
      ],
    ];
    _stamps = meta.stamps;
    final reports = <String, SpaceReport>{};
    for (final space in spaces) {
      if (!ref.mounted) break;
      reports[space.id] = await engine.sync(space);
    }
    return SyncReport(reports);
  }

  /// The stamps of the synced settings during a sync.
  Map<String, int> _stamps = const {};

  AppSettings get _settings =>
      ref.read(appSettingsProvider).value ?? const AppSettings();

  void _writeSettings(Map<String, Object?> values, Map<String, int> times) {
    _stamps = {..._stamps, ...times};
    unawaited(
      _loadMeta().then((meta) {
        if (ref.mounted) _saveMeta(meta.copyWith(stamps: _stamps));
      }),
    );
    final next = withSyncedValues(_settings, values);
    _apply(() {
      unawaited(
        ref
            .read(appSettingsProvider.notifier)
            .set(next)
            .catchError(
              (Object e) => debugPrint(
                'Sync: could not save the settings (${e.runtimeType})',
              ),
            ),
      );
    });
  }

  void _apply(void Function() change) {
    _applying = true;
    try {
      change();
    } finally {
      _applying = false;
    }
  }

  /// Saves the local data before a first sync.
  Future<void> _backup(SyncStorage storage, ProviderConfig? config) async {
    final name = await storage.backup({
      'settings.json': _settings.toJson(),
      if (config != null) ...{
        'watch.json': ref.read(watchProvider).toJson(),
        'favourites.json': ref.read(favouritesProvider).toJson(),
      },
    });
    debugPrint('Sync: first sync, local data saved in sync_backup/$name');
  }

  /// "Test connection": what the server says, in words.
  Future<(String, bool)> testConnection() async {
    final target = await _target();
    if (target == null) {
      return ('Enter the server address and token first.', false);
    }
    final backend = ref.read(syncBackendFactoryProvider)(target.$1, target.$2);
    try {
      await backend.info();
      return ('Connected to the sync server.', true);
    } catch (e) {
      return (describeSyncError(e), false);
    } finally {
      backend.close();
    }
  }
}
