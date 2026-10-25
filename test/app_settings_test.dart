import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  test('track defaults: Swedish then English subtitles, on', () {
    const settings = AppSettings();
    expect(settings.subtitleLanguages, ['sv', 'en']);
    expect(settings.audioLanguages, isEmpty);
    expect(settings.subtitlesOn, isTrue);
    expect(AppSettings.fromJson({}).subtitleLanguages, ['sv', 'en']);
  });

  test('track settings round-trip through JSON', () {
    const settings = AppSettings(
      subtitleLanguages: ['en'],
      audioLanguages: ['sv', 'en'],
      subtitlesOn: false,
    );
    final back = AppSettings.fromJson(settings.toJson());
    expect(back.subtitleLanguages, ['en']);
    expect(back.audioLanguages, ['sv', 'en']);
    expect(back.subtitlesOn, isFalse);
    expect(back.trackPreferences.audioLanguages, ['sv', 'en']);
  });

  test('languages are normalised, deduplicated and unknown ones dropped', () {
    final settings = AppSettings.fromJson({
      'subtitleLanguages': ['swe', 'Svenska', 'English', 'klingon', 3],
      'audioLanguages': 'not a list',
    });
    expect(settings.subtitleLanguages, ['sv', 'en']);
    expect(settings.audioLanguages, isEmpty);
  });

  test('layout settings round-trip through JSON', () {
    const settings = AppSettings(
      sidebarCollapsed: true,
      sidebarWidth: 300,
      hiddenCategoryLists: {'live', 'series'},
      categoryListWidth: 320,
      guideChannelWidth: 250,
    );
    final back = AppSettings.fromJson(settings.toJson());
    expect(back.sidebarCollapsed, isTrue);
    expect(back.sidebarWidth, 300);
    expect(back.hiddenCategoryLists, {'live', 'series'});
    expect(back.categoryListWidth, 320);
    expect(back.guideChannelWidth, 250);
  });

  test('layout settings: defaults, clamped width, bad values ignored', () {
    final defaults = AppSettings.fromJson({});
    expect(defaults.sidebarCollapsed, isFalse);
    expect(defaults.sidebarWidth, AppSettings.defaultSidebarWidth);
    expect(defaults.hiddenCategoryLists, isEmpty);
    expect(defaults.categoryListWidth, AppSettings.defaultCategoryListWidth);
    expect(defaults.guideChannelWidth, AppSettings.defaultGuideChannelWidth);
    expect(
      AppSettings.fromJson({'categoryListWidth': 5000}).categoryListWidth,
      AppSettings.maxCategoryListWidth,
    );
    expect(
      AppSettings.fromJson({'guideChannelWidth': 10}).guideChannelWidth,
      AppSettings.minGuideChannelWidth,
    );

    expect(
      AppSettings.fromJson({'sidebarWidth': 5000}).sidebarWidth,
      AppSettings.maxSidebarWidth,
    );
    expect(
      AppSettings.fromJson({'sidebarWidth': 10}).sidebarWidth,
      AppSettings.minSidebarWidth,
    );
    final bad = AppSettings.fromJson({
      'sidebarCollapsed': 'yes',
      'sidebarWidth': 'wide',
      'categoryListWidth': double.nan,
      'guideChannelWidth': 'wide',
      'hiddenCategoryLists': ['live', 3, null],
    });
    expect(bad.sidebarCollapsed, isFalse);
    expect(bad.sidebarWidth, AppSettings.defaultSidebarWidth);
    expect(bad.hiddenCategoryLists, {'live'});
    expect(bad.categoryListWidth, AppSettings.defaultCategoryListWidth);
    expect(bad.guideChannelWidth, AppSettings.defaultGuideChannelWidth);
  });

  test('sort per section round-trips; unknown values use the default', () {
    final settings = const AppSettings().withSort('series', VodSort.rating);
    expect(settings.sortOf('series'), VodSort.rating);
    expect(settings.sortOf('movies'), VodSort.recent);
    final back = AppSettings.fromJson(settings.toJson());
    expect(back.seriesSort, VodSort.rating);
    expect(back.movieSort, VodSort.recent);
    expect(
      AppSettings.fromJson({'movieSort': 'sideways', 'seriesSort': 3})
          .movieSort,
      VodSort.recent,
    );
  });

  test('home layout: moves and hides rows, round-trips, repairs bad JSON', () {
    final layout = HomeLayout.defaults
        .move(HomeRowId.recentMovies, -2)
        .withVisible(HomeRowId.featured, false);
    expect(layout.rows.map((r) => r.id), [
      HomeRowId.featured,
      HomeRowId.channels,
      HomeRowId.myCategories,
      HomeRowId.recentMovies,
      HomeRowId.continueWatching,
      HomeRowId.recentSeries,
    ]);
    expect(layout.move(HomeRowId.featured, -1), same(layout));
    final settings = AppSettings(homeLayout: layout);
    expect(AppSettings.fromJson(settings.toJson()).homeLayout, layout);

    // Unknown and repeated rows are dropped, missing ones added, shown.
    final repaired = HomeLayout.fromJson([
      {'id': 'recentSeries', 'visible': false},
      {'id': 'downloads'},
      {'id': 'recentSeries'},
      'garbage',
    ]);
    expect(
      repaired.rows.first,
      const HomeRow(HomeRowId.recentSeries, visible: false),
    );
    expect(repaired.rows, hasLength(HomeRowId.values.length));
    expect(repaired.rows.skip(1).every((r) => r.visible), isTrue);
    expect(
      AppSettings.fromJson({'homeLayout': 3}).homeLayout,
      HomeLayout.defaults,
    );
  });
}
