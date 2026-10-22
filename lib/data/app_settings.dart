import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// User preferences that are not secret.
final class AppSettings {
  const AppSettings({
    this.guideTimeZone,
    this.guideShiftHours = 0,
    this.showPlaybackStats = false,
  });

  /// IANA zone for guide times, e.g. `Europe/Stockholm`; null means the
  /// device's zone.
  final String? guideTimeZone;

  /// Whole hours added to every guide time, for providers whose times are
  /// wrong.
  final int guideShiftHours;

  static const maxShiftHours = 12;

  /// Whether the player shows mpv's dropped-frame counters.
  final bool showPlaybackStats;

  AppSettings copyWith({
    String? Function()? guideTimeZone,
    int? guideShiftHours,
    bool? showPlaybackStats,
  }) => AppSettings(
    guideTimeZone: guideTimeZone == null ? this.guideTimeZone : guideTimeZone(),
    guideShiftHours: guideShiftHours ?? this.guideShiftHours,
    showPlaybackStats: showPlaybackStats ?? this.showPlaybackStats,
  );

  Map<String, Object?> toJson() => {
    'guideTimeZone': ?guideTimeZone,
    'guideShiftHours': guideShiftHours,
    'showPlaybackStats': showPlaybackStats,
  };

  /// Lenient inverse of [toJson]: unknown or invalid values use defaults.
  factory AppSettings.fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    final zone = json['guideTimeZone'];
    final shift = json['guideShiftHours'];
    return AppSettings(
      guideTimeZone: zone is String && zone.isNotEmpty ? zone : null,
      guideShiftHours: shift is int && shift.abs() <= maxShiftHours ? shift : 0,
      showPlaybackStats: json['showPlaybackStats'] == true,
    );
  }
}

/// Persists [AppSettings].
abstract interface class SettingsStorage {
  /// The saved settings, or defaults when none are saved or they can't be
  /// read.
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

/// [SettingsStorage] in a JSON file in the app support directory.
class FileSettingsStorage implements SettingsStorage {
  FileSettingsStorage([Future<Directory> Function()? directory])
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> get _file async =>
      File('${(await _directory()).path}/settings.json');

  @override
  Future<AppSettings> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return const AppSettings();
      return AppSettings.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()));
    await tmp.rename(file.path);
  }
}
