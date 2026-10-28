import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'provider_storage.dart';

/// The online services that take a personal key.
enum MetadataService {
  tmdb('tmdb_credential_v1'),

  /// SkipDB and TheIntroDB need a key only to submit timestamps (10.2).
  skipDb('skipdb_key_v1'),
  introDb('introdb_key_v1');

  const MetadataService(this.storageKey);

  final String storageKey;
}

/// Keys of [MetadataService]s, kept like the provider login: in the
/// platform keystore, never in files, logs or messages.
abstract interface class ServiceCredentials {
  /// The saved key of [service], or null when none is saved. Throws
  /// [ProviderStorageException].
  Future<String?> read(MetadataService service);

  Future<void> write(MetadataService service, String value);

  Future<void> delete(MetadataService service);
}

/// [ServiceCredentials] in the Secret Service keyring (Linux) or the
/// Android Keystore.
class SecureServiceCredentials implements ServiceCredentials {
  SecureServiceCredentials({
    FlutterSecureStorage? storage,
    this.android = false,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final bool android;

  Future<T> _guard<T>(Future<T> Function() op) =>
      guardKeyring(op, android: android, subject: 'service keys');

  @override
  Future<String?> read(MetadataService service) =>
      _guard(() => _storage.read(key: service.storageKey));

  @override
  Future<void> write(MetadataService service, String value) =>
      _guard(() => _storage.write(key: service.storageKey, value: value));

  @override
  Future<void> delete(MetadataService service) =>
      _guard(() => _storage.delete(key: service.storageKey));
}
