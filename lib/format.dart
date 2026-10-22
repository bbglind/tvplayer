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
