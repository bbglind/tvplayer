import 'dart:io';

import 'package:tvplayer_sync_server/tvplayer_sync_server.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
  await stdout.flush();
  exit(exitCode);
}
