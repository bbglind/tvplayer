import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/epg/guide_screen.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer/ui/vod/movie_details_screen.dart';
import 'package:tvplayer/ui/vod/movies_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

final _t0 = DateTime.utc(2026, 3, 1, 12);

/// Live categories named [live] (ids `live0`, …) and movie categories
/// [movies] (`movie0`, …), with [members] as (category id, item id, name).
FavouritesData _data({
  List<String> live = const [],
  List<String> movies = const [],
  List<(String, String, String)> members = const [],
  Set<String> hiddenLive = const {},
}) {
  var data = FavouritesData.empty;
  for (final (kind, names) in [
    (ContentKind.live, live),
    (ContentKind.movie, movies),
  ]) {
    for (final (i, name) in names.indexed) {
      (data, _) = createCategory(
        data,
        kind: kind,
        name: name,
        icon: 'star',
        now: _t0,
        newId: () => '${kind.name}$i',
      );
    }
  }
  for (final (i, (category, item, name)) in members.indexed) {
    data = setMembership(
      data,
      category,
      ItemRef(data.category(category)!.kind, item),
      name: name,
      member: true,
      now: _t0.add(Duration(minutes: i)),
    );
  }
  return setCategoriesHidden(
    data,
    ContentKind.live,
    hiddenLive,
    hidden: true,
    now: _t0,
  );
}

