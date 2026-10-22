import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Converts guide times (stored in UTC) for display in an IANA time zone,
/// such as `Europe/Stockholm`, using the bundled time zone database, so
/// daylight saving changes are applied automatically.
///
/// [shiftHours] moves every programme by whole hours, for providers whose
/// guide times are wrong. It applies to the programme times themselves:
/// use [adjust] before showing or placing a programme time and [unadjust]
/// to look up what airs at a real moment.
final class GuideTime {
  GuideTime(this.location, {this.shiftHours = 0});

  /// [GuideTime] for the zone named [zoneName]; UTC when it is unknown.
  factory GuideTime.named(String zoneName, {int shiftHours = 0}) {
    ensureInitialized();
    return GuideTime(
      findZone(zoneName) ?? findZone('UTC') ?? tz.UTC,
      shiftHours: shiftHours,
    );
  }

  final tz.Location location;
  final int shiftHours;

  String get zoneName => location.name;

  Duration get _shift => Duration(hours: shiftHours);

  /// Loads the time zone database. Safe to call more than once.
  static void ensureInitialized() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }

  static bool _initialized = false;

  /// The zone named [name] (e.g. `Europe/Stockholm`), or null if unknown.
  static tz.Location? findZone(String name) {
    ensureInitialized();
    return tz.timeZoneDatabase.locations[name];
  }

  /// All known zone names, sorted.
  static List<String> zoneNames() {
    ensureInitialized();
    return tz.timeZoneDatabase.locations.keys.toList()..sort();
  }

  /// A programme time with the shift applied (still a UTC instant).
  DateTime adjust(DateTime utc) => utc.toUtc().add(_shift);

  /// The guide (unshifted) time corresponding to the real moment [time].
  DateTime unadjust(DateTime time) => time.toUtc().subtract(_shift);

  /// A programme time, shifted, in the display zone.
  tz.TZDateTime toDisplay(DateTime utc) =>
      tz.TZDateTime.from(adjust(utc), location);

  /// A real moment (e.g. now) in the display zone, without shift.
  tz.TZDateTime local(DateTime time) => tz.TZDateTime.from(time, location);

  /// `HH:mm` of a programme time in the display zone.
  String formatHm(DateTime utc) => _hm(toDisplay(utc));

  /// `HH:mm–HH:mm` for a programme running from [start] to [stop].
  String formatRange(DateTime start, DateTime stop) =>
      '${formatHm(start)}–${formatHm(stop)}';

  /// Midnight of the display-zone day containing the real moment [time], as
  /// a UTC instant.
  DateTime startOfDay(DateTime time) {
    final l = local(time);
    return tz.TZDateTime(location, l.year, l.month, l.day).toUtc();
  }

  /// Start of the display-zone hour containing [time], as a UTC instant.
  /// Correct for zones with non-whole-hour offsets too.
  DateTime startOfHour(DateTime time) {
    final l = local(time);
    return l
        .subtract(
          Duration(
            minutes: l.minute,
            seconds: l.second,
            milliseconds: l.millisecond,
            microseconds: l.microsecond,
          ),
        )
        .toUtc();
  }

  /// `HH:mm` of the real moment [time] in the display zone.
  String formatLocalHm(DateTime time) => _hm(local(time));

  /// Short UTC offset of the display zone at [time], e.g. `+01:00`.
  String offsetAt(DateTime time) {
    final offset = local(time).timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }

  static String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
