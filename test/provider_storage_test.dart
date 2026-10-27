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
    test('is loaded after the keyring item is moved', () async {
      var calls = 0;
      final loaded = await SecureProviderStorage(
        migrateLegacy: () async {
          calls++;
          await storage.write(
            key: 'provider_config_v1',
            value: encodeProviderConfig(_config),
          );
          return true;
        },
      ).load();

      expect(calls, 1);
      expect(loaded?.username, 'user');
      expect(loaded?.password, 's3cret-pass');
    });

    test('is absent when there was nothing to move', () async {
      final loaded = await SecureProviderStorage(
        migrateLegacy: () async => false,
      ).load();

      expect(loaded, isNull);
    });

    test('is not looked for when a provider is saved', () async {
      FlutterSecureStorage.setMockInitialValues({
        'provider_config_v1': encodeProviderConfig(_config),
      });
      var calls = 0;
      final loaded = await SecureProviderStorage(
        migrateLegacy: () async {
          calls++;
          return false;
        },
      ).load();

      expect(calls, 0);
      expect(loaded?.host, 'example.com:8080');
    });

    test('reports a keyring error without credentials', () async {
      final load = SecureProviderStorage(
        migrateLegacy: () => throw PlatformException(
          code: 'keyring',
          message: 'Cannot create an item in a locked collection',
        ),
      ).load();

      await expectLater(
        load,
        throwsA(
          isA<ProviderStorageException>().having(
            (e) => e.message,
            'message',
            allOf(contains('locked collection'), isNot(contains('s3cret'))),
          ),
        ),
      );
    });
  });
}