Future<void> _pumpLive(
  WidgetTester tester,
  MemoryFavouritesStore store, {
  LiveCatalog? catalog,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      overrides: [
        liveSourceProvider.overrideWithValue(
          FakeLiveSource(catalog ?? syntheticCatalog(count: 50)),
        ),
        providerKeyProvider.overrideWithValue('test'),
      ],
      favourites: store,
      child: const Scaffold(body: LiveTvScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _starOf(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(ChannelRow)),
  matching: find.byKey(const Key('favourite.star')),
);

/// The checkbox of my category [name] in a favourites menu.
Finder _box(String name) => find.byWidgetPredicate(
  (w) => w is CheckboxMenuButton && w.key == Key('favourite.menu.$name'),
);

bool _starFilled(WidgetTester tester, String name) =>
    tester.widget<IconButton>(_starOf(name)).isSelected ?? false;

void main() {
  group('Live TV', () {
    testWidgets('the star creates a category and adds the channel', (
      tester,
    ) async {
      final store = MemoryFavouritesStore();
      await _pumpLive(tester, store);
      expect(find.text('MY CATEGORIES'), findsOneWidget);
      expect(_starFilled(tester, 'Channel 0001'), isFalse);

      await tester.tap(_starOf('Channel 0001'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favourite.menu.new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('category.name')), ' Sport ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('category.icon.soccer')));
      await tester.tap(find.byKey(const Key('category.save')));
      await tester.pumpAndSettle();

      final sport = store.data.categoriesOf(ContentKind.live).single;
      expect((sport.name, sport.icon), ('Sport', 'soccer'));
      expect(store.data.itemsIn(sport.id).single.name, 'Channel 0001');
      expect(_starFilled(tester, 'Channel 0001'), isTrue);

      // Selecting it lists just that channel.
      await tester.tap(find.byKey(const Key('live.my.Sport')));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelRow), findsOneWidget);
      expect(find.text('Channel 0001'), findsOneWidget);
    });

    testWidgets('the star menu toggles several categories', (tester) async {
      final store = MemoryFavouritesStore(_data(live: ['News', 'Kids']));
      await _pumpLive(tester, store);

      await tester.tap(_starOf('Channel 0002'));
      await tester.pumpAndSettle();
      await tester.tap(_box('News'));
      await tester.pumpAndSettle();
      // The menu stays open for the next box.
      await tester.tap(_box('Kids'));
      await tester.pumpAndSettle();
      final item = const ItemRef(ContentKind.live, '2');
      expect(store.data.categoriesContaining(item), {'live0', 'live1'});

      await tester.tap(_box('News'));
      await tester.pumpAndSettle();
      expect(store.data.categoriesContaining(item), {'live1'});
    });

    testWidgets('right click and Shift+F10 open the context menu', (
      tester,
    ) async {
      final store = MemoryFavouritesStore(_data(live: ['News']));
      await _pumpLive(tester, store);

      await tester.tap(find.text('Channel 0003'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('context.favourites')));
      await tester.pumpAndSettle();
      await tester.tap(_box('News'));
      await tester.pumpAndSettle();
      expect(
        store.data.isFavourite(const ItemRef(ContentKind.live, '3')),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_box('News'), findsNothing);

      Focus.of(tester.element(find.text('Channel 0004'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('context.favourites')), findsOneWidget);
      // Focus moved into the menu; Enter shows the categories.
      expect(
        Focus.of(tester.element(find.text('Add to favourites…')))
            .hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        store.data.isFavourite(const ItemRef(ContentKind.live, '4')),
        isTrue,
      );
    });

    testWidgets('edit mode hides provider categories from the list and All', (
      tester,
    ) async {
      final store = MemoryFavouritesStore();
      await _pumpLive(tester, store);
      expect(find.text('50'), findsOneWidget); // All channels.

      await tester.tap(find.byKey(const Key('live.categories.edit')));
      await tester.pumpAndSettle();
      expect(find.text('PROVIDER CATEGORIES'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live.visibility.c3')));
      await tester.tap(find.byKey(const Key('live.visibility.c4')));
      await tester.pumpAndSettle();
      expect(store.data.hiddenIds(ContentKind.live), {'c3', 'c4'});
      // Still listed while editing, so they can be shown again.
      expect(find.text('Category 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('live.categories.edit')));
      await tester.pumpAndSettle();
      expect(find.text('Category 3'), findsNothing);
      expect(find.text('Category 4'), findsNothing);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('Channel 0003'), findsNothing);
      expect(find.text('Channel 0002'), findsOneWidget);

      await tester.tap(find.byKey(const Key('live.categories.edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live.categories.showAll')));
      await tester.pumpAndSettle();
      expect(store.data.hiddenIds(ContentKind.live), isEmpty);
    });

    testWidgets('hiding the selected category falls back to all channels', (
      tester,
    ) async {
      final store = MemoryFavouritesStore();
      await _pumpLive(tester, store);
      await tester.tap(find.text('Category 3'));
      await tester.pumpAndSettle();
      expect(find.text('Channel 0002'), findsNothing);

      await tester.tap(find.byKey(const Key('live.categories.edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live.visibility.c3')));
      await tester.pumpAndSettle();
      expect(find.text('Channel 0002'), findsOneWidget);
    });

    testWidgets('my category shows channels the provider dropped', (
      tester,
    ) async {
      final store = MemoryFavouritesStore(
        _data(
          live: ['Faves'],
          members: [('live0', '5', 'Channel 0005'), ('live0', 'x', 'Gone TV')],
        ),
      );
      await _pumpLive(tester, store);
      await tester.tap(find.byKey(const Key('live.my.Faves')));
      await tester.pumpAndSettle();
      expect(find.text('Channel 0005'), findsOneWidget);
      expect(find.text('Gone TV'), findsOneWidget);
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // Count in the list.
    });

    testWidgets('edit mode reorders and deletes my categories', (tester) async {
      final store = MemoryFavouritesStore(
        _data(live: ['A', 'B'], members: [('live0', '1', 'Channel 0001')]),
      );
      await _pumpLive(tester, store);
      await tester.tap(find.byKey(const Key('live.categories.edit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('live.my.B.actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category.action.up')));
      await tester.pumpAndSettle();
      expect(store.data.categoriesOf(ContentKind.live).map((c) => c.name), [
        'B',
        'A',
      ]);

      await tester.tap(find.byKey(const Key('live.my.A.actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category.action.edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('category.name')), 'Alpha');
      await tester.pump();
      await tester.tap(find.byKey(const Key('category.icon.news')));
      await tester.tap(find.byKey(const Key('category.save')));
      await tester.pumpAndSettle();
      expect(store.data.category('live0')!.name, 'Alpha');
      expect(store.data.category('live0')!.icon, 'news');

      await tester.tap(find.byKey(const Key('live.my.Alpha.actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category.action.delete')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Its item is removed'), findsOneWidget);
      await tester.tap(find.byKey(const Key('category.delete.confirm')));
      await tester.pumpAndSettle();
      expect(store.data.categoriesOf(ContentKind.live).map((c) => c.name), [
        'B',
      ]);
      expect(find.text('Alpha'), findsNothing);
    });
  });

  testWidgets('the guide picker offers my categories, not hidden ones', (
    tester,
  ) async {
    final player = FakeExternalPlayer();
    addTearDown(player.dispose);
    final now = DateTime.utc(2026, 3, 1, 20);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(syntheticCatalog(count: 20), hasGuide: true),
          ),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(false),
        ],
        epg: FakeEpgRepository(cached: EpgGuide.empty(fetchedAt: now)),
        now: now,
        favourites: MemoryFavouritesStore(
          _data(
            live: ['Faves'],
            members: [('live0', '7', 'Channel 0007')],
            hiddenLive: {'c2'},
          ),
        ),
        child: const Scaffold(body: GuideScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Channel 0002'), findsNothing);

    await tester.tap(find.byKey(const Key('guide.category')));
    await tester.pumpAndSettle();
    expect(find.text('Category 2'), findsNothing);
    // Above "All channels", which the menu opens on.
    await tester.ensureVisible(find.text('Faves').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Faves').last);
    await tester.pumpAndSettle();
    expect(find.text('Channel 0007'), findsOneWidget);
    expect(find.text('Channel 0001'), findsNothing);
  });

  group('Movies', () {
    Future<void> pump(
      WidgetTester tester,
      MemoryFavouritesStore store,
      Widget child,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          overrides: [
            vodSourceProvider.overrideWithValue(
              FakeVodSource(movies: syntheticMovies(count: 40)),
            ),
            providerKeyProvider.overrideWithValue('test'),
          ],
          favourites: store,
          child: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a poster star adds the movie; my category lists it', (
      tester,
    ) async {
      final store = MemoryFavouritesStore(_data(movies: ['Weekend']));
      await pump(tester, store, const MoviesScreen());

      final star = find.descendant(
        of: find.byKey(const ValueKey(3)),
        matching: find.byKey(const Key('favourite.star')),
      );
      await tester.tap(star);
      await tester.pumpAndSettle();
      await tester.tap(_box('Weekend'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        store.data.itemsIn('movie0').single.item,
        const ItemRef(ContentKind.movie, '3'),
      );
      expect(tester.widget<IconButton>(star).isSelected, isTrue);

      await tester.tap(find.byKey(const Key('movies.my.Weekend')));
      await tester.pumpAndSettle();
      expect(find.text('Movie 00003'), findsOneWidget);
      expect(find.text('Movie 00000'), findsNothing);
    });

    testWidgets('hidden categories leave All movies', (tester) async {
      final store = MemoryFavouritesStore();
      await pump(tester, store, const MoviesScreen());
      await tester.tap(find.byKey(const Key('movies.categories.edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('movies.visibility.m1')));
      await tester.tap(find.byKey(const Key('movies.categories.edit')));
      await tester.pumpAndSettle();
      expect(find.text('Movie category 1'), findsNothing);
      expect(find.text('32'), findsOneWidget); // 40 - 8.
      expect(find.text('Movie 00001'), findsNothing);
      expect(find.text('Movie 00002'), findsOneWidget);
    });

    testWidgets('the detail page has a favourite button', (tester) async {
      final store = MemoryFavouritesStore(_data(movies: ['Weekend']));
      await pump(
        tester,
        store,
        const MovieDetailsScreen(movie: Movie(streamId: 5, name: 'Film')),
      );
      expect(find.text('Add to favourites'), findsOneWidget);
      await tester.tap(find.byKey(const Key('favourite.button')));
      await tester.pumpAndSettle();
      await tester.tap(_box('Weekend'));
      await tester.pumpAndSettle();
      expect(store.data.itemsIn('movie0').single.name, 'Film');
      expect(find.text('In favourites'), findsOneWidget);
    });
  });

  group('Settings', () {
    Future<void> pump(
      WidgetTester tester,
      MemoryFavouritesStore store, {
      FakeSettingsStorage? settings,
    }) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          overrides: [
            liveSourceProvider.overrideWithValue(
              FakeLiveSource(syntheticCatalog(count: 30, categories: 3)),
            ),
            vodSourceProvider.overrideWithValue(FakeVodSource()),
            providerKeyProvider.overrideWithValue('test'),
          ],
          settings: settings,
          favourites: store,
          child: const Scaffold(body: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('stores the global search setting', (tester) async {
      final settings = FakeSettingsStorage();
      await pump(tester, MemoryFavouritesStore(), settings: settings);
      await tester.tap(find.byKey(const Key('settings.searchHidden')));
      await tester.pumpAndSettle();
      expect(settings.saved.showHiddenInGlobalSearch, isTrue);
    });

    testWidgets('the Live TV page hides categories and manages mine', (
      tester,
    ) async {
      final store = MemoryFavouritesStore(_data(live: ['A', 'B']));
      await pump(tester, store);
      expect(find.text('2 categories of mine'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings.categories.live')));
      await tester.pumpAndSettle();
      expect(find.text('Live TV categories'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings.visible.c1')));
      await tester.pumpAndSettle();
      expect(store.data.hiddenIds(ContentKind.live), {'c1'});

      await tester.enterText(
        find.byKey(const Key('settings.categories.filter')),
        'category 2',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings.visible.c0')), findsNothing);
      await tester.tap(find.byKey(const Key('settings.categories.hideAll')));
      await tester.pumpAndSettle();
      expect(store.data.hiddenIds(ContentKind.live), {'c1', 'c2'});

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings.my.A')),
          matching: find.byKey(const Key('settings.my.down')),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.data.categoriesOf(ContentKind.live).map((c) => c.name), [
        'B',
        'A',
      ]);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('settings.my.B')),
          matching: find.byKey(const Key('settings.my.delete')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category.delete.confirm')));
      await tester.pumpAndSettle();
      expect(store.data.categoriesOf(ContentKind.live).map((c) => c.name), [
        'A',
      ]);

      await tester.tap(find.byKey(const Key('settings.categories.new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('category.name')), 'Kids');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(store.data.categoriesOf(ContentKind.live).map((c) => c.name), [
        'A',
        'Kids',
      ]);
    });
  });

  testWidgets('the embedded player opens a favourites panel beside the video', (
    tester,
  ) async {
    final player = FakeExternalPlayer();
    addTearDown(player.dispose);
    final store = MemoryFavouritesStore(_data(live: ['News']));
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(syntheticCatalog(count: 3)),
          ),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(true),
          videoEmbedProvider.overrideWithValue(FakeVideoEmbed()),
        ],
        favourites: store,
        child: const Scaffold(body: LiveTvScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Channel 0001'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    player.emit(player.state.copyWith(status: ExternalPlayerStatus.playing));
    await tester.pump();

    await tester.tap(find.byKey(const Key('player.favourite')));
    await tester.pump();
    final video = tester.getRect(find.byKey(const Key('mpv.video')));
    final panel = tester.getRect(find.byKey(const Key('player.favourites')));
    expect(panel.left, greaterThanOrEqualTo(video.right));

    await tester.tap(find.byKey(const Key('player.favourite.News')));
    await tester.pump();
    expect(
      store.data.isFavourite(const ItemRef(ContentKind.live, '1')),
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('player.favourite')))
          .isSelected,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const Key('player.favourite.newName')),
      'Late',
    );
    await tester.tap(find.byKey(const Key('player.favourite.create')));
    await tester.pump();
    expect(
      store.data.categoriesContaining(const ItemRef(ContentKind.live, '1')),
      hasLength(2),
    );
  });

  test('favourites are loaded and saved per provider', () async {
    final stores = {
      'p1': MemoryFavouritesStore(_data(live: ['One'])),
      'p2': MemoryFavouritesStore(),
    };
    final key = NotifierProvider<_Key, String>(_Key.new);
    final container = ProviderContainer(
      overrides: [
        providerKeyProvider.overrideWith((ref) => ref.watch(key)),
        favouritesStoreProvider.overrideWithValue((k) => stores[k]!),
      ],
    );
    addTearDown(container.dispose);
    container.listen(favouritesProvider, (_, _) {});
    await container.read(favouritesProvider.notifier).saved;
    expect(
      container.read(favouritesProvider).categoriesOf(ContentKind.live),
      hasLength(1),
    );

    container.read(key.notifier).set('p2');
    await container.read(favouritesProvider.notifier).saved;
    expect(container.read(favouritesProvider).categories, isEmpty);
    container
        .read(favouritesProvider.notifier)
        .create(ContentKind.series, 'Two', 'star');
    await container.read(favouritesProvider.notifier).saved;
    expect(stores['p2']!.data.categoriesOf(ContentKind.series), hasLength(1));
    expect(stores['p1']!.saves, 0);
  });

  group('at text scale 1.4', () {
    Widget scaled(Widget child) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.4)),
        child: child,
      ),
    );

    testWidgets('lists, menus and dialogs lay out without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = MemoryFavouritesStore(
        _data(
          live: ['A rather long category name', 'B'],
          movies: ['Weekend'],
          members: [('live0', '1', 'Channel 0001')],
        ),
      );
      Widget app(Widget screen) => testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(syntheticCatalog(count: 30, categories: 3)),
          ),
          vodSourceProvider.overrideWithValue(
            FakeVodSource(movies: syntheticMovies(count: 30)),
          ),
          providerKeyProvider.overrideWithValue('test'),
        ],
        favourites: store,
        child: Scaffold(body: scaled(screen)),
      );

      await tester.pumpWidget(app(const LiveTvScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live.categories.edit')));
      await tester.pumpAndSettle();
      await tester.tap(_starOf('Channel 0002'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favourite.menu.new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('category.icon.night')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(app(const MoviesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('movies.categories.edit')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(app(const SettingsScreen()));
      await tester.pumpAndSettle();
      final live = find.byKey(const Key('settings.categories.live'));
      await tester.scrollUntilVisible(
        live,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(live);
      await tester.pumpAndSettle();
      expect(find.text('Live TV categories'), findsOneWidget);
    });
  });
}

class _Key extends Notifier<String> {
  @override
  String build() => 'p1';

  void set(String key) => state = key;
}
