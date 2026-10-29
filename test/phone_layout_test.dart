import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/state/navigation.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/shell/app_shell.dart';
import 'package:tvplayer/ui/vod/poster.dart';
import 'package:tvplayer/ui/vod/series_details_screen.dart';

import 'helpers.dart';

/// A phone in portrait (Pixel 9a), and a desktop window.
const _phone = Size(412, 915);
const _desktop = Size(1400, 900);

Future<void> _pump(
  WidgetTester tester, {
  Size size = _phone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(
          FakeLiveSource(
            syntheticCatalog(count: 20, categories: 3),
            hasGuide: true,
          ),
        ),
        vodSourceProvider.overrideWithValue(
          FakeVodSource(
            movies: syntheticMovies(count: 36013, categories: 4),
            series: syntheticSeries(count: 30),
          ),
        ),
        providerKeyProvider.overrideWithValue('test'),
      ],
      child: const AppShell(),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tab(AppSection section) => find.byKey(Key('phoneNav.${section.name}'));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('phone layout (412 × 915)', () {
    testWidgets('a bottom bar with Home, Live TV, Movies, Series and More '
        'instead of the sidebar', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('sidebar')), findsNothing);
      expect(find.byKey(const Key('sidebar.resize')), findsNothing);
      for (final s in [
        AppSection.home,
        AppSection.live,
        AppSection.movies,
        AppSection.series,
        AppSection.more,
      ]) {
        expect(_tab(s), findsOneWidget);
      }
      final bar = tester.getRect(find.byKey(const Key('phoneNav')));
      expect(bar.bottom, _phone.height);

      await _tap(tester, _tab(AppSection.series));
      expect(find.byKey(const Key('page.title')), findsOneWidget);
      expect(find.text('Series'), findsWidgets);
      // A tab has no back arrow.
      expect(find.byKey(const Key('page.back')), findsNothing);
    });

    testWidgets('More lists TV Guide, Downloads and Settings; their back '
        'arrow and Android Back return to More', (tester) async {
      await _pump(tester);
      await _tap(tester, _tab(AppSection.more));
      expect(find.byKey(const Key('more.guide')), findsOneWidget);
      expect(find.byKey(const Key('more.downloads')), findsOneWidget);
      expect(find.byKey(const Key('more.settings')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('more.settings')));
      expect(find.text('Settings'), findsWidgets);
      await _tap(tester, find.byKey(const Key('page.back')));
      expect(find.byKey(const Key('more.settings')), findsOneWidget);

      await _tap(tester, find.byKey(const Key('more.downloads')));
      expect(find.text('Nothing downloaded yet'), findsOneWidget);
      // Android's Back (gesture or button) goes the same way.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more.downloads')), findsOneWidget);
      // From a tab other than Home, Back goes Home.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.textContaining(RegExp('^Good (morning|afternoon|evening)')),
        findsOneWidget,
      );
    });

    testWidgets('the magnifier opens Search; back returns', (tester) async {
      await _pump(tester);
      await _tap(tester, _tab(AppSection.movies));
      // The section's own search field is left out on a phone.
      expect(find.byKey(const Key('movies.search')), findsNothing);
      await _tap(tester, find.byKey(const Key('page.search')));
      expect(find.byKey(const Key('search.field')), findsOneWidget);
      expect(find.byKey(const Key('page.search')), findsNothing);
      await _tap(tester, find.byKey(const Key('page.back')));
      expect(find.byKey(const Key('movies.categories.sheet')), findsOneWidget);
    });

    testWidgets('leaving Search closes the keyboard: opening a result, '
        'switching tab, going back', (tester) async {
      Future<void> search(String text) async {
        await _tap(tester, find.byKey(const Key('page.search')));
        await tester.enterText(find.byKey(const Key('search.field')), text);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
      }

      bool fieldFocused() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>() !=
          null;

      await _pump(tester);
      // A series result opens its details.
      await search('Series 0001');
      await _tap(tester, find.byKey(const ValueKey('search.series.1')));
      expect(find.byType(SeriesDetailsScreen), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(fieldFocused(), isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);

      // A movie result.
      await _tap(tester, _tab(AppSection.home));
      await search('Movie 00001');
      await _tap(tester, find.byKey(const ValueKey('search.movie.1')));
      expect(tester.testTextInput.isVisible, isFalse);
      expect(fieldFocused(), isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Switching tab and Back.
      await _tap(tester, _tab(AppSection.home));
      await search('Movie');
      await _tap(tester, _tab(AppSection.movies));
      expect(tester.testTextInput.isVisible, isFalse);
      await search('Movie');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search.field')), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(fieldFocused(), isFalse);
    });

    testWidgets('Live TV opens the TV guide', (tester) async {
      await _pump(tester);
      await _tap(tester, _tab(AppSection.live));
      await _tap(tester, find.byKey(const Key('live.guide')));
      expect(find.text('TV Guide'), findsWidgets);
      // No resizing by dragging on a phone.
      expect(find.byKey(const Key('guide.channels.resize')), findsNothing);
      await _tap(tester, find.byKey(const Key('page.back')));
      expect(find.byKey(const Key('live.categories.sheet')), findsOneWidget);
    });

    testWidgets('categories open in a sheet; a choice closes it and the '
        'content keeps the full width', (tester) async {
      await _pump(tester);
      await _tap(tester, _tab(AppSection.movies));
      expect(find.byKey(const Key('movies.categories')), findsNothing);
      expect(find.byKey(const Key('movies.categories.resize')), findsNothing);
      expect(find.byKey(const Key('movies.categories.hide')), findsNothing);
      final grid = tester.getRect(find.byKey(const Key('movies.grid')));
      expect(grid.width, _phone.width);

      final button = find.byKey(const Key('movies.categories.sheet'));
      expect(
        find.descendant(of: button, matching: find.text('All movies')),
        findsOneWidget,
      );
      await _tap(tester, button);
      expect(find.byKey(const Key('movies.categories')), findsOneWidget);
      expect(find.text('MY CATEGORIES'), findsOneWidget);
      // With their counts.
      expect(find.text('36013'), findsOneWidget);

      await _tap(tester, find.text('Movie category 1'));
      expect(find.byKey(const Key('movies.categories')), findsNothing);
      expect(
        find.descendant(of: button, matching: find.text('Movie category 1')),
        findsOneWidget,
      );
    });

    testWidgets('two or three poster columns', (tester) async {
      await _pump(tester);
      await _tap(tester, _tab(AppSection.movies));
      final cards = find.byType(PosterCard);
      final top = tester.getTopLeft(cards.first).dy;
      final columns = {
        for (final e in cards.evaluate())
          if (tester.getTopLeft(find.byWidget(e.widget)).dy == top)
            tester.getTopLeft(find.byWidget(e.widget)).dx,
      };
      expect(columns.length, inInclusiveRange(2, 3));
    });

    testWidgets('a settings row puts its dropdown below the text', (
      tester,
    ) async {
      await _pump(tester, textScale: 1.4);
      await _tap(tester, _tab(AppSection.more));
      await _tap(tester, find.byKey(const Key('more.settings')));
      final dropdown = find.byKey(const Key('settings.autoRefresh'));
      await tester.scrollUntilVisible(
        dropdown,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final title = find.text('Automatic refresh');
      expect(
        tester.getTopLeft(dropdown).dy,
        greaterThan(tester.getBottomLeft(title).dy),
      );
      // The description keeps (nearly) the row's width.
      final description = find.textContaining('Once a day');
      expect(tester.getSize(description).width, greaterThan(250));
      expect(tester.takeException(), isNull);
    });

    testWidgets('movie details stack: the picture above the title', (
      tester,
    ) async {
      await _pump(tester);
      await _tap(tester, _tab(AppSection.movies));
      await _tap(tester, find.byType(PosterCard).first);
      final picture = find.byKey(const Key('details.picture'));
      final title = find.byKey(const Key('movie.title'));
      expect(picture, findsOneWidget);
      expect(
        tester.getBottomLeft(picture).dy,
        lessThan(tester.getTopLeft(title).dy),
      );
      expect(tester.getSize(title).width, greaterThan(300));
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.4, 2.0]) {
      testWidgets('every page fits at text scale $scale', (tester) async {
        await _pump(tester, textScale: scale);
        for (final s in AppSection.values) {
          final nav = ProviderScope.containerOf(
            tester.element(find.byType(AppShell)),
          ).read(appSectionProvider.notifier);
          nav.select(s);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s.name);
        }
        await _tap(tester, _tab(AppSection.movies));
        await _tap(tester, find.byKey(const Key('movies.categories.sheet')));
        expect(tester.takeException(), isNull, reason: 'category sheet');
        await _tap(tester, find.text('All movies').last);
        await _tap(tester, find.byType(PosterCard).first);
        expect(tester.takeException(), isNull, reason: 'movie details');
      });
    }
  });

  testWidgets('a desktop window keeps the sidebar and category column', (
    tester,
  ) async {
    await _pump(tester, size: _desktop);
    expect(find.byKey(const Key('sidebar')), findsOneWidget);
    expect(find.byKey(const Key('sidebar.resize')), findsOneWidget);
    expect(find.byKey(const Key('phoneNav')), findsNothing);
    await _tap(tester, find.byKey(Key('nav.${AppSection.movies.index}')));
    expect(find.byKey(const Key('movies.categories')), findsOneWidget);
    expect(find.byKey(const Key('movies.categories.resize')), findsOneWidget);
    expect(find.byKey(const Key('movies.categories.sheet')), findsNothing);
    expect(find.byKey(const Key('movies.search')), findsOneWidget);
    expect(find.byKey(const Key('page.search')), findsNothing);
  });
}
