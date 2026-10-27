import 'dart:io';

import 'package:tvplayer_core/tvplayer_core.dart';

/// The IANA name of the device's time zone, e.g. `Europe/Stockholm`, or
/// `UTC` when it can't be determined.
///
/// This checks `TZ`, then the `/etc/localtime` symlink, then
/// `/etc/timezone` (Linux), then [androidZone]: by default the zone set in
/// Android's settings, on Android only.
String deviceTimeZone({
  Map<String, String>? environment,
  String localtimePath = '/etc/localtime',
  String timezonePath = '/etc/timezone',
  String? Function()? androidZone,
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
  final android = androidZone ?? (Platform.isAndroid ? _androidZone : null);
  if (valid(android?.call()) case final zone?) return zone;
  return 'UTC';
}

/// The `persist.sys.timezone` system property, which Android's date and
/// time settings set; null when it can't be read.
String? _androidZone() {
  try {
    final result = Process.runSync('getprop', ['persist.sys.timezone']);
    return result.exitCode == 0 ? result.stdout as String : null;
  } on ProcessException {
    return null;
  }
}

String? _zoneFromPath(String? path) {
  if (path == null) return null;
  const marker = 'zoneinfo/';
  final i = path.indexOf(marker);
  return i < 0 ? null : path.substring(i + marker.length);
}
