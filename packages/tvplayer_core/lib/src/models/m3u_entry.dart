/// One entry of an M3U playlist.
final class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    this.tvgId,
    this.tvgName,
    this.tvgLogo,
    this.groupTitle,
    this.duration,
    this.attributes = const {},
  });

  /// Display name (text after the comma of the `#EXTINF` line).
  final String name;

  /// Stream URL. May contain credentials, so it is never part of [toString].
  final String url;
  final String? tvgId;
  final String? tvgName;
  final String? tvgLogo;
  final String? groupTitle;

  /// Duration from `#EXTINF`; -1 or null for live streams.
  final int? duration;

  /// All attributes of the `#EXTINF` line, including the ones above.
  final Map<String, String> attributes;

  @override
  String toString() => 'M3uEntry($name, group: $groupTitle)';
}
