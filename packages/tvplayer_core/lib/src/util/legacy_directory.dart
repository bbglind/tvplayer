import 'dart:io';

/// The outcome of [migrateLegacyDirectory].
enum LegacyMigrationResult {
  /// There was no old folder.
  none,

  /// The new folder already has data; nothing was touched.
  skipped,

  /// The old folder's contents are now in the new folder.
  migrated,

  /// Copying failed; the old folder is untouched and the new one unchanged.
  failed,
}

/// Copies one file; [File.copy] in production.
typedef FileCopier = Future<void> Function(File from, String to);

Future<void> _copyFile(File from, String to) => from.copy(to);

/// Moves the data of an earlier application ID from [from] to [to], unless
/// [to] already has data, which is never overwritten.
///
/// The tree is copied into a staging folder next to [to], checked, and
/// renamed into place; only then is [from] deleted. On failure the staging
/// folder is removed and [from] is left as it was, so the next start
/// tries again (as long as [to] is still empty).
Future<LegacyMigrationResult> migrateLegacyDirectory(
  Directory from,
  Directory to, {
  FileCopier copy = _copyFile,
}) async {
  if (!await from.exists()) return LegacyMigrationResult.none;
  if (await to.exists() && !await to.list().isEmpty) {
    return LegacyMigrationResult.skipped;
  }
  final staging = Directory('${to.path}.migrating');
  try {
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final target =
          '${staging.path}${entity.path.substring(from.path.length)}';
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await copy(entity, target);
        if (await File(target).length() != await entity.length()) {
          throw FileSystemException('Copy is incomplete', target);
        }
      } else if (entity is Link) {
        await Link(target).create(await entity.target());
      }
    }
    if (await to.exists()) await to.delete();
    await staging.rename(to.path);
  } on FileSystemException catch (e) {
    stderr.writeln(
      'Could not move ${from.path} to ${to.path}: ${e.message} (${e.path})',
    );
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } on FileSystemException {
      // Removed on the next attempt.
    }
    return LegacyMigrationResult.failed;
  }
  try {
    await from.delete(recursive: true);
  } on FileSystemException {
    // The data is moved; the leftover old folder is ignored from now on.
  }
  return LegacyMigrationResult.migrated;
}
