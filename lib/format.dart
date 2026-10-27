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

/// What is left of a movie or episode: `1 h 02 min left`, `18 min left`.
String formatTimeLeft(Duration left) {
  final minutes = (left.inSeconds / 60).ceil().clamp(1, 1 << 31);
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min left';
  return '$h h ${m.toString().padLeft(2, '0')} min left';
}

/// When something happened, relative to [now]: `just now`, `5 min ago`,
/// `1 h ago`, `yesterday`, `3 days ago`.
String formatAgo(DateTime time, DateTime now) {
  final d = now.difference(time);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  return '${d.inDays} days ago';
}

/// The start page greeting for the local hour [hour]: morning from 5,
/// afternoon from 12, evening from 18.
String greetingFor(int hour) => switch (hour) {
  >= 5 && < 12 => 'Good morning',
  >= 12 && < 18 => 'Good afternoon',
  _ => 'Good evening',
};

/// The time left of a movie or episode for the player's end time:
/// `-12:34`.
String formatRemaining(Duration position, Duration duration) {
  final left = duration - position;
  return '-${formatDuration(left.isNegative ? Duration.zero : left)}';
}

/// Short weekday names, Monday first.
const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Short month names, January first.
const monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// When something was last updated, both times in local time: `Today
/// 12:40`, `Yesterday 21:05`, else `Mon 20 Oct 14:05` (with the year when
/// it isn't [now]'s).
String formatUpdated(DateTime time, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${two(time.hour)}:${two(time.minute)}';
  final day = DateTime.utc(time.year, time.month, time.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today $hm';
  if (days == 1) return 'Yesterday $hm';
  final year = time.year == now.year ? '' : ' ${time.year}';
  return '${weekdayNames[time.weekday - 1]} ${time.day} '
      '${monthNames[time.month - 1]}$year $hm';
}

/// A size in decimal units, as file managers show it: `512 B`, `640 KB`,
/// `4.2 MB`, `2.1 GB`, `12 GB` (one decimal below 10).
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  if (unit == 0) return '$bytes B';
  final text = value < 10 ? value.toStringAsFixed(1) : '${value.round()}';
  return '$text ${units[unit]}';
}

/// Whole gigabytes: `5 GB`.
String formatGb(int bytes) => '${(bytes / 1e9).round()} GB';

/// A transfer rate: `4.2 MB/s`.
String formatSpeed(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/s';

/// Elapsed time as `0:12:34`.
String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}
