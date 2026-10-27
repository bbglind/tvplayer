import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The default folder for downloads and recordings: `tvplayer` in the
/// user's videos folder.
///
/// The videos folder is `XDG_VIDEOS_DIR`, else the one set in
/// `user-dirs.dirs` (in `XDG_CONFIG_HOME`, default `~/.config`), else
/// `~/Videos`.
String defaultDownloadFolder({
  Map<String, String>? environment,
  String? userDirsPath,
}) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? '';
  String expand(String path) => path.replaceAll(r'$HOME', home);

  String? videos;
  if (env['XDG_VIDEOS_DIR'] case final dir? when dir.trim().isNotEmpty) {
    videos = expand(dir.trim());
  } else {
    final config = env['XDG_CONFIG_HOME']?.trim();
    final path =
        userDirsPath ??
        '${config == null || config.isEmpty ? '$home/.config' : config}'
            '/user-dirs.dirs';
    try {
      for (final line in File(path).readAsLinesSync()) {
        final m = RegExp(r'^\s*XDG_VIDEOS_DIR\s*=\s*"(.*)"').firstMatch(line);
        if (m != null && m.group(1)!.isNotEmpty) videos = expand(m.group(1)!);
      }
    } on FileSystemException {
      // No user-dirs.dirs.
    }
  }
  // user-dirs.dirs points at $HOME itself when the folder is disabled.
  if (videos == null || videos == home || videos == '$home/') {
    videos = '$home/Videos';
  }
  return '${videos.replaceFirst(RegExp(r'/+$'), '')}/tvplayer';
}

/// The default folder for downloads and recordings on Android: `tvplayer`
/// in the app's own folder on shared storage, which needs no permission
/// (and is removed with the app), else in its private documents folder.
Future<String> androidDownloadFolder() async {
  final dir =
      await getExternalStorageDirectory() ??
      await getApplicationDocumentsDirectory();
  return '${dir.path}/tvplayer';
}
