import 'dart:io';

/// Starts a process; [Process.start] in production, a fake in tests.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// Command line for one external mpv instance.
///
/// The stream URL is deliberately not part of it: anything in argv is
/// readable by every local user via `ps` or `/proc/<pid>/cmdline`, so the URL
/// is sent over the IPC socket with `loadfile` instead (see `--idle=once`).
class MpvLaunchConfig {
  const MpvLaunchConfig({
    required this.title,
    required this.ipcPath,
    this.hwdec = 'vaapi',
    this.wid,
    this.volume,
    this.executable = 'mpv',
  });

  /// Window title, shown literally (mpv property expansion is escaped).
  final String title;

  /// Unix socket path for `--input-ipc-server`.
  final String ipcPath;
  final String hwdec;

  /// X11 window id to embed the video into (`--wid`). Null opens mpv in its
  /// own window. Only meaningful on X11.
  final int? wid;

  /// Start volume in percent; null for mpv's default.
  final int? volume;
  final String executable;

  /// Highest volume in percent: no boost, so the slider's end is full
  /// volume.
  static const maxVolume = 100;

  List<String> get arguments => [
    '--hwdec=$hwdec',
    '--force-window=immediate',
    if (wid != null) ...[
      '--wid=$wid',
      // Leave mouse and keys to the app: clicks then reach the native video
      // area (double-click for fullscreen) and Esc reaches Flutter.
      '--input-cursor=no',
      '--input-vo-keyboard=no',
      // mpv sees no mouse movement, so it would hide the cursor for good;
      // the app shows and hides it on the video area instead.
      '--cursor-autohide=no',
    ],
    '--volume-max=$maxVolume',
    if (volume case final v?) '--volume=${v.clamp(0, maxVolume)}',
    '--title=${escapePropertyExpansion(title)}',
    '--input-ipc-server=$ipcPath',
    // Wait for the URL over IPC, then quit when playback ends.
    '--idle=once',
    // mpv prints the URL it plays to the terminal; keep it silent.
    '--terminal=no',
  ];

  /// mpv expands `${...}` in the title; `$$` is a literal `$`.
  static String escapePropertyExpansion(String text) =>
      text.replaceAll(r'$', r'$$');
}

/// mpv could not be started. [message] never contains arguments or the URL.
class MpvLaunchException implements Exception {
  const MpvLaunchException(this.message, {this.notInstalled = false});

  final String message;
  final bool notInstalled;

  @override
  String toString() => message;
}

/// errno for "No such file or directory".
const _enoent = 2;

/// Starts mpv for [config]. Throws [MpvLaunchException].
Future<Process> launchMpv(
  MpvLaunchConfig config, {
  ProcessStarter start = Process.start,
}) async {
  final Process process;
  try {
    process = await start(config.executable, config.arguments);
  } on ProcessException catch (e) {
    // ProcessException.toString() echoes the arguments; only use the code.
    if (e.errorCode == _enoent) {
      throw const MpvLaunchException(
        'mpv is not installed. Install it with your package manager '
        '(for example: sudo apt install mpv) and try again.',
        notInstalled: true,
      );
    }
    throw MpvLaunchException('Could not start mpv (error ${e.errorCode}).');
  }
  // Output is never shown; drain it so mpv can't block on a full pipe.
  process.stdout.drain<void>().ignore();
  process.stderr.drain<void>().ignore();
  return process;
}
