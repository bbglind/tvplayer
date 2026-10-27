import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// The application ID of test builds before it was made permanent. Data
/// folders and the keyring item are named after the ID.
const legacyApplicationId = 'dev.example.tvplayer';

/// Moves the data and cache folders of [legacyApplicationId] to the current
/// ones on first start (Linux only). Failures leave the old folders in
/// place and are only logged.
Future<void> migrateLegacyData() async {
  if (!Platform.isLinux) return;
  for (final current in [
    await getApplicationSupportDirectory(),
    await getApplicationCacheDirectory(),
  ]) {
    final legacy = Directory('${current.parent.path}/$legacyApplicationId');
    if (legacy.path == current.path) continue;
    await migrateLegacyDirectory(legacy, current);
  }
}

const _keyringChannel = MethodChannel('tvplayer/legacy_keyring');

/// The flutter_secure_storage keyring value of [legacyApplicationId] (a JSON
/// object of all keys), or null when there is none or off Linux. Throws a
/// [PlatformException] when the keyring can't be used. Contains credentials.
Future<String?> readLegacyKeyring() async {
  if (!Platform.isLinux) return null;
  return _keyringChannel.invokeMethod<String>('read', legacyApplicationId);
}

/// Deletes the keyring item of [legacyApplicationId].
Future<void> clearLegacyKeyring() async {
  if (!Platform.isLinux) return;
  await _keyringChannel.invokeMethod<void>('clear', legacyApplicationId);
}
