import '../epg/guide_time.dart';
import 'playlist_status.dart';

/// How long automatic refresh leaves a part alone after it failed, so a
/// provider that is down isn't asked again every check.
const autoRetryAfter = Duration(hours: 1);

/// The [available] parts that automatic refresh [mode] should download
/// now, in [PlaylistPart] order. [atStart] is the check made when the app
/// starts.
///
/// "Every 6 hours" refreshes a part once 6 hours have passed since its
/// last successful download; "Daily" once that download was on an earlier
/// calendar day than [now] in [deviceTime] (the device's time zone), so the
/// first check of a new day refreshes. Either refreshes a part without a
/// download, or when the clock went back. "On app start" refreshes
/// everything at start. Off never does: parts without any data are
/// downloaded by their pages, not here. Parts downloaded at or after
/// [freshSince] (e.g. while the app was starting) are never due.
List<PlaylistPart> dueParts({
  required AutoRefresh mode,
  required PlaylistStatus status,
  required Set<PlaylistPart> available,
  required DateTime now,
  required GuideTime deviceTime,
  bool atStart = false,
  DateTime? freshSince,
}) {
  final today = _date(deviceTime.local(now));

  bool stale(DateTime updated) => switch (mode) {
    AutoRefresh.daily => _date(deviceTime.local(updated)).isBefore(today),
    AutoRefresh.every6Hours => now.difference(updated) >= mode.interval!,
    AutoRefresh.off || AutoRefresh.onStart => false,
  };

  bool due(PartStatus s) {
    final updated = s.updatedAt;
    if (freshSince != null &&
        updated != null &&
        !updated.isBefore(freshSince) &&
        !updated.isAfter(now)) {
      return false;
    }
    if (mode == AutoRefresh.onStart) return atStart;
    if (mode == AutoRefresh.off) return false;
    if (s.failedAt case final f?
        when !f.isAfter(now) && now.difference(f) < autoRetryAfter) {
      return false;
    }
    return updated == null || updated.isAfter(now) || stale(updated);
  }

  return [
    for (final p in PlaylistPart.values)
      if (available.contains(p) && due(status.part(p))) p,
  ];
}

/// The calendar date of [local], as a UTC midnight for comparing.
DateTime _date(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day);

/// A refresh returned nothing where there was data before. Providers
/// sometimes answer an outage with an empty list; the old data is kept.
class EmptyResultException implements Exception {
  const EmptyResultException();

  @override
  String toString() => 'EmptyResultException: the provider sent nothing';
}

/// Throws [EmptyResultException] when a refresh would replace [before]
/// items with none.
void checkNotEmptied({required int before, required int after}) {
  if (before > 0 && after == 0) throw const EmptyResultException();
}
