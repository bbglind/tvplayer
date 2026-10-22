import 'dart:io';

import 'package:tvplayer_core/tvplayer_core.dart';

/// The IANA name of the device's time zone, e.g. `Europe/Stockholm`, or
/// `UTC` when it can't be determined.
///
/// On Linux this checks `TZ`, then the `/etc/localtime` symlink, then
/// `/etc/timezone`.
// Android needs a platform plugin (e.g. flutter_timezone); add it with the
// Android build.
String deviceTimeZone({
  Map<String, String>? environment,
  String localtimePath = '/etc/localtime',
  String timezonePath = '/etc/timezone',
}) {
  String? valid(String? name) {
    final n = name?.trim();
    if (n == null || n.isEmpty) return null;
    return GuideTime.findZone(n) == null ? null : n;
  }

  final env = environment ?? Platform.environment;
  var tz = env['TZ'];
  if (tz != null && tz.startsWith(':')) tz = tz.substring(1);
  // TZ may be a zone name or a path such as /usr/share/zoneinfo/Europe/Rome.
  if (valid(tz) ?? valid(_zoneFromPath(tz)) case final zone?) return zone;

  try {
    final target = Link(localtimePath).targetSync();
    if (valid(_zoneFromPath(target)) case final zone?) return zone;
  } on FileSystemException {
    // Not a symlink or missing.
  }
  try {
    if (valid(File(timezonePath).readAsStringSync()) case final zone?) {
      return zone;
    }
  } on FileSystemException {
    // Missing.
  }
  return 'UTC';
}

String? _zoneFromPath(String? path) {
  if (path == null) return null;
  const marker = 'zoneinfo/';
  final i = path.indexOf(marker);
  return i < 0 ? null : path.substring(i + marker.length);
}
