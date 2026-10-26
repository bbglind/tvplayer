import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer/ui/vod/series_details_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

final _now = DateTime.utc(2026, 3, 1, 20);

/// Made-up catalogue: tags recur, so they are labels; `AC` doesn't.
final _movies = VodCatalog.movies(
  categories: const [Category(id: 'm', name: 'Films')],
  items: const [
    Movie(
      streamId: 1,
      name: 'NF-DO - Quiet Orchard (2025) (GB)',
      categoryId: 'm',
    ),
    Movie(streamId: 2, name: 'NF-DO - Copper Valley (2024)', categoryId: 'm'),
    Movie(streamId: 3, name: 'NF-DO - Glass Tide (2023)', categoryId: 'm'),
    Movie(streamId: 4, name: '4K-SC - Lantern Harbour (2026)', categoryId: 'm'),
    Movie(streamId: 5, name: '4K-SC - Paper Moth (2019)', categoryId: 'm'),
    Movie(streamId: 6, name: '4K-SC - Northern Signal (2021)', categoryId: 'm'),
    Movie(streamId: 7, name: 'AC - All Hours (2023)', categoryId: 'm'),
  ],
  fetchedAt: DateTime.utc(2026),
);

final _series = VodCatalog.series(
  categories: const [Category(id: 's', name: 'Shows')],
  items: const [
    Series(
      seriesId: 1,
      name: 'NF-DO - Bramble Lane (2025) (GB)',
      categoryId: 's',
    ),
  ],
  fetchedAt: DateTime.utc(2026),
);

final _info = SeriesInfo(
  series: _series.items.first,
  seasons: const [],
  episodes: const [
    Episode(
      id: '11',
      season: 1,
      episodeNumber: 1,
      title: 'NF-DO - Bramble Lane (2025) (GB) - S01E01 - Episode 1',
    ),
    Episode(
      id: '12',
      season: 1,
      episodeNumber: 2,
      title: 'NF-DO - Bramble Lane (2025) (GB) - S01E02 - The Gate',
    ),
    Episode(
      id: '13',
      season: 1,
      episodeNumber: 3,
      title: 'NF-DO - Bramble Lane (2025) (GB) - S01E03',
    ),
  ],
);

/// A [Text] whose plain text (a label is a placeholder) contains [text].
Finder _title(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? w.textSpan?.toPlainText() ?? '').contains(text) &&
      !(w.data ?? w.textSpan?.toPlainText() ?? '').contains(' - '),
);

Finder _tooltip(String text) =>
    find.byWidgetPredicate((w) => w is Tooltip && w.message == text);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double scale = 1.4,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    testApp(
      overrides: [
        vodSourceProvider.overrideWithValue(
          FakeVodSource(
            movies: _movies,
            series: _series,
            seriesInfos: {1: _info},
          ),
        ),
        providerKeyProvider.overrideWithValue('test'),
      ],
      now: _now,
      child: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 1.4]) {
    testWidgets('posters show the label and the clean title at $scale', (
      tester,
    ) async {
      await _pump(tester, const MoviesScreen(), scale: scale);
      expect(tester.takeException(), isNull);
      final card = find.byKey(const ValueKey(1));
      expect(
        find.descendant(of: card, matching: find.text('NF-DO')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: _title('Quiet Orchard')),
        findsOneWidget,
      );
      expect(_tooltip('NF-DO - Quiet Orchard (2025) (GB)'), findsOneWidget);
      // Seen once: kept in the title, no label.
      expect(find.text('AC - All Hours'), findsOneWidget);
      expect(find.text('AC'), findsNothing);
    });
  }

  testWidgets('movie details: label, clean title and country', (tester) async {
    await _pump(tester, const MoviesScreen());
    await tester.tap(find.byKey(const ValueKey(1)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final title = find.byKey(const Key('movie.title'));
    expect(find.descendant(of: title, matching: find.text('NF-DO')), findsOne);
    expect(
      find.descendant(of: title, matching: _title('Quiet Orchard')),
      findsOne,
    );
    expect(find.text('2025 · GB'), findsOneWidget);
  });

  testWidgets('episode rows show the episode name only', (tester) async {
    await _pump(tester, SeriesDetailsScreen(series: _series.items.first));
    expect(tester.takeException(), isNull);
    final title = find.byKey(const Key('series.title'));
    expect(find.descendant(of: title, matching: find.text('NF-DO')), findsOne);
    expect(find.text('1. Episode 1'), findsOneWidget);
    expect(find.text('2. The Gate'), findsOneWidget);
    // No name of its own.
    expect(find.text('3. Episode 3'), findsOneWidget);
    expect(
      _tooltip('NF-DO - Bramble Lane (2025) (GB) - S01E02 - The Gate'),
      findsOneWidget,
    );
  });
}
