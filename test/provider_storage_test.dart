import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/provider_storage.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

const _config = ProviderConfig.xtream(
  host: 'example.com:8080',
  username: 'user',
  password: 's3cret-pass',
);

void main() {
  const storage = FlutterSecureStorage();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('a provider saved under the old application ID', () {
    late List<String> log;
    late DebugPrintCallback savedDebugPrint;

    setUp(() {
      log = [];
      savedDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => log.add(message ?? '');
    });
    tearDown(() => debugPrint = savedDebugPrint);

    String legacyValue([ProviderConfig config = _config]) =>
        jsonEncode({'provider_config_v1': encodeProviderConfig(config)});

    test('is moved and loaded, and the old item cleared', () async {
      var cleared = 0;
      final loaded = await SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async => legacyValue(),
          clear: () async => cleared++,
        ),
      ).load();

      expect(loaded?.username, 'user');
      expect(loaded?.password, 's3cret-pass');
      expect(
        await storage.read(key: 'provider_config_v1'),
        encodeProviderConfig(_config),
      );
      expect(cleared, 1);
      expect(log, ['Keyring migration: migrated']);
    });

    test('is absent when there was nothing to move', () async {
      final loaded = await SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async => null,
          clear: () async => fail('nothing to clear'),
        ),
      ).load();

      expect(loaded, isNull);
      expect(log, ['Keyring migration: none']);
    });

    test('is absent when the old item has no provider', () async {
      final loaded = await SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async => jsonEncode({'other': 'x'}),
          clear: () async => fail('kept'),
        ),
      ).load();

      expect(loaded, isNull);
      expect(log.single, startsWith('Keyring migration: none'));
    });

    test('is not looked for when a provider is saved', () async {
      FlutterSecureStorage.setMockInitialValues({
        'provider_config_v1': encodeProviderConfig(_config),
      });
      var reads = 0;
      final loaded = await SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async {
            reads++;
            return null;
          },
          clear: () async {},
        ),
      ).load();

      expect(reads, 0);
      expect(loaded?.host, 'example.com:8080');
      expect(log, ['Keyring migration: exists']);
    });

    test('is moved once across concurrent loads', () async {
      var reads = 0;
      final store = SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async {
            reads++;
            return legacyValue();
          },
          clear: () async {},
        ),
      );
      final loaded = await Future.wait([store.load(), store.load()]);
      await store.load();

      expect(reads, 1);
      expect(loaded.map((c) => c?.username), ['user', 'user']);
      expect(log, ['Keyring migration: migrated']);
    });

    test('is still loaded when the old item cannot be cleared', () async {
      final loaded = await SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async => legacyValue(),
          clear: () =>
              throw PlatformException(code: 'keyring', message: 'Nope'),
        ),
      ).load();

      expect(loaded?.username, 'user');
      expect(log, ['Keyring migration: migrated (old item left behind: Nope)']);
    });

    test('never logs an unreadable old item', () async {
      final loaded = await SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async => '{"provider_config_v1": "s3cret-pass',
          clear: () async => fail('kept'),
        ),
      ).load();

      expect(loaded, isNull);
      expect(log.single, startsWith('Keyring migration: none'));
      expect(log.single, isNot(contains('s3cret')));
    });

    test('reports a keyring error without credentials, and retries', () async {
      var attempts = 0;
      final store = SecureProviderStorage(
        legacy: LegacyKeyring(
          read: () async {
            if (attempts++ == 0) {
              throw PlatformException(
                code: 'keyring',
                message: 'Cannot create an item in a locked collection',
              );
            }
            return legacyValue();
          },
          clear: () async {},
        ),
      );

      await expectLater(
        store.load(),
        throwsA(
          isA<ProviderStorageException>().having(
            (e) => e.message,
            'message',
            allOf(contains('locked collection'), isNot(contains('s3cret'))),
          ),
        ),
      );
      expect((await store.load())?.username, 'user');
      expect(log, [
        'Keyring migration: failed '
            '(Cannot create an item in a locked collection)',
        'Keyring migration: migrated',
      ]);
    });
  });
}
