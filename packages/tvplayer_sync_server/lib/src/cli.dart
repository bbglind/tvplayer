import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'api.dart';
import 'config.dart';
import 'store.dart';

const serverVersion = '1.0.0';

const defaultConfigPath = '/etc/tvplayer-sync/config.json';

/// Runs the command line [args]; returns the exit code.
Future<int> runCli(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'tvplayer_sync_server',
          'Sync server for tvplayer (version $serverVersion).',
        )
        ..argParser.addOption(
          'config',
          abbr: 'c',
          help: 'The config file.',
          defaultsTo: defaultConfigPath,
        )
        ..argParser.addFlag(
          'version',
          negatable: false,
          help: 'Print the version.',
        )
        ..addCommand(_ServeCommand())
        ..addCommand(_TokenCommand())
        ..addCommand(_BackupCommand())
        ..addCommand(_StatusCommand());
  try {
    final parsed = runner.parse(args);
    if (parsed['version'] == true) {
      stdout.writeln(serverVersion);
      return 0;
    }
    return await runner.runCommand(parsed) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 78;
  }
}

/// The config named by `--config`, and its database (the data folder is
/// made when missing).
(ServerConfig, SyncStore) _open(Command<int> command) {
  final config = ServerConfig.load(command.globalResults!['config'] as String);
  Directory(config.dataDir).createSync(recursive: true);
  return (config, SyncStore.open(config.databasePath));
}

class _ServeCommand extends Command<int> {
  @override
  String get name => 'serve';

  @override
  String get description => 'Run the server.';

  @override
  Future<int> run() async {
    final (config, store) = _open(this);
    final server = await shelf_io.serve(
      syncApi(store, log: (line) => stdout.writeln(line)),
      config.host,
      config.port,
    );
    server.autoCompress = true;
    stdout.writeln(
      'tvplayer sync server $serverVersion listening on '
      '${config.host}:${config.port}',
    );
    final done = Completer<void>();
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signal.watch().listen((_) {
        if (!done.isCompleted) done.complete();
      });
    }
    await done.future;
    await server.close();
    store.close();
    stdout.writeln('Stopped.');
    return 0;
  }
}

class _TokenCommand extends Command<int> {
  _TokenCommand() {
    addSubcommand(_TokenCreateCommand());
    addSubcommand(_TokenListCommand());
    addSubcommand(_TokenRevokeCommand());
  }

  @override
  String get name => 'token';

  @override
  String get description => 'Create, list or revoke login tokens.';
}

class _TokenCreateCommand extends Command<int> {
  _TokenCreateCommand() {
    argParser.addOption(
      'name',
      abbr: 'n',
      help: 'What the token is for, e.g. laptop or phone.',
      mandatory: true,
    );
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a token for one device.';

  @override
  int run() {
    final (_, store) = _open(this);
    try {
      final token = store.createToken(argResults!['name'] as String);
      stdout
        ..writeln(token)
        ..writeln()
        ..writeln(
          'Enter this token in tvplayer › Settings › Sync. It is shown only '
          'once.',
        );
      return 0;
    } on ArgumentError catch (e) {
      stderr.writeln(e.message);
      return 1;
    } finally {
      store.close();
    }
  }
}

class _TokenListCommand extends Command<int> {
  @override
  String get name => 'list';

  @override
  String get description => 'List the tokens (not the tokens themselves).';

  @override
  int run() {
    final (_, store) = _open(this);
    try {
      final tokens = store.tokens();
      if (tokens.isEmpty) stdout.writeln('No tokens.');
      for (final t in tokens) {
        stdout.writeln(
          '${t.name}\tcreated ${_date(t.created)}\t'
          'last used ${t.lastUsed == null ? 'never' : _date(t.lastUsed!)}',
        );
      }
      return 0;
    } finally {
      store.close();
    }
  }
}

class _TokenRevokeCommand extends Command<int> {
  @override
  String get name => 'revoke';

  @override
  String get description =>
      'Delete a token: tvplayer_sync_server token revoke <name>';

  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Give the name of one token.');
    final (_, store) = _open(this);
    try {
      if (!store.revokeToken(rest.single)) {
        stderr.writeln('No token named ${rest.single}.');
        return 1;
      }
      stdout.writeln('Revoked ${rest.single}.');
      return 0;
    } finally {
      store.close();
    }
  }
}

class _BackupCommand extends Command<int> {
  @override
  String get name => 'backup';

  @override
  String get description =>
      'Copy the database to a new file, also while the server runs: '
      'tvplayer_sync_server backup <file>';

  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Give the file to write.');
    final (_, store) = _open(this);
    try {
      store.backup(rest.single);
      stdout.writeln('Saved ${rest.single}.');
      return 0;
    } on ArgumentError catch (e) {
      stderr.writeln(e.message);
      return 1;
    } finally {
      store.close();
    }
  }
}

class _StatusCommand extends Command<int> {
  @override
  String get name => 'status';

  @override
  String get description => 'Show how many records each space holds.';

  @override
  int run() {
    final (config, store) = _open(this);
    try {
      stdout.writeln('Database: ${config.databasePath}');
      final counts = store.counts();
      if (counts.isEmpty) stdout.writeln('No records yet.');
      for (final MapEntry(:key, :value) in counts.entries) {
        stdout.writeln('$key\t$value records');
      }
      stdout.writeln('${store.tokens().length} tokens');
      return 0;
    } finally {
      store.close();
    }
  }
}

String _date(DateTime t) => t.toLocal().toString().substring(0, 16);
