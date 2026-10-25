import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// User preferences that are not secret.
final class AppSettings {
  const AppSettings({
    this.guideTimeZone,
    this.guideShiftHours = 0,
    this.showPlaybackStats = false,
    this.subtitleLanguages = TrackPreferences.defaultSubtitleLanguages,
    this.audioLanguages = const [],
    this.subtitlesOn = true,
    this.sidebarCollapsed = false,
    this.sidebarWidth = defaultSidebarWidth,
    this.hiddenCategoryLists = const {},
    this.categoryListWidth = defaultCategoryListWidth,
    this.guideChannelWidth = defaultGuideChannelWidth,
    this.showHiddenInGlobalSearch = false,
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

  /// Preferred subtitle languages in order, as ISO 639-1 codes.
  final List<String> subtitleLanguages;

  /// Preferred audio languages in order, as ISO 639-1 codes; empty keeps
  /// each stream's default audio.
  final List<String> audioLanguages;

  /// Whether subtitles are shown by default.
  final bool subtitlesOn;

  /// Whether the sidebar shows icons only, chosen by the user.
  final bool sidebarCollapsed;

  /// Width of the full sidebar, between [minSidebarWidth] and
  /// [maxSidebarWidth].
  final double sidebarWidth;

  static const defaultSidebarWidth = 232.0;
  static const minSidebarWidth = 200.0;
  static const maxSidebarWidth = 360.0;

  /// Sections whose category list is hidden: `live`, `movies`, `series`.
  final Set<String> hiddenCategoryLists;

  /// Width of the category list, shared by Live TV, Movies and Series.
  final double categoryListWidth;

  static const defaultCategoryListWidth = 260.0;
  static const minCategoryListWidth = 200.0;
  static const maxCategoryListWidth = 420.0;

  /// Width of the channel column in the TV guide.
  final double guideChannelWidth;

  static const defaultGuideChannelWidth = 200.0;
  static const minGuideChannelWidth = 140.0;
  static const maxGuideChannelWidth = 400.0;

  /// Whether global search also finds items in hidden provider categories.
  final bool showHiddenInGlobalSearch;

  TrackPreferences get trackPreferences => TrackPreferences(
    subtitleLanguages: subtitleLanguages,
    audioLanguages: audioLanguages,
    subtitlesOn: subtitlesOn,
  );

  AppSettings copyWith({
    String? Function()? guideTimeZone,
    int? guideShiftHours,
    bool? showPlaybackStats,
    List<String>? subtitleLanguages,
    List<String>? audioLanguages,
    bool? subtitlesOn,
    bool? sidebarCollapsed,
    double? sidebarWidth,
    Set<String>? hiddenCategoryLists,
    double? categoryListWidth,
    double? guideChannelWidth,
    bool? showHiddenInGlobalSearch,
  }) => AppSettings(
    guideTimeZone: guideTimeZone == null ? this.guideTimeZone : guideTimeZone(),
    guideShiftHours: guideShiftHours ?? this.guideShiftHours,
    showPlaybackStats: showPlaybackStats ?? this.showPlaybackStats,
    subtitleLanguages: subtitleLanguages ?? this.subtitleLanguages,
    audioLanguages: audioLanguages ?? this.audioLanguages,
    subtitlesOn: subtitlesOn ?? this.subtitlesOn,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    hiddenCategoryLists: hiddenCategoryLists ?? this.hiddenCategoryLists,
    categoryListWidth: categoryListWidth ?? this.categoryListWidth,
    guideChannelWidth: guideChannelWidth ?? this.guideChannelWidth,
    showHiddenInGlobalSearch:
        showHiddenInGlobalSearch ?? this.showHiddenInGlobalSearch,
  );

  Map<String, Object?> toJson() => {
    'guideTimeZone': ?guideTimeZone,
    'guideShiftHours': guideShiftHours,
    'showPlaybackStats': showPlaybackStats,
    'subtitleLanguages': subtitleLanguages,
    'audioLanguages': audioLanguages,
    'subtitlesOn': subtitlesOn,
    'sidebarCollapsed': sidebarCollapsed,
    'sidebarWidth': sidebarWidth,
    'hiddenCategoryLists': hiddenCategoryLists.toList(),
    'categoryListWidth': categoryListWidth,
    'guideChannelWidth': guideChannelWidth,
    'showHiddenInGlobalSearch': showHiddenInGlobalSearch,
  };

  /// Lenient inverse of [toJson]: unknown or invalid values use defaults.
  factory AppSettings.fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    final zone = json['guideTimeZone'];
    final shift = json['guideShiftHours'];
    final hidden = json['hiddenCategoryLists'];
    return AppSettings(
      guideTimeZone: zone is String && zone.isNotEmpty ? zone : null,
      guideShiftHours: shift is int && shift.abs() <= maxShiftHours ? shift : 0,
      showPlaybackStats: json['showPlaybackStats'] == true,
      subtitleLanguages:
          _languages(json['subtitleLanguages']) ??
          TrackPreferences.defaultSubtitleLanguages,
      audioLanguages: _languages(json['audioLanguages']) ?? const [],
      subtitlesOn: json['subtitlesOn'] != false,
      sidebarCollapsed: json['sidebarCollapsed'] == true,
      sidebarWidth: _width(
        json['sidebarWidth'],
        minSidebarWidth,
        maxSidebarWidth,
        defaultSidebarWidth,
      ),
      hiddenCategoryLists: hidden is List
          ? hidden.whereType<String>().toSet()
          : const {},
      categoryListWidth: _width(
        json['categoryListWidth'],
        minCategoryListWidth,
        maxCategoryListWidth,
        defaultCategoryListWidth,
      ),
      guideChannelWidth: _width(
        json['guideChannelWidth'],
        minGuideChannelWidth,
        maxGuideChannelWidth,
        defaultGuideChannelWidth,
      ),
      showHiddenInGlobalSearch: json['showHiddenInGlobalSearch'] == true,
    );
  }

  /// A width from JSON, clamped to [min]..[max]; [fallback] when invalid.
  static double _width(Object? json, double min, double max, double fallback) =>
      json is num && json.isFinite ? json.toDouble().clamp(min, max) : fallback;

  /// Known language codes from a JSON list, without duplicates; null when
  /// [json] isn't a list.
  static List<String>? _languages(Object? json) {
    if (json is! List) return null;
    final codes = <String>{};
    for (final item in json) {
      if (Language.parse(item is String ? item : null) case final l?) {
        codes.add(l.code);
      }
    }
    return codes.toList();
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
