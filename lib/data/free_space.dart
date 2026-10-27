import 'dart:io';

/// Free bytes on the disk holding a folder.
abstract interface class FreeSpace {
  /// The bytes free for the user at [path] (or its nearest existing parent);
  /// null when unknown.
  Future<int?> at(String path);
}

/// [FreeSpace] from `df` (Linux and Android).
class DfFreeSpace implements FreeSpace {
  const DfFreeSpace();

  @override
  Future<int?> at(String path) async {
    var dir = Directory(path);
    while (!await dir.exists() && dir.parent.path != dir.path) {
      dir = dir.parent;
    }
    try {
      final result = await Process.run('df', ['-P', '-k', dir.path]);
      if (result.exitCode != 0) return null;
      return parseDfAvailable(result.stdout as String);
    } on ProcessException {
      return null;
    }
  }
}

/// The available kilobytes, as bytes, from `df -P -k` output.
int? parseDfAvailable(String output) {
  final lines = output.trim().split('\n');
  if (lines.length < 2) return null;
  // Filesystem 1024-blocks Used Available Capacity Mounted-on; the name may
  // contain spaces, so count from the end.
  final fields = lines.last.trim().split(RegExp(r'\s+'));
  if (fields.length < 6) return null;
  final kb = int.tryParse(fields[fields.length - 3]);
  return kb == null ? null : kb * 1024;
}
