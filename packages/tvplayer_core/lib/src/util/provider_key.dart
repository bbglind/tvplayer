import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/provider_config.dart';

/// What identifies the account of [config]: the provider type, host and
/// username (or playlist URL). Not the password, so changing it keeps the
/// account's data. Contains credentials: only ever hash it.
String providerIdentity(ProviderConfig config) => switch (config.type) {
  ProviderType.xtream =>
    'xtream\n${config.host?.trim().toLowerCase()}\n${config.username}',
  ProviderType.m3u => 'm3u\n${config.playlistUrl?.trim()}',
};

/// A short, stable id for [config], used to keep per-provider data (watch
/// history, catalogue caches) apart. It is a hash of [providerIdentity]:
/// it never contains the host or username and they can't be read back
/// from it. The password is left out, so changing it keeps the data.
String providerKey(ProviderConfig config) => sha256
    .convert(utf8.encode(providerIdentity(config)))
    .toString()
    .substring(0, 16);
