import 'dart:convert';
import 'dart:io';

/// The server's settings, from a JSON file like `config.example.json`.
final class ServerConfig {
  const ServerConfig({
    this.host = '0.0.0.0',
    this.port = 8787,
    this.dataDir = '/var/lib/tvplayer-sync',
  });

  /// The address to listen on; `0.0.0.0` for every network interface.
  final String host;
  final int port;

  /// Where the database (`sync.sqlite`) is kept.
  final String dataDir;

  String get databasePath => '$dataDir/sync.sqlite';

  /// Reads [path]. Throws [FormatException] with a message for the user.
  static ServerConfig load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FormatException('Config file not found: $path');
    }
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw FormatException('$path is not valid JSON: ${e.message}');
    }
    if (json is! Map) throw FormatException('$path must hold a JSON object');
    const defaults = ServerConfig();
    final host = json['host'] ?? defaults.host;
    final port = json['port'] ?? defaults.port;
    final dataDir = json['dataDir'] ?? defaults.dataDir;
    if (host is! String || host.isEmpty) {
      throw FormatException('$path: "host" must be an address');
    }
    if (port is! int || port < 1 || port > 65535) {
      throw FormatException('$path: "port" must be a number from 1 to 65535');
    }
    if (dataDir is! String || dataDir.isEmpty) {
      throw FormatException('$path: "dataDir" must be a folder');
    }
    return ServerConfig(host: host, port: port, dataDir: dataDir);
  }
}
