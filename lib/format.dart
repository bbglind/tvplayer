/// Formats a duration as `h:mm:ss` or `m:ss`.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$s';
  return '$m:$s';
}

/// Formats mpv `video-params/w` and `video-params/h` as `WxH`, or `-` when
/// either is unavailable.
String formatResolution(String w, String h) {
  if (w.isEmpty || h.isEmpty) return '-';
  return '${w}x$h';
}

/// mpv dropped-frame counters as `dropped (vo/dec): 3 / 0`, with `-` for an
/// unknown count.
String formatDrops(int? vo, int? decoder) =>
    'dropped (vo/dec): ${vo ?? '-'} / ${decoder ?? '-'}';

/// Season and episode as `S01E02`.
String formatEpisodeCode(int season, int episode) =>
    'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

/// A length as `1 h 30 min` or `45 min`.
String formatRuntime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// A count with thousands separators: `36,000`.
String formatCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// [n] and the noun, singular for one: `1 movie`, `2,000 movies`.
String formatCountOf(int n, String singular, String plural) =>
    '${formatCount(n)} ${n == 1 ? singular : plural}';
