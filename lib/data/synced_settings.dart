import 'app_settings.dart';

/// The settings that sync between devices, by their name in
/// [AppSettings.toJson]. Everything else stays on the device: layout
/// (sidebar, list widths, hidden lists), volume, playback statistics,
/// downloads and recording, the TMDB switch, pause and image cache (the
/// TMDB key isn't synced), SkipDB and TheIntroDB, and sync itself.
const syncedSettingNames = [
  'subtitleLanguages',
  'audioLanguages',
  'subtitlesOn',
  'playNextSeconds',
  'showRemainingTime',
  'movieSort',
  'seriesSort',
  'movieMySort',
  'seriesMySort',
  'showHiddenInGlobalSearch',
  'homeLayout',
  'tmdbPreferPosters',
  'guideTimeZone',
  'guideShiftHours',
];

/// The synced settings of [settings] as JSON values by name; null for an
/// unset one (e.g. the device's own time zone).
Map<String, Object?> syncedValues(AppSettings settings) {
  final json = settings.toJson();
  return {for (final name in syncedSettingNames) name: json[name]};
}

/// [settings] with the synced [values] (as from [syncedValues]) in place;
/// invalid values fall back to the defaults, as when reading the file.
AppSettings withSyncedValues(
  AppSettings settings,
  Map<String, Object?> values,
) {
  final json = settings.toJson();
  for (final MapEntry(:key, :value) in values.entries) {
    if (!syncedSettingNames.contains(key)) continue;
    if (value == null) {
      json.remove(key);
    } else {
      json[key] = value;
    }
  }
  return AppSettings.fromJson(json);
}
