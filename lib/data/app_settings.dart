import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'home_layout.dart';

export 'home_layout.dart';

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
    this.movieSort = VodSort.recent,
    this.seriesSort = VodSort.recent,
    this.movieMySort = VodSort.myOrder,
    this.seriesMySort = VodSort.myOrder,
    this.homeLayout = HomeLayout.defaults,
    this.playerVolume = defaultPlayerVolume,
    this.showRemainingTime = false,
    this.playNextSeconds = defaultPlayNextSeconds,
    this.downloadFolder,
    this.endMarginMinutes = defaultEndMarginMinutes,
    this.startMarginMinutes = defaultStartMarginMinutes,
    this.maxRecordingHours = defaultMaxRecordingHours,
    this.minFreeGb = defaultMinFreeGb,
    this.tmdbEnabled = false,
    this.tmdbPreferPosters = false,
    this.tmdbPaused = false,
    this.tmdbImageCacheMb = defaultTmdbImageCacheMb,
    this.skipDbEnabled = true,
    this.introDbEnabled = true,
    this.syncEnabled = false,
    this.syncServer,
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

  /// Sort order of the Movies tab.
  final VodSort movieSort;

  /// Sort order of the Series tab.
  final VodSort seriesSort;

  /// Sort order of the Movies tab in one of my categories.
  final VodSort movieMySort;

  /// Sort order of the Series tab in one of my categories.
  final VodSort seriesMySort;

  /// Order and visibility of the start page rows.
  final HomeLayout homeLayout;

  /// Player volume in percent, 0–[maxPlayerVolume], kept across restarts.
  final int playerVolume;

  static const defaultPlayerVolume = 100;
  static const maxPlayerVolume = 100;

  /// Whether the player's end time shows the time left (`-12:34`) rather
  /// than the duration.
  final bool showRemainingTime;

  /// Seconds before the end of an episode at which the next one is
  /// offered with a countdown (one of [playNextChoices]); null for off.
  final int? playNextSeconds;

  /// Where downloads and recordings are saved; null for the default
  /// (`~/Videos/tvplayer`, or the XDG videos folder).
  final String? downloadFolder;

  /// Minutes recorded and saved after a programme's end (one of
  /// [endMarginChoices]).
  final int endMarginMinutes;

  static const defaultEndMarginMinutes = 15;
  static const endMarginChoices = [0, 5, 10, 15, 20, 30, 45, 60];

  /// Minutes saved before a programme's start, from the archive (one of
  /// [startMarginChoices]).
  final int startMarginMinutes;

  static const defaultStartMarginMinutes = 2;
  static const startMarginChoices = [0, 1, 2, 5, 10];

  /// Hours after which a recording stops in any case (one of
  /// [maxRecordingChoices]).
  final int maxRecordingHours;

  static const defaultMaxRecordingHours = 4;
  static const maxRecordingChoices = [1, 2, 3, 4, 6, 8, 12];

  /// Gigabytes kept free on the disk of the downloads (one of
  /// [minFreeChoices]): below it downloads pause and recordings stop.
  final int minFreeGb;

  static const defaultMinFreeGb = 5;
  static const minFreeChoices = [1, 2, 5, 10, 20, 50];

  /// Whether TMDB fills in details (with the key in the keyring).
  final bool tmdbEnabled;

  /// Whether TMDB posters are shown wherever TMDB has one, rather than
  /// only where the provider has none.
  final bool tmdbPreferPosters;

  /// Whether the user paused the background fetch of TMDB info.
  final bool tmdbPaused;

  /// Size limit of the TMDB image cache in MB (one of
  /// [tmdbImageCacheChoices]).
  final int tmdbImageCacheMb;

  static const defaultTmdbImageCacheMb = 1000;
  static const tmdbImageCacheChoices = [250, 500, 1000, 2000, 4000];

  /// Whether intro, recap and credits times come from SkipDB and
  /// TheIntroDB (Settings › Services). Saved as `skipDb` / `introDb`: the
  /// earlier `skipDbEnabled` / `introDbEnabled` were saved as false before
  /// the switches existed, so they are ignored.
  final bool skipDbEnabled;
  final bool introDbEnabled;

  /// Whether watch data, favourites and settings are synced through a
  /// sync server (Settings › Sync). Device-only, like [syncServer].
  final bool syncEnabled;

  /// The sync server's address as entered (see `parseSyncServerAddress`);
  /// null when none is set.
  final String? syncServer;

  Duration get endMargin => Duration(minutes: endMarginMinutes);
  Duration get startMargin => Duration(minutes: startMarginMinutes);
  Duration get maxRecordingLength => Duration(hours: maxRecordingHours);
  SpacePolicy get spacePolicy => SpacePolicy(minFreeGb * bytesPerGb);

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
    VodSort? movieSort,
    VodSort? seriesSort,
    VodSort? movieMySort,
    VodSort? seriesMySort,
    HomeLayout? homeLayout,
    int? playerVolume,
    bool? showRemainingTime,
    int? Function()? playNextSeconds,
    String? Function()? downloadFolder,
    int? endMarginMinutes,
    int? startMarginMinutes,
    int? maxRecordingHours,
    int? minFreeGb,
    bool? tmdbEnabled,
    bool? tmdbPreferPosters,
    bool? tmdbPaused,
    int? tmdbImageCacheMb,
    bool? skipDbEnabled,
    bool? introDbEnabled,
    bool? syncEnabled,
    String? Function()? syncServer,
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
    movieSort: movieSort ?? this.movieSort,
    seriesSort: seriesSort ?? this.seriesSort,
    movieMySort: movieMySort ?? this.movieMySort,
    seriesMySort: seriesMySort ?? this.seriesMySort,
    homeLayout: homeLayout ?? this.homeLayout,
    playerVolume: playerVolume ?? this.playerVolume,
    showRemainingTime: showRemainingTime ?? this.showRemainingTime,
    playNextSeconds: playNextSeconds == null
        ? this.playNextSeconds
        : playNextSeconds(),
    downloadFolder: downloadFolder == null
        ? this.downloadFolder
        : downloadFolder(),
    endMarginMinutes: endMarginMinutes ?? this.endMarginMinutes,
    startMarginMinutes: startMarginMinutes ?? this.startMarginMinutes,
    maxRecordingHours: maxRecordingHours ?? this.maxRecordingHours,
    minFreeGb: minFreeGb ?? this.minFreeGb,
    tmdbEnabled: tmdbEnabled ?? this.tmdbEnabled,
    tmdbPreferPosters: tmdbPreferPosters ?? this.tmdbPreferPosters,
    tmdbPaused: tmdbPaused ?? this.tmdbPaused,
    tmdbImageCacheMb: tmdbImageCacheMb ?? this.tmdbImageCacheMb,
    skipDbEnabled: skipDbEnabled ?? this.skipDbEnabled,
    introDbEnabled: introDbEnabled ?? this.introDbEnabled,
    syncEnabled: syncEnabled ?? this.syncEnabled,
    syncServer: syncServer == null ? this.syncServer : syncServer(),
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
    'movieSort': movieSort.name,
    'seriesSort': seriesSort.name,
    'movieMySort': movieMySort.name,
    'seriesMySort': seriesMySort.name,
    'homeLayout': homeLayout.toJson(),
    'playerVolume': playerVolume,
    'showRemainingTime': showRemainingTime,
    // 0 for off, so a missing value still means the default.
    'playNextSeconds': playNextSeconds ?? 0,
    'downloadFolder': ?downloadFolder,
    'endMarginMinutes': endMarginMinutes,
    'startMarginMinutes': startMarginMinutes,
    'maxRecordingHours': maxRecordingHours,
    'minFreeGb': minFreeGb,
    'tmdbEnabled': tmdbEnabled,
    'tmdbPreferPosters': tmdbPreferPosters,
    'tmdbPaused': tmdbPaused,
    'tmdbImageCacheMb': tmdbImageCacheMb,
    'skipDb': skipDbEnabled,
    'introDb': introDbEnabled,
    'syncEnabled': syncEnabled,
    'syncServer': ?syncServer,
  };

  /// Lenient inverse of [toJson]: unknown or invalid values use defaults.
  factory AppSettings.fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    final zone = json['guideTimeZone'];
    final shift = json['guideShiftHours'];
    final hidden = json['hiddenCategoryLists'];
    final volume = json['playerVolume'];
    final playNext = json['playNextSeconds'];
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
      movieSort: _providerSort(json['movieSort']),
      seriesSort: _providerSort(json['seriesSort']),
      movieMySort:
          VodSort.byName(_string(json['movieMySort'])) ?? VodSort.myOrder,
      seriesMySort:
          VodSort.byName(_string(json['seriesMySort'])) ?? VodSort.myOrder,
      homeLayout: HomeLayout.fromJson(json['homeLayout']),
      playerVolume: volume is num && volume.isFinite
          ? volume.round().clamp(0, maxPlayerVolume)
          : defaultPlayerVolume,
      showRemainingTime: json['showRemainingTime'] == true,
      playNextSeconds: switch (playNext) {
        0 => null,
        final int s when playNextChoices.contains(s) => s,
        _ => defaultPlayNextSeconds,
      },
      downloadFolder: switch (json['downloadFolder']) {
        final String f when f.isNotEmpty => f,
        _ => null,
      },
      endMarginMinutes: _choice(
        json['endMarginMinutes'],
        endMarginChoices,
        defaultEndMarginMinutes,
      ),
      startMarginMinutes: _choice(
        json['startMarginMinutes'],
        startMarginChoices,
        defaultStartMarginMinutes,
      ),
      maxRecordingHours: _choice(
        json['maxRecordingHours'],
        maxRecordingChoices,
        defaultMaxRecordingHours,
      ),
      minFreeGb: _choice(json['minFreeGb'], minFreeChoices, defaultMinFreeGb),
      tmdbEnabled: json['tmdbEnabled'] == true,
      tmdbPreferPosters: json['tmdbPreferPosters'] == true,
      tmdbPaused: json['tmdbPaused'] == true,
      tmdbImageCacheMb: _choice(
        json['tmdbImageCacheMb'],
        tmdbImageCacheChoices,
        defaultTmdbImageCacheMb,
      ),
      skipDbEnabled: json['skipDb'] != false,
      introDbEnabled: json['introDb'] != false,
      syncEnabled: json['syncEnabled'] == true,
      syncServer: switch (json['syncServer']) {
        final String s when s.trim().isNotEmpty => s.trim(),
        _ => null,
      },
    );
  }

  /// One of [choices] from JSON, else [fallback].
  static int _choice(Object? json, List<int> choices, int fallback) =>
      json is int && choices.contains(json) ? json : fallback;

  static String? _string(Object? json) => json is String ? json : null;

  /// A sort outside my categories: any but My order.
  static VodSort _providerSort(Object? json) =>
      switch (VodSort.byName(_string(json))) {
        null || VodSort.myOrder => VodSort.recent,
        final sort => sort,
      };

  /// The sort order of [section] (`movies` or `series`); with [mine], in
  /// one of my categories.
  VodSort sortOf(String section, {bool mine = false}) =>
      switch ((section == 'series', mine)) {
        (true, true) => seriesMySort,
        (true, false) => seriesSort,
        (false, true) => movieMySort,
        (false, false) => movieSort,
      };

  /// These settings with [sort] for [section] (`movies` or `series`); with
  /// [mine], for my categories. My order is only for my categories.
  AppSettings withSort(String section, VodSort sort, {bool mine = false}) {
    if (sort == VodSort.myOrder && !mine) return this;
    return switch ((section == 'series', mine)) {
      (true, true) => copyWith(seriesMySort: sort),
      (true, false) => copyWith(seriesSort: sort),
      (false, true) => copyWith(movieMySort: sort),
      (false, false) => copyWith(movieSort: sort),
    };
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
