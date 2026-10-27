import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

final _t0 = DateTime.utc(2026, 3, 1, 12);

/// My category "Faves" (id `live0`, or `movie0` for [kind] movie) holding
/// [items] in this order, and [hidden] provider categories.
FavouritesData _data({
  ContentKind kind = ContentKind.live,
  List<(String, String)> items = const [],
  Set<String> hidden = const {},
}) {
  var (data, _) = createCategory(
    FavouritesData.empty,
    kind: kind,
    name: 'Faves',
    icon: 'star',
    now: _t0,
    newId: () => '${kind.name}0',
  );
  // New items go first: add the last one first.
  for (final (i, (id, name)) in items.reversed.indexed) {
    data = setMembership(
      data,
      '${kind.name}0',
      ItemRef(kind, id),
      name: name,
      member: true,
      now: _t0.add(Duration(minutes: i)),
    );
  }
  return setCategoriesHidden(data, kind, hidden, hidden: true, now: _t0);
}

Future<void> _pump(
  WidgetTester tester,
  MemoryFavouritesStore store,
  Widget screen, {
  FakeSettingsStorage? settings,
  double textScale = 1,
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(
          FakeLiveSource(syntheticCatalog(count: 50)),
        ),
        vodSourceProvider.overrideWithValue(
          FakeVodSource(movies: syntheticMovies(count: 40)),
        ),
        providerKeyProvider.overrideWithValue('test'),
      ],
      favourites: store,
      settings: settings,
      child: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: screen,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The texts of [texts] that are on screen, in reading order (top to
/// bottom, then left to right in a grid row).
List<String> _topToBottom(WidgetTester tester, List<String> texts) {
  final shown = [
    for (final t in texts)
      if (find.text(t).evaluate().isNotEmpty) t,
  ];
  shown.sort((a, b) {
    final pa = tester.getTopLeft(find.text(a).first);
    final pb = tester.getTopLeft(find.text(b).first);
    return pa.dy != pb.dy ? pa.dy.compareTo(pb.dy) : pa.dx.compareTo(pb.dx);
  });
  return shown;
}

Future<void> _shiftF10(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<MenuItemButton>(find.byKey(key)).onPressed != null;

/// Drags the row with [key] by its handle by [dy].
Future<void> _dragHandle(WidgetTester tester, Finder row, double dy) async {
  final handle = find.descendant(
    of: row,
    matching: find.byIcon(Icons.drag_indicator),
  );
  final gesture = await tester.startGesture(
    tester.getCenter(handle),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(0, dy / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

const _categories = [
  'Category 0',
  'Category 1',
  'Category 2',
  'Category 3',
  'Category 4',
];

void main() {
  group('provider categories', () {
    testWidgets('the context menu moves them, passing over hidden ones', (
      tester,
    ) async {
      final store = MemoryFavouritesStore(_data(hidden: {'c1'}));
      await _pump(tester, store, const LiveTvScreen());

      await tester.tap(find.text('Category 2'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live.categoryMenu.up')));
      await tester.pumpAndSettle();
      expect(store.data.categoryOrder(ContentKind.live)!.ids.take(3), [
        'c2',
        'c0',
        'c1',
      ]);
      expect(_topToBottom(tester, _categories), [
        'Category 2',
        'Category 0',
        'Category 3',
        'Category 4',
      ]);

      // The first can't move up or to the top.
      await tester.tap(find.text('Category 2'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(_enabled(tester, const Key('live.categoryMenu.up')), isFalse);
      expect(_enabled(tester, const Key('live.categoryMenu.top')), isFalse);
      await tester.tap(find.byKey(const Key('live.categoryMenu.down')));
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, _categories).take(2), [
        'Category 0',
        'Category 2',
      ]);

      // Keyboard: Shift+F10 on a focused category; focus goes to the
      // first entry that can be used.
      Focus.of(tester.element(find.text('Category 4'))).requestFocus();
      await tester.pump();
      await _shiftF10(tester);
      expect(
        Focus.of(tester.element(find.text('Move up'))).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, _categories).first, 'Category 4');
      // The moved category keeps keyboard focus.
      expect(
        Focus.of(tester.element(find.text('Category 4'))).hasFocus,
        isTrue,
      );

      // The Menu key opens it too.
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('live.categoryMenu.down')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });

    testWidgets('edit mode: drag to reorder, Reset to provider order with '
        'Undo', (tester) async {
      final store = MemoryFavouritesStore(_data());
      await _pump(tester, store, const LiveTvScreen());
      await tester.tap(find.byKey(const Key('live.categories.edit')));
      await tester.pumpAndSettle();
      final reset = find.byKey(const Key('live.categories.resetOrder'));
      expect(
        tester
            .widget<TextButton>(
              find.descendant(of: reset, matching: find.byType(TextButton)),
            )
            .onPressed,
        isNull,
      );

      await _dragHandle(
        tester,
        find.byKey(const ValueKey('provider.c3')),
        -150,
      );
      final moved = store.data.categoryOrder(ContentKind.live)!.ids;
      expect(moved.indexOf('c3'), lessThan(3));

      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(store.data.categoryOrder(ContentKind.live), isNull);
      expect(_topToBottom(tester, _categories), _categories);
      expect(
        find.text('Categories are back in the provider’s order'),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.data.categoryOrder(ContentKind.live)!.ids, moved);

      // The snack bar closes after 6 s.
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('Settings lists them in my order and resets; the snack bar '
        'closes when the page closes', (tester) async {
      final store = MemoryFavouritesStore(
        moveProviderCategory(
          _data(),
          ContentKind.live,
          syntheticCatalog(count: 50).categories,
          'c4',
          toIndex: 0,
          now: _t0,
        ),
      );
      await _pump(
        tester,
        store,
        const SettingsScreen(),
        size: const Size(1200, 2400),
      );
      await tester.tap(find.byKey(const Key('settings.categories.live')));
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, _categories).first, 'Category 4');

      await tester.tap(find.byKey(const Key('settings.categories.resetOrder')));
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, _categories), _categories);
      expect(find.text('Undo'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
    });
  });

  group('Live TV: my category', () {
    const channels = [
      ('3', 'Channel 0003'),
      ('1', 'Channel 0001'),
      ('7', 'Channel 0007'),
    ];
    final names = [for (final (_, n) in channels) n];

    Future<void> openFaves(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('live.my.Faves')));
      await tester.pumpAndSettle();
    }

    testWidgets('the context menu moves channels; not under All channels', (
      tester,
    ) async {
      final store = MemoryFavouritesStore(_data(items: channels));
      await _pump(tester, store, const LiveTvScreen());
      expect(find.byKey(const Key('live.reorder')), findsNothing);
      await tester.tap(find.text('Channel 0007'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('context.move.up')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await openFaves(tester);
      expect(_topToBottom(tester, names), names);
      await tester.tap(find.text('Channel 0007'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(_enabled(tester, const Key('context.move.down')), isFalse);
      await tester.tap(find.byKey(const Key('context.move.top')));
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, names), [
        'Channel 0007',
        'Channel 0003',
        'Channel 0001',
      ]);

      // Keyboard, and focus stays on the moved channel.
      Focus.of(tester.element(find.text('Channel 0003'))).requestFocus();
      await tester.pump();
      await _shiftF10(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter); // Move up.
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, names), [
        'Channel 0003',
        'Channel 0007',
        'Channel 0001',
      ]);
      expect(
        Focus.of(tester.element(find.text('Channel 0003'))).hasFocus,
        isTrue,
      );
    });

    testWidgets('Reorder: drag in the list, then Done', (tester) async {
      final store = MemoryFavouritesStore(
        _data(items: [...channels, ('gone', 'Gone TV')]),
      );
      await _pump(tester, store, const LiveTvScreen());
      await openFaves(tester);
      await tester.tap(find.byKey(const Key('live.reorder')));
      await tester.pumpAndSettle();
      expect(find.text('Done reordering'), findsOneWidget);
      // Dropped channels can be moved too.
      expect(find.text('Gone TV'), findsOneWidget);
      expect(find.text('Not available'), findsOneWidget);

      await _dragHandle(tester, find.byKey(const Key('live.reorder.7')), -200);
      expect(
        [for (final m in store.data.itemsIn('live0')) m.item.id],
        ['7', '3', '1', 'gone'],
      );

      await tester.tap(find.byKey(const Key('live.reorder')));
      await tester.pumpAndSettle();
      expect(find.text('Reorder'), findsOneWidget);
      expect(_topToBottom(tester, names), [
        'Channel 0007',
        'Channel 0003',
        'Channel 0001',
      ]);
    });

    testWidgets('a channel added with the star goes first', (tester) async {
      final store = MemoryFavouritesStore(_data(items: channels));
      await _pump(tester, store, const LiveTvScreen());
      await tester.tap(find.text('Channel 0009'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context.favourites')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is CheckboxMenuButton &&
              w.key == const Key('favourite.menu.Faves'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await openFaves(tester);
      expect(
        _topToBottom(tester, ['Channel 0009', ...names]).first,
        'Channel 0009',
      );
    });
  });

  group('Movies: my category', () {
    const movies = [
      ('12', 'Movie 00012'),
      ('3', 'Movie 00003'),
      ('30', 'Movie 00030'),
    ];
    final names = [for (final (_, n) in movies) n];

    Future<void> openFaves(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('movies.my.Faves')));
      await tester.pumpAndSettle();
    }

    testWidgets('My order is the default and only offered there', (
      tester,
    ) async {
      final settings = FakeSettingsStorage();
      final store = MemoryFavouritesStore(
        _data(kind: ContentKind.movie, items: movies),
      );
      await _pump(tester, store, const MoviesScreen(), settings: settings);
      // A provider category: no My order.
      await tester.tap(find.byKey(const Key('movies.sort')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('movies.sort.myOrder')), findsNothing);
      await tester.tap(find.byKey(const Key('movies.sort.title')));
      await tester.pumpAndSettle();

      await openFaves(tester);
      expect(find.text('My order'), findsOneWidget);
      expect(_topToBottom(tester, names), names);
      await tester.tap(find.byKey(const Key('movies.sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('movies.sort.title')));
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, names), [
        'Movie 00003',
        'Movie 00012',
        'Movie 00030',
      ]);
      // No moves while sorted A–Z.
      await tester.tap(find.text('Movie 00030'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('context.move.up')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('movies.sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('movies.sort.myOrder')));
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, names), names);

      final saved = settings.saved;
      expect(saved.movieSort, VodSort.title);
      expect(saved.movieMySort, VodSort.myOrder);
    });

    testWidgets('poster menu moves; Reorder list drags', (tester) async {
      final store = MemoryFavouritesStore(
        _data(kind: ContentKind.movie, items: movies),
      );
      await _pump(tester, store, const MoviesScreen());
      await openFaves(tester);
      await tester.tap(find.text('Movie 00030'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context.move.top')));
      await tester.pumpAndSettle();
      expect(
        [for (final m in store.data.itemsIn('movie0')) m.item.id],
        ['30', '12', '3'],
      );

      await tester.tap(find.byKey(const Key('movies.reorder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('movies.sort')), findsNothing);
      await _dragHandle(
        tester,
        find.byKey(const Key('movies.reorder.30')),
        200,
      );
      expect(
        [for (final m in store.data.itemsIn('movie0')) m.item.id].last,
        '30',
      );
      await tester.tap(find.byKey(const Key('movies.reorder')));
      await tester.pumpAndSettle();
      expect(_topToBottom(tester, names).last, 'Movie 00030');
    });
  });

  testWidgets('edit mode and Reorder lists fit at text scale 1.4', (
    tester,
  ) async {
    final store = MemoryFavouritesStore(
      _data(items: [('1', 'A channel with a rather long name'), ('2', 'Two')]),
    );
    await _pump(
      tester,
      store,
      const LiveTvScreen(),
      textScale: 1.4,
      size: const Size(1280, 800),
    );
    await tester.tap(find.byKey(const Key('live.categories.edit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Category 2'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tap(find.byKey(const Key('live.categories.edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live.my.Faves')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live.reorder')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final movies = MemoryFavouritesStore(
      _data(kind: ContentKind.movie, items: [('1', 'Movie 00001')]),
    );
    await _pump(
      tester,
      movies,
      const MoviesScreen(),
      textScale: 1.4,
      size: const Size(1280, 800),
    );
    await tester.tap(find.byKey(const Key('movies.my.Faves')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('movies.reorder')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('AppSettings keeps My order out of provider categories', () {
    const s = AppSettings();
    expect(s.sortOf('movies'), VodSort.recent);
    expect(s.sortOf('movies', mine: true), VodSort.myOrder);
    expect(s.withSort('movies', VodSort.myOrder), same(s));
    final json = s.withSort('series', VodSort.rating, mine: true).toJson();
    final back = AppSettings.fromJson({...json, 'movieSort': 'myOrder'});
    expect(back.sortOf('series', mine: true), VodSort.rating);
    expect(back.sortOf('movies'), VodSort.recent);
  });
}
