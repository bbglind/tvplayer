import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// The saved provider couldn't be read or written, typically because no
/// Secret Service keyring is available or it is locked.
class ProviderStorageException implements Exception {
  const ProviderStorageException(this.message);

  final String message;

  @override
  String toString() => 'ProviderStorageException: $message';
}

/// Persists the single configured provider.
abstract interface class ProviderStorage {
  /// The saved provider, or null when none is saved.
  Future<ProviderConfig?> load();

  Future<void> save(ProviderConfig config);

  Future<void> delete();
}

/// [ProviderStorage] in the platform keystore (Secret Service keyring on
/// Linux, Keystore on Android). Nothing is written to plain files.
class SecureProviderStorage implements ProviderStorage {
  SecureProviderStorage({FlutterSecureStorage? storage, this.migrateLegacy})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'provider_config_v1';

  /// Generous, because the keyring may show an unlock prompt.
  static const _timeout = Duration(seconds: 60);

  final FlutterSecureStorage _storage;

  /// Moves a provider saved under an earlier application ID into the
  /// keystore and returns true when it did; tried when nothing is saved.
  final Future<bool> Function()? migrateLegacy;

  @override
  Future<ProviderConfig?> load() async {
    var raw = await _guard(() => _storage.read(key: _key));
    final migrate = migrateLegacy;
    if (raw == null && migrate != null && await _guard(migrate)) {
      raw = await _guard(() => _storage.read(key: _key));
    }
    return raw == null ? null : decodeProviderConfig(raw);
  }

  @override
  Future<void> save(ProviderConfig config) => _guard(
    () => _storage.write(key: _key, value: encodeProviderConfig(config)),
  );

  @override
  Future<void> delete() => _guard(() => _storage.delete(key: _key));

  static Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(_timeout);
    } on TimeoutException {
      throw const ProviderStorageException(
        'The system keyring did not respond. If an unlock prompt is open, '
        'unlock it and retry.',
      );
    } catch (e) {
      // Errors come from libsecret/D-Bus and never contain the stored value.
      throw ProviderStorageException(
        'Could not access the system keyring. tvplayer stores provider '
        'credentials in a Secret Service keyring (e.g. GNOME Keyring or '
        'KWallet); make sure one is installed, running and unlocked, then '
        'retry. ($e)',
      );
    }
  }
}

/// Serializes [config] for storage. The result contains credentials.
String encodeProviderConfig(ProviderConfig config) =>
    jsonEncode(switch (config.type) {
      ProviderType.xtream => {
        'type': 'xtream',
        'host': config.host,
        'username': config.username,
        'password': config.password,
      },
      ProviderType.m3u => {'type': 'm3u', 'playlistUrl': config.playlistUrl},
    });

/// Inverse of [encodeProviderConfig]; null for unreadable data.
ProviderConfig? decodeProviderConfig(String raw) {
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    String? s(String key) => json[key] is String ? json[key] as String : null;
    return switch (s('type')) {
      'xtream' when s('host') != null => ProviderConfig.xtream(
        host: s('host')!,
        username: s('username') ?? '',
        password: s('password') ?? '',
      ),
      'm3u' when s('playlistUrl') != null => ProviderConfig.m3u(
        playlistUrl: s('playlistUrl')!,
      ),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}
