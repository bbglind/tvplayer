import 'dart:convert';

/// Characters not allowed in file names on Linux, Android (FAT/exFAT
/// cards) or Windows, plus control characters.
final _unsafe = RegExp(r'[/\\:*?"<>|\x00-\x1f\x7f]');
final _spaces = RegExp(r'\s+');
final _extension = RegExp(r'^[a-z0-9]{1,5}$');

/// [name] as a safe file or folder name: unsafe characters become spaces,
/// runs of white space one space, leading and trailing dots and spaces
/// are dropped, and it is cut to [maxBytes] of UTF-8 (never inside a
/// character). "Untitled" when nothing is left.
String safeFileName(String name, {int maxBytes = 150}) {
  var s = name.replaceAll(_unsafe, ' ').replaceAll(_spaces, ' ');
  s = _trimDotsAndSpaces(s);
  if (utf8.encode(s).length > maxBytes) {
    final out = StringBuffer();
    var bytes = 0;
    for (final rune in s.runes) {
      final char = String.fromCharCode(rune);
      final size = utf8.encode(char).length;
      if (bytes + size > maxBytes) break;
      out.write(char);
      bytes += size;
    }
    s = _trimDotsAndSpaces(out.toString());
  }
  return s.isEmpty ? 'Untitled' : s;
}

String _trimDotsAndSpaces(String s) {
  var start = 0, end = s.length;
  bool skip(int i) => s[i] == ' ' || s[i] == '.';
  while (start < end && skip(start)) {
    start++;
  }
  while (end > start && skip(end - 1)) {
    end--;
  }
  return s.substring(start, end);
}

/// The provider's container extension when it looks like one (`mkv`,
/// `mp4`, `ts`), else [fallback].
String safeExtension(String? extension, {required String fallback}) {
  final e = extension?.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  return e != null && _extension.hasMatch(e) ? e : fallback;
}

/// Subfolders of the downloads folder.
abstract final class DownloadFolders {
  static const movies = 'Movies';
  static const series = 'Series';
  static const recordings = 'Recordings';
}

/// `Movies/<Title> (<Year>).<ext>`, relative to the downloads folder.
String moviePath(String title, int? year, String extension) {
  final name = year == null ? title : '$title ($year)';
  return '${DownloadFolders.movies}/${safeFileName(name)}.$extension';
}

/// `Series/<Series>/Season 01/<Series> - S01E02 - <Episode>.<ext>`.
String episodePath(
  String series,
  int season,
  int episode,
  String? episodeTitle,
  String extension,
) {
  String two(int n) => n.toString().padLeft(2, '0');
  final code = 'S${two(season)}E${two(episode)}';
  final name = [
    series,
    code,
    if (episodeTitle != null && episodeTitle.trim().isNotEmpty) episodeTitle,
  ].join(' - ');
  return '${DownloadFolders.series}/${safeFileName(series)}/'
      'Season ${two(season)}/${safeFileName(name)}.$extension';
}

/// `Recordings/<Channel> - <Programme> - 2026-10-27 20-00.ts`; [start] is
/// the local start time.
String recordingPath(
  String channel,
  String? programme,
  DateTime start,
  String extension,
) {
  String two(int n) => n.toString().padLeft(2, '0');
  final when =
      '${start.year}-${two(start.month)}-${two(start.day)} '
      '${two(start.hour)}-${two(start.minute)}';
  final name = [
    channel,
    if (programme != null && programme.trim().isNotEmpty) programme,
    when,
  ].join(' - ');
  return '${DownloadFolders.recordings}/${safeFileName(name)}.$extension';
}

/// [path], or with " (2)", " (3)"… before the extension while [taken]
/// says that name is in use.
String uniquePath(String path, bool Function(String path) taken) {
  if (!taken(path)) return path;
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  final hasExt = dot > slash + 1;
  final stem = hasExt ? path.substring(0, dot) : path;
  final ext = hasExt ? path.substring(dot) : '';
  for (var n = 2; ; n++) {
    final candidate = '$stem ($n)$ext';
    if (!taken(candidate)) return candidate;
  }
}
