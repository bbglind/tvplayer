/// Normalises a channel name for fuzzy matching between a playlist and a
/// guide: lowercase, without a leading country prefix (`SE:`, `SE |`,
/// `|SE|`, `[SE]`, `(SE)`, `SE - `), without quality tags (`HD`, `FHD`,
/// `UHD`, `4K`, ...) and without spaces or punctuation.
///
/// Returns an empty string when nothing is left.
String normalizeChannelName(String name) {
  var s = name.toLowerCase().trim();
  s = s.replaceFirst(_prefix, '');
  s = s.replaceAll(_qualityTag, ' ');
  return s.replaceAll(_nonAlphanumeric, '');
}

final _prefix = RegExp(
  r'^(?:\|\s*[a-z]{2,3}\s*\||\[[a-z]{2,3}\]|\([a-z]{2,3}\)|'
  r'[a-z]{2,3}\s*[:|]|[a-z]{2,3}\s+-\s+)\s*',
);

final _qualityTag = RegExp(
  r'(?<![\p{L}\p{N}])'
  r'(?:uhd|fhd|hd|sd|hq|hevc|h\.?265|4k|8k|2160p|1080[pi]?|720p|50fps|hdr)'
  r'(?![\p{L}\p{N}])',
  unicode: true,
);

final _nonAlphanumeric = RegExp(r'[^\p{L}\p{N}]', unicode: true);
