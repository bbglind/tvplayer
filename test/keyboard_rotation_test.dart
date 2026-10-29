import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/player/touch_player_screen.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';
import 'package:tvplayer/ui/vod/movie_details_screen.dart';
import 'package:tvplayer/ui/vod/series_details_screen.dart';

import 'fake_touch_player.dart';
import 'helpers.dart';

/// A Pixel 9a in portrait and in landscape: landscape is wider than the
/// phone layout, so the app below the open page is rebuilt as on desktop.
/// (Taller than the phone's 412, where the sidebar doesn't fit yet.)
const _portrait = Size(412, 915);
const _landscape = Size(915, 560);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = _portrait;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final player = FakeTouchPlayer();
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(
          FakeLiveSource(syntheticCatalog(count: 20, categories: 3)),
        ),
        vodSourceProvider.overrideWithValue(
          FakeVodSource(
            movies: syntheticMovies(count: 30, categories: 3),
            series: syntheticSeries(count: 30),
          ),
        ),
        providerKeyProvider.overrideWithValue('test'),
        useExternalMpvProvider.overrideWithValue(false),
        touchPlayerFactoryProvider.overrideWithValue(
          ({required hwdec}) => player,
        ),
        deviceControlsProvider.overrideWithValue(FakeDeviceControls()),
      ],
      child: const AppShell(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Rotates to [size]; the player animates, so no pumpAndSettle.
Future<void> _rotate(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Searches for [text] from the magnifier: the field gets focus and the
/// keyboard opens.
Future<void> _search(WidgetTester tester, String text) async {
  await _tap(tester, find.byKey(const Key('page.search')));
  expect(_textFocused(), isTrue);
  await tester.enterText(find.byKey(const Key('search.field')), text);
  await tester.pumpAndSettle();
  expect(tester.testTextInput.isVisible, isTrue);
}

bool _textFocused() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

void _expectNoKeyboard(WidgetTester tester, String when) {
  expect(_textFocused(), isFalse, reason: when);
  expect(tester.testTextInput.isVisible, isFalse, reason: when);
}

void main() {
  testWidgets('a movie from Search: Play (landscape) and Back never bring '
      'the keyboard back', (tester) async {
    await _pump(tester);
    await _search(tester, 'Movie 00001');
    await _tap(tester, find.byKey(const ValueKey('search.movie.1')));
    expect(find.byType(MovieDetailsScreen), findsOneWidget);
    _expectNoKeyboard(tester, 'movie page');

    await tester.tap(find.byKey(const Key('movie.play')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _rotate(tester, _landscape);
    expect(find.byType(TouchPlayerScreen), findsOneWidget);
    _expectNoKeyboard(tester, 'player in landscape');

    await tester.tap(find.byKey(const Key('player.back')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _rotate(tester, _portrait);
    expect(find.byType(TouchPlayerScreen), findsNothing);
    expect(find.byType(MovieDetailsScreen), findsOneWidget);
    _expectNoKeyboard(tester, 'back on the movie page');
  });

  testWidgets('a series from Search: rotating on its page', (tester) async {
    await _pump(tester);
    await _search(tester, 'Series 0001');
    await _tap(tester, find.byKey(const ValueKey('search.series.1')));
    expect(find.byType(SeriesDetailsScreen), findsOneWidget);
    await _rotate(tester, _landscape);
    _expectNoKeyboard(tester, 'series page, landscape');
    await _rotate(tester, _portrait);
    _expectNoKeyboard(tester, 'series page, portrait');
  });

  testWidgets('back on Search after a result, rotating keeps the keyboard '
      'closed; opening Search again focuses the field', (tester) async {
    await _pump(tester);
    await _search(tester, 'Movie 00001');
    await _tap(tester, find.byKey(const ValueKey('search.movie.1')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    _expectNoKeyboard(tester, 'back on Search');
    await _rotate(tester, _landscape);
    _expectNoKeyboard(tester, 'Search, landscape');
    await _rotate(tester, _portrait);
    _expectNoKeyboard(tester, 'Search, portrait');

    // Another section, then Search again: as before, the field is focused.
    await _tap(tester, find.byKey(const Key('phoneNav.movies')));
    _expectNoKeyboard(tester, 'Movies');
    await _search(tester, 'Movie');
  });

  testWidgets('rotating while typing on Search keeps the field focused', (
    tester,
  ) async {
    await _pump(tester);
    await _search(tester, 'Movie');
    await _rotate(tester, _landscape);
    expect(_textFocused(), isTrue);
  });
}
