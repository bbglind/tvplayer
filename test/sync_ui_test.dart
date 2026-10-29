import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/service_credentials.dart';
import 'package:tvplayer/data/sync_storage.dart';
import 'package:tvplayer/data/synced_settings.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/state/sync.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer/ui/settings/sync_section.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

const _config = ProviderConfig.xtream(
  host: 'http://example.com:8080',
  username: 'user',
  password: 'pass',
);

const _server = 'http://192.0.2.10:8787';
const _token = 'tvps_0123456789abcdefghij';

/// [SyncStorage] in memory.
class _MemorySyncStorage implements SyncStorage {
  final spaces = MemorySyncStateStore();
  var meta = const SyncMeta();
  final backups = <Map<String, Object?>>[];

  @override
  Future<SyncStateStore> states() async => spaces;

  @override
  Future<SyncMeta> loadMeta() async => meta;

  @override
  Future<void> saveMeta(SyncMeta meta) async => this.meta = meta;

  @override
  Future<String> backup(Map<String, Object?> files) async {
    backups.add(files);
    return 'test-${backups.length}';
  }
}

/// Keeps [syncProvider] alive, as the app does.
class _SyncHost extends ConsumerWidget {
  const _SyncHost(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncProvider);
    return child;
  }
}

/// Log lines of the running test.
final _log = <String>[];

/// [testWidgets] with the log captured in [_log] (and put back after).
void _testWidgets(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      final old = debugPrint;
      debugPrint = (message, {wrapWidth}) => _log.add(message ?? '');
      try {
        await body(tester);
      } finally {
        debugPrint = old;
      }
    });

