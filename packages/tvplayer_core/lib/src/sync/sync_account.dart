import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/provider_config.dart';
import '../util/provider_key.dart';

/// The id of [config]'s account on a sync backend with [salt]
/// ([SyncInfo.salt]): 32 hex digits of an HMAC-SHA256 of
/// [providerIdentity]. It never contains the host, username or password,
/// and without the salt it can't be matched against guessed ones. The
/// same account gives the same id on every device; a new password keeps
/// it.
String syncAccountId(String salt, ProviderConfig config) =>
    Hmac(sha256, utf8.encode(salt))
        .convert(utf8.encode('tvplayer-account\n${providerIdentity(config)}'))
        .toString()
        .substring(0, 32);

/// The space of an account's watch history.
String watchSpace(String accountId) => 'watch-$accountId';

/// The space of an account's favourites and category settings.
String favouritesSpace(String accountId) => 'favourites-$accountId';

/// The space of the synced settings, shared by all accounts.
const settingsSpace = 'settings';
