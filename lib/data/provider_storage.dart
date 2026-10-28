import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// The keyring value saved under an earlier application ID.
class LegacyKeyring {
  const LegacyKeyring({required this.read, required this.clear});

  /// The old value (a JSON object of all keys), or null when there is none.
  final Future<String?> Function() read;

  /// Deletes the old value.
  final Future<void> Function() clear;
}

/// [ProviderStorage] in the platform keystore (Secret Service keyring on
/// Linux, Keystore on Android). Nothing is written to plain files.
class SecureProviderStorage implements ProviderStorage {
  SecureProviderStorage({
    FlutterSecureStorage? storage,
    this.legacy,
    this.android = false,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'provider_config_v1';

  /// Generous, because the keyring may show an unlock prompt.
  static const _timeout = Duration(seconds: 60);

  final FlutterSecureStorage _storage;

  /// Where a provider saved under an earlier application ID is moved from,
  /// once, on the first [load] when nothing is saved.
  final LegacyKeyring? legacy;

  /// Whether errors describe Android's secure storage instead of a
  /// Secret Service keyring.
  final bool android;

  /// The move from [legacy]; reset after a failure so a retry tries again.
  Future<void>? _migration;

  @override
  Future<ProviderConfig?> load() async {
    final legacy = this.legacy;
    if (legacy != null) await (_migration ??= _migrate(legacy));
    final raw = await _guard(() => _storage.read(key: _key));
    return raw == null ? null : decodeProviderConfig(raw);
  }

  /// Moves the provider from [legacy] and logs the outcome, never the value.
  Future<void> _migrate(LegacyKeyring legacy) => _guard(() async {
    try {
      final outcome = await _moveLegacy(legacy).timeout(_timeout);
      debugPrint('Keyring migration: $outcome');
    } catch (e) {
      _migration = null;
      debugPrint('Keyring migration: failed (${_describe(e)})');
      rethrow;
    }
  });

  Future<String> _moveLegacy(LegacyKeyring legacy) async {
    if (await _storage.read(key: _key) != null) return 'exists';
    final old = await legacy.read();
    if (old == null) return 'none';
    final String? value;
    try {
      final json = jsonDecode(old);
      value = json is Map && json[_key] is String ? json[_key] as String : null;
    } on FormatException {
      // Its message quotes the value.
      return 'none (old item unreadable)';
    }
    if (value == null) return 'none (old item has no provider)';
    await _storage.write(key: _key, value: value);
    if (await _storage.read(key: _key) != value) {
      throw const ProviderStorageException(
        'The moved provider did not read back the same.',
      );
    }
    try {
      await legacy.clear();
    } catch (e) {
      return 'migrated (old item left behind: ${_describe(e)})';
    }
    return 'migrated';
  }

  /// An error for the log; keyring errors never contain the stored value.
  static String _describe(Object e) => switch (e) {
    PlatformException(:final message) => message ?? e.code,
    ProviderStorageException(:final message) => message,
    TimeoutException() => 'no response',
    _ => '${e.runtimeType}',
  };

  @override
  Future<void> save(ProviderConfig config) => _guard(
    () => _storage.write(key: _key, value: encodeProviderConfig(config)),
  );

  @override
  Future<void> delete() => _guard(() => _storage.delete(key: _key));

  Future<T> _guard<T>(Future<T> Function() op) =>
      guardKeyring(op, android: android, subject: 'provider credentials');
}

/// Runs a keystore operation [op] with a timeout, turning its errors into
/// a [ProviderStorageException] that says what to do. [subject] is what
/// is stored, e.g. `provider credentials`. Messages never contain the
/// stored value.
Future<T> guardKeyring<T>(
  Future<T> Function() op, {
  required bool android,
  required String subject,
  Duration timeout = const Duration(seconds: 60),
}) async {
  try {
    return await op().timeout(timeout);
  } on TimeoutException {
    throw ProviderStorageException(
      android
          ? 'The secure storage of this device did not respond. Retry.'
          : 'The system keyring did not respond. If an unlock prompt is '
                'open, unlock it and retry.',
    );
  } catch (e) {
    // Errors come from libsecret/D-Bus or the Android Keystore and never
    // contain the stored value.
    throw ProviderStorageException(
      android
          ? 'Could not access the secure storage of this device. Retry. '
                '($e)'
          : 'Could not access the system keyring. tvplayer stores $subject '
                'in a Secret Service keyring (e.g. GNOME Keyring or KWallet); '
                'make sure one is installed, running and unlocked, then '
                'retry. ($e)',
    );
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
