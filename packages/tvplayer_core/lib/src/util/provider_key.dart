import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/provider_config.dart';

/// A short, stable id for [config], used to keep per-provider data (watch
/// history, catalogue caches) apart. It is a hash of the provider type,
/// host and username (or playlist URL): it never contains them and they
/// can't be read back from it. The password is left out, so changing it
/// keeps the data.
String providerKey(ProviderConfig config) {
  final identity = switch (config.type) {
    ProviderType.xtream =>
      'xtream\n${config.host?.trim().toLowerCase()}\n${config.username}',
    ProviderType.m3u => 'm3u\n${config.playlistUrl?.trim()}',
  };
  return sha256.convert(utf8.encode(identity)).toString().substring(0, 16);
}
