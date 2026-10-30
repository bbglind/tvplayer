import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/default_categories.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

final _first = ProviderConfig.xtream(
  host: 'example.com:8080',
  username: 'user',
  password: 'pass',
);
final _second = ProviderConfig.xtream(
  host: 'example.com:8080',
  username: 'user2',
  password: 'pass',
);

/// What stays between starts of the app.
class _Device {
  _Device({bool eligible = true, ProviderConfig? saved})
    : marker = MemoryDefaultCategoriesStore(eligible: eligible),
      provider = FakeProviderStorage(saved);

  final MemoryDefaultCategoriesStore marker;
  final FakeProviderStorage provider;
  final stores = <String, MemoryFavouritesStore>{};

  MemoryFavouritesStore store(ProviderConfig config) =>
      stores.putIfAbsent(providerKey(config), MemoryFavouritesStore.new);

  /// A start of the app.
  Future<ProviderContainer> start() async {
    final container = ProviderContainer(
      overrides: [
        defaultCategoriesStoreProvider.overrideWithValue(marker),
        providerStorageProvider.overrideWithValue(provider),
        favouritesStoreProvider.overrideWithValue(
          (key) => stores.putIfAbsent(key, MemoryFavouritesStore.new),
        ),
        epgRepositoryProvider.overrideWithValue(FakeEpgRepository()),
        vodRepositoryProvider.overrideWithValue(FakeVodRepository()),
        archiveEpgRepositoryProvider.overrideWithValue(
          MemoryArchiveEpgRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(savedProviderProvider.future);
    return container;
  }

  /// Saves [config] as the provider, as "Add a provider" does.
  Future<void> add(ProviderConfig config) async {
    final container = await start();
    await container.read(savedProviderProvider.notifier).save(config);
  }

  /// The favourites of the active provider, loaded as the app does.
  Future<(ProviderContainer, FavouritesData)> favourites() async {
    final container = await start();
    container.listen(favouritesProvider, (_, _) {});
    await container.read(favouritesProvider.notifier).loaded;
    return (container, container.read(favouritesProvider));
  }
}

List<String> _live(FavouritesData d) => [
  for (final c in d.categories.values)
    if (!c.deleted) c.name,
];

void main() {
  group('a new install', () {
    test('the first account gets exactly three empty categories', () async {
      final device = _Device();
      await device.add(_first);
      final (_, data) = await device.favourites();
      expect(data.categories, hasLength(3));
      expect(
        [
          for (final kind in ContentKind.values)
            for (final c in data.categoriesOf(kind)) (c.name, c.icon),
        ],
        [
          ('My Channels', 'tv'),
          ('My Movies', 'movie'),
          ('My Series', 'series'),
        ],
      );
      expect(data.memberships, isEmpty);
    });

    test('a later new account gets them too; going back adds none', () async {
      final device = _Device();
      await device.add(_first);
      final (container, _) = await device.favourites();
      final notifier = container.read(favouritesProvider.notifier);
      notifier.delete('default-live');
      await notifier.saved;

      await device.add(_second);
      expect(device.store(_second).data.categories, hasLength(3));

      await device.add(_first);
      final (_, data) = await device.favourites();
      expect(_live(data), ['My Movies', 'My Series']);
    });

    test('a new password is the same account', () async {
      final device = _Device();
      await device.add(_first);
      final (container, _) = await device.favourites();
      final notifier = container.read(favouritesProvider.notifier);
      notifier.delete('default-series');
      await notifier.saved;
      await device.add(
        ProviderConfig.xtream(
          host: 'example.com:8080',
          username: 'user',
          password: 'other',
        ),
      );
      final (_, data) = await device.favourites();
      expect(_live(data), ['My Channels', 'My Movies']);
    });

    test('they stay gone after delete and rename, and a restart', () async {
      final device = _Device();
      await device.add(_first);
      final (container, _) = await device.favourites();
      final notifier = container.read(favouritesProvider.notifier);
      notifier.delete('default-live');
      notifier.edit('default-movie', name: 'Films', icon: 'movie');
      await notifier.saved;
      container.dispose();

      final (_, data) = await device.favourites();
      expect(_live(data), ['Films', 'My Series']);
      // Saving the same account again doesn't bring them back either.
      await device.add(_first);
      final (_, again) = await device.favourites();
      expect(_live(again), ['Films', 'My Series']);
    });

    test('an account that already has data keeps it as it is', () async {
      final device = _Device();
      device.store(_first).data = createCategory(
        FavouritesData.empty,
        kind: ContentKind.live,
        name: 'News',
        icon: 'news',
        now: DateTime.utc(2026),
      ).$1;
      await device.add(_first);
      expect(_live(device.store(_first).data), ['News']);
    });
  });

  group('an existing install', () {
    test('creates none, even for a new account', () async {
      final device = _Device(eligible: false);
      await device.add(_first);
      await device.add(_second);
      expect(device.stores.values.where((s) => s.saves > 0), isEmpty);
    });

    test('a provider in the keyring means the install is not new', () async {
      final device = _Device(saved: _first);
      await device.start();
      expect(device.marker.marker.eligible, isFalse);
      await device.add(_second);
      expect(device.store(_second).data.categories, isEmpty);
    });

    test(
      'restarting a new install with its account keeps it eligible',
      () async {
        final device = _Device();
        await device.add(_first);
        await device.start();
        expect(device.marker.marker.eligible, isTrue);
        await device.add(_second);
        expect(device.store(_second).data.categories, hasLength(3));
      },
    );
  });

  group('the marker file', () {
    late Directory root;
    late FileDefaultCategoriesStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('tvplayer_marker');
      addTearDown(() => root.delete(recursive: true));
      store = FileDefaultCategoriesStore(() async => root);
    });

    test('an empty folder is a new install', () async {
      await store.prepare();
      expect((await store.load()).eligible, isTrue);
    });

    for (final name in ['settings.json', 'tmdb.sqlite', 'skip.sqlite']) {
      test('$name means an existing install', () async {
        await File('${root.path}/$name').writeAsString('{}');
        await store.prepare();
        expect((await store.load()).eligible, isFalse);
      });
    }

    for (final name in [
      'favourites',
      'watch',
      'playlist',
      'downloads',
      'sync',
      'sync_backup',
    ]) {
      test('$name/ means an existing install', () async {
        await Directory('${root.path}/$name').create();
        await store.prepare();
        expect((await store.load()).eligible, isFalse);
      });
    }

    test('it is decided once', () async {
      await store.prepare();
      await File('${root.path}/settings.json').writeAsString('{}');
      await store.prepare();
      expect((await store.load()).eligible, isTrue);
    });

    test('seeded accounts are kept', () async {
      await store.prepare();
      await store.save((await store.load()).withSeeded('abc'));
      expect((await store.load()).seeded, {'abc'});
    });

    test('no file or a damaged one is not eligible', () async {
      expect((await store.load()).eligible, isFalse);
      final file = File('${root.path}/default_categories.json');
      await file.writeAsString('not json');
      expect((await store.load()).eligible, isFalse);
      await file.writeAsString(jsonEncode([1]));
      expect((await store.load()).eligible, isFalse);
    });
  });
}