void main() {
  late MemorySyncBackend backend;
  late _MemorySyncStorage storage;
  late FakeSettingsStorage settings;
  late MemoryWatchStore watch;
  late MemoryServiceCredentials credentials;
  late List<(Uri, String)> connections;

  setUp(() {
    backend = MemorySyncBackend(salt: 'salt-1');
    storage = _MemorySyncStorage();
    settings = FakeSettingsStorage(
      const AppSettings(syncEnabled: true, syncServer: _server),
    );
    watch = MemoryWatchStore(
      WatchData.empty.withItems({
        movieKey(1): updatedProgress(
          null,
          position: const Duration(minutes: 30),
          duration: const Duration(minutes: 100),
          now: DateTime.now().toUtc(),
        ),
      }),
    );
    credentials = MemoryServiceCredentials({MetadataService.syncToken: _token});
    _log.clear();
    connections = [];
  });

  String watchSpaceId() => watchSpace(syncAccountId('salt-1', _config));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Widget child = const SizedBox(),
  }) async {
    await tester.pumpWidget(
      testApp(
        providerStorage: FakeProviderStorage(_config),
        settings: settings,
        watch: watch,
        serviceCredentials: credentials,
        overrides: [
          syncStorageProvider.overrideWithValue(storage),
          syncBackendFactoryProvider.overrideWithValue((server, token) {
            connections.add((server, token));
            return backend;
          }),
        ],
        child: Scaffold(body: _SyncHost(child)),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(_SyncHost)));
  }

  group('sync engine in the app', () {
    _testWidgets('off: no requests at all, also later', (tester) async {
      settings.saved = const AppSettings(syncServer: _server);
      await pump(tester);
      await tester.pump(syncInterval * 2);
      expect(connections, isEmpty);
      expect(storage.backups, isEmpty);
      expect(_log.where((l) => l.startsWith('Sync')), isEmpty);
    });

    _testWidgets('syncs at start, backs up first and logs one short line', (
      tester,
    ) async {
      await pump(tester);
      expect(connections.single.$1.toString(), _server);
      expect(connections.single.$2, _token);
      expect(backend.records(watchSpaceId()).keys, contains(movieKey(1)));
      expect(storage.backups, hasLength(1));
      expect(storage.backups.single.keys, [
        'settings.json',
        'watch.json',
        'favourites.json',
      ]);
      final lines = _log.where((l) => l.startsWith('Sync: ok')).toList();
      expect(lines, hasLength(1));
      expect(
        lines.single,
        matches(
          RegExp(r'^Sync: ok · pulled \d+ · pushed \d+ · 3 spaces · \d+ ms$'),
        ),
      );
      for (final line in _log) {
        expect(line, isNot(contains(_token)));
        expect(line, isNot(contains('192.0.2.10')));
        expect(line, isNot(contains('example.com')));
      }
      expect(storage.meta.lastSync, isNotNull);
      expect(storage.meta.salt, 'salt-1');
    });

    _testWidgets('only synced settings are sent; device ones stay', (
      tester,
    ) async {
      final container = await pump(tester);
      await container
          .read(appSettingsProvider.notifier)
          .change(
            (s) => s.copyWith(
              movieSort: VodSort.title,
              sidebarWidth: 300,
              playerVolume: 40,
            ),
          );
      await container.read(syncProvider.notifier).syncNow();
      final sent = backend.records(settingsSpace);
      expect(sent['setting:movieSort']!.value, 'title');
      for (final key in sent.keys) {
        expect(syncedSettingNames, contains(key.substring('setting:'.length)));
      }
      expect(sent.keys, isNot(contains('setting:sidebarWidth')));
      expect(sent.keys, isNot(contains('setting:playerVolume')));
      expect(sent.keys, isNot(contains('setting:syncServer')));
    });

    _testWidgets('the server\'s settings win on the first sync', (
      tester,
    ) async {
      await backend.push(settingsSpace, [
        SyncRecord(key: 'setting:subtitlesOn', t: 1, value: false),
        SyncRecord(key: 'setting:sidebarWidth', t: 1, value: 300.0),
      ]);
      final container = await pump(tester);
      final s = container.read(appSettingsProvider).value!;
      expect(s.subtitlesOn, isFalse);
      // Not a synced setting: ignored.
      expect(s.sidebarWidth, AppSettings.defaultSidebarWidth);
      expect(settings.saved.subtitlesOn, isFalse);
    });

    _testWidgets('waits while a player is open, syncs when it closes', (
      tester,
    ) async {
      final container = await pump(tester);
      final before = connections.length;
      container.read(playerOpenProvider.notifier).enter();
      container
          .read(watchProvider.notifier)
          .recordProgress(
            movieKey(2),
            position: const Duration(minutes: 5),
            duration: const Duration(minutes: 90),
          );
      await tester.pump(syncInterval + syncChangeDelay);
      await tester.pumpAndSettle();
      expect(connections.length, before);
      expect(
        backend.records(watchSpaceId()).keys,
        isNot(contains(movieKey(2))),
      );
      container.read(playerOpenProvider.notifier).leave();
      await tester.pumpAndSettle();
      expect(connections.length, before + 1);
      expect(backend.records(watchSpaceId()).keys, contains(movieKey(2)));
    });

    _testWidgets('changes are sent shortly after, then every interval', (
      tester,
    ) async {
      final container = await pump(tester);
      final before = connections.length;
      container
          .read(favouritesProvider.notifier)
          .create(ContentKind.live, 'News', 'star');
      await tester.pump(syncChangeDelay);
      await tester.pumpAndSettle();
      expect(connections.length, before + 1);
      await tester.pump(syncInterval);
      await tester.pumpAndSettle();
      expect(connections.length, before + 2);
    });

    _testWidgets('offline: shows why, and sends the changes later', (
      tester,
    ) async {
      backend.failure = const SyncException(SyncFailure.network);
      final container = await pump(tester);
      expect(
        container.read(syncProvider).error,
        startsWith("Couldn't reach the sync server"),
      );
      expect(
        _log.where((l) => l.startsWith('Sync: failed (network)')),
        hasLength(1),
      );
      backend.failure = null;
      expect(await container.read(syncProvider.notifier).syncNow(), isNull);
      expect(backend.records(watchSpaceId()).keys, contains(movieKey(1)));
    });

    _testWidgets('another server starts over with a first sync', (
      tester,
    ) async {
      final container = await pump(tester);
      expect(storage.backups, hasLength(1));
      backend = MemorySyncBackend(salt: 'salt-2');
      await container.read(syncProvider.notifier).syncNow();
      expect(storage.backups, hasLength(2));
      expect(
        backend.records(watchSpace(syncAccountId('salt-2', _config))).keys,
        contains(movieKey(1)),
      );
    });
  });

  group('Settings › Sync', () {
    const section = Scaffold(body: SingleChildScrollView(child: SyncSection()));

    _testWidgets('off: only the switch', (tester) async {
      settings.saved = const AppSettings();
      await pump(tester, child: section);
      expect(find.text('Sync'), findsWidgets);
      expect(find.text('Server address'), findsNothing);
      expect(find.text('Sync now'), findsNothing);
      await tester.tap(find.byKey(const Key('settings.sync')));
      await tester.pumpAndSettle();
      expect(find.text('Server address'), findsOneWidget);
      expect(settings.saved.syncEnabled, isTrue);
    });

    _testWidgets('enters the address and token', (tester) async {
      settings.saved = const AppSettings(syncEnabled: true);
      credentials.values.clear();
      await pump(tester, child: section);
      expect(find.text('Not set'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('settings.syncServer.edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings.syncServer.field')),
        'ftp://nope',
      );
      await tester.tap(find.byKey(const Key('settings.syncServer.save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter an address like'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('settings.syncServer.field')),
        'https://sync.example.com',
      );
      await tester.tap(find.byKey(const Key('settings.syncServer.save')));
      await tester.pumpAndSettle();
      expect(settings.saved.syncServer, 'https://sync.example.com');

      await tester.tap(find.byKey(const Key('settings.syncToken.enter')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('settings.syncToken.field')),
        'not a token',
      );
      await tester.tap(find.byKey(const Key('settings.syncToken.save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tokens start with tvps_'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('settings.syncToken.field')),
        _token,
      );
      await tester.tap(find.byKey(const Key('settings.syncToken.save')));
      await tester.pumpAndSettle();
      expect(credentials.values[MetadataService.syncToken], _token);
      expect(find.text('Saved in the system keyring.'), findsOneWidget);
      // Saving the token syncs.
      expect(connections, isNotEmpty);
    });

    _testWidgets('Test connection and Sync now report with messages', (
      tester,
    ) async {
      await pump(tester, child: section);
      expect(find.textContaining('Last sync: Today'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings.syncTest')));
      await tester.pumpAndSettle();
      expect(find.text('Connected to the sync server.'), findsOneWidget);
      expect(find.byKey(const Key('message.icon.success')), findsOneWidget);

      backend.failure = const SyncException(SyncFailure.auth, statusCode: 401);
      await tester.tap(find.byKey(const Key('settings.syncTest')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "The sync server didn't accept the token. Check that you copied "
          'all of it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('settings.syncNow')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Last sync failed:'), findsOneWidget);
      expect(find.byKey(const Key('message.icon.error')), findsOneWidget);

      backend.failure = null;
      await tester.tap(find.byKey(const Key('settings.syncNow')));
      await tester.pumpAndSettle();
      expect(find.text('Synced.'), findsOneWidget);
      expect(find.textContaining('Last sync failed:'), findsNothing);
    });

    _testWidgets('is part of Settings, after Services', (tester) async {
      settings.saved = const AppSettings();
      await pump(tester, child: const SettingsScreen());
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.sync')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('settings.sync')), findsOneWidget);
    });
  });
}
