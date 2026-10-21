/// The kind of source a [ProviderConfig] describes.
enum ProviderType { xtream, m3u }

/// Connection details for a playlist provider.
///
/// Holds credentials, so it is deliberately not serializable: it lives in
/// memory only and [toString] never reveals the host, username, password or
/// playlist URL.
final class ProviderConfig {
  /// An Xtream Codes compatible panel. [host] may include a scheme and port,
  /// e.g. `http://example.com:8080`; `http` is assumed when no scheme is given.
  const ProviderConfig.xtream({
    required String this.host,
    required String this.username,
    required String this.password,
  }) : type = ProviderType.xtream,
       playlistUrl = null;

  /// A plain M3U/M3U8 playlist.
  const ProviderConfig.m3u({required String this.playlistUrl})
    : type = ProviderType.m3u,
      host = null,
      username = null,
      password = null;

  final ProviderType type;
  final String? host;
  final String? username;
  final String? password;
  final String? playlistUrl;

  @override
  String toString() => 'ProviderConfig(${type.name}, <redacted>)';
}
