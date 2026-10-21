import 'package:http/http.dart' as http;
import 'package:tvplayer_core/tvplayer_core.dart';

import 'errors.dart';

/// Outcome of a connection test. [message] is safe to show: it never
/// contains credentials, hosts or URLs.
final class ConnectionResult {
  const ConnectionResult.success(this.message) : ok = true;
  const ConnectionResult.failure(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// Checks that a provider config works: Xtream login, or fetching the M3U.
class ConnectionTester {
  ConnectionTester(this._http);

  final http.Client _http;

  Future<ConnectionResult> test(ProviderConfig config) => switch (config.type) {
    ProviderType.xtream => _testXtream(config),
    ProviderType.m3u => _testM3u(config),
  };

  Future<ConnectionResult> _testXtream(ProviderConfig config) async {
    final XtreamClient client;
    try {
      client = XtreamClient(config, httpClient: _http);
    } on ArgumentError {
      return const ConnectionResult.failure(
        'Enter a valid host, e.g. example.com:8080.',
      );
    }
    try {
      final account = await client.login();
      final details = [
        'account status: ${account.status}',
        if (account.expiresAt case final exp?) 'expires ${_date(exp)}',
        if (account.maxConnections case final max?)
          'connections ${account.activeConnections ?? 0}/$max',
      ].join(', ');
      return account.isActive
          ? ConnectionResult.success('Connected ($details).')
          : ConnectionResult.failure(
              'Logged in, but the account is not active ($details).',
            );
    } catch (e) {
      return ConnectionResult.failure(describeProviderError(e));
    } finally {
      client.close();
    }
  }

  Future<ConnectionResult> _testM3u(ProviderConfig config) async {
    final M3uClient client;
    try {
      client = M3uClient(config.playlistUrl ?? '', httpClient: _http);
    } on ArgumentError {
      return const ConnectionResult.failure(
        'Enter a valid http(s) playlist URL.',
      );
    }
    try {
      final entries = await client.fetch();
      final groups = entries.map((e) => e.groupTitle).toSet().length;
      return ConnectionResult.success(
        'Playlist loaded: ${entries.length} entries in $groups groups.',
      );
    } catch (e) {
      return ConnectionResult.failure(describeProviderError(e));
    } finally {
      client.close();
    }
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
