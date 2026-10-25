import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _t0 = DateTime.utc(2026, 3, 1, 12);

DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

/// Ids `id0`, `id1`, … in creation order.
String Function() _ids() {
  var n = 0;
  return () => 'id${n++}';
}

const _ch1 = ItemRef(ContentKind.live, '101');
const _ch2 = ItemRef(ContentKind.live, '102');
const _movie = ItemRef(ContentKind.movie, '7');

/// Two live categories ("Sport" id0, "News" id1) and one movie category
/// ("Weekend" id2).
FavouritesData _sample() {
  final ids = _ids();
  var data = FavouritesData.empty;
  for (final (i, (kind, name)) in [
    (ContentKind.live, 'Sport'),
    (ContentKind.live, 'News'),
    (ContentKind.movie, 'Weekend'),
  ].indexed) {
    (data, _) = createCategory(
      data,
      kind: kind,
      name: name,
      icon: 'star',
      now: _at(i),
      newId: ids,
    );
  }
  return data;
}

void main() {
  group('newFavouriteId', () {
    test('is 32 hex digits and differs between calls', () {
      final a = newFavouriteId();
      final b = newFavouriteId();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, isNot(b));
    });

    test('uses the given random source', () {
      expect(newFavouriteId(Random(1)), newFavouriteId(Random(1)));
    });
  });

  group('categories', () {
    test('are created at the end, per kind, with cleaned names', () {
      final data = _sample();
      expect(data.categoriesOf(ContentKind.live).map((c) => c.name), [
        'Sport',
        'News',
      ]);
      expect(data.categoriesOf(ContentKind.movie).single.name, 'Weekend');
      expect(data.categoriesOf(ContentKind.series), isEmpty);

      final (named, c) = createCategory(
        data,
        kind: ContentKind.series,
        name: '  Late   night  ',
        icon: 'moon',
        now: _at(9),
      );
      expect(c!.name, 'Late night');
      expect(c.createdAt, _at(9));
      expect(named.categoriesOf(ContentKind.series), [c]);
    });

    test('need a name', () {
      final data = _sample();
      final (same, c) = createCategory(
        data,
        kind: ContentKind.live,
        name: '   ',
        icon: 'star',
        now: _at(9),
      );
      expect(c, isNull);
      expect(identical(same, data), isTrue);
      expect(cleanFavouriteName('x' * 60)!.length, maxFavouriteNameLength);
    });

    test('rename and change icon', () {
      var data = renameCategory(_sample(), 'id0', 'Football', now: _at(10));
      data = setCategoryIcon(data, 'id0', 'soccer', now: _at(11));
      final c = data.category('id0')!;
      expect((c.name, c.icon, c.updatedAt), ('Football', 'soccer', _at(11)));
      expect(c.createdAt, _at(0));
      // Empty names and unknown ids change nothing.
      expect(
        identical(renameCategory(data, 'id0', ' ', now: _at(12)), data),
        isTrue,
      );
      expect(
        identical(renameCategory(data, 'nope', 'X', now: _at(12)), data),
        isTrue,
      );
    });

    test('move, touching only categories whose position changes', () {
      var data = _sample();
      for (final name in ['Kids', 'Music']) {
        (data, _) = createCategory(
          data,
          kind: ContentKind.live,
          name: name,
          icon: 'star',
          now: _at(5),
        );
      }
      final before = data.categoriesOf(ContentKind.live);
      data = moveCategory(data, before[3].id, toIndex: 1, now: _at(20));
      final after = data.categoriesOf(ContentKind.live);
      expect(after.map((c) => c.name), ['Sport', 'Music', 'News', 'Kids']);
      expect(after.first.updatedAt, _at(0)); // Stayed at 0.
      expect(after[1].updatedAt, _at(20));
      // The movie category is untouched; out-of-range indexes are clamped.
      expect(data.categoriesOf(ContentKind.movie).single.updatedAt, _at(2));
      data = moveCategory(data, 'id0', toIndex: 99, now: _at(21));
      expect(data.categoriesOf(ContentKind.live).last.name, 'Sport');
    });

    test('delete leaves tombstones for the category and its items', () {
      var data = setMembership(
        _sample(),
        'id0',
        _ch1,
        name: 'One',
        member: true,
        now: _at(10),
      );
      data = deleteCategory(data, 'id0', now: _at(11));
      expect(data.category('id0'), isNull);
      expect(data.categories['id0']!.deleted, isTrue);
      expect(data.categoriesOf(ContentKind.live).map((c) => c.name), ['News']);
      expect(data.isFavourite(_ch1), isFalse);
      final m = data.memberships.values.single;
      expect((m.deleted, m.updatedAt), (true, _at(11)));
    });
  });

  group('memberships', () {
    test('an item can be in several categories', () {
      var data = _sample();
      for (final id in ['id0', 'id1']) {
        data = setMembership(
          data,
          id,
          _ch1,
          name: 'One',
          member: true,
          now: _at(10),
        );
      }
      expect(data.categoriesContaining(_ch1), {'id0', 'id1'});
      expect(data.isFavourite(_ch1), isTrue);
      expect(data.isFavourite(_ch2), isFalse);

      data = setMembership(
        data,
        'id0',
        _ch1,
        name: 'One',
        member: false,
        now: _at(11),
      );
      expect(data.categoriesContaining(_ch1), {'id1'});
      expect(data.countIn('id0'), 0);
    });

    test('items are listed in the order they were added', () {
      var data = _sample();
      data = setMembership(
        data,
        'id0',
        _ch2,
        name: 'Two',
        member: true,
        now: _at(10),
      );
      data = setMembership(
        data,
        'id0',
        _ch1,
        name: 'One',
        member: true,
        now: _at(11),
      );
      expect(data.itemsIn('id0').map((m) => m.name), ['Two', 'One']);
      // Removing and adding again moves it to the end.
      data = setMembership(
        data,
        'id0',
        _ch2,
        name: 'Two',
        member: false,
        now: _at(12),
      );
      data = setMembership(
        data,
        'id0',
        _ch2,
        name: 'Two',
        member: true,
        now: _at(13),
      );
      expect(data.itemsIn('id0').map((m) => m.name), ['One', 'Two']);
    });

    test('need an existing category of the same kind', () {
      final data = _sample();
      for (final (category, item) in [
        ('id2', _ch1),
        ('id0', _movie),
        ('missing', _ch1),
      ]) {
        expect(
          identical(
            setMembership(
              data,
              category,
              item,
              name: 'x',
              member: true,
              now: _at(10),
            ),
            data,
          ),
          isTrue,
        );
      }
    });

    test('setting the same state again changes nothing', () {
      final data = setMembership(
        _sample(),
        'id2',
        _movie,
        name: 'Film',
        member: true,
        now: _at(10),
      );
      expect(
        identical(
          setMembership(
            data,
            'id2',
            _movie,
            name: 'Film',
            member: true,
            now: _at(11),
          ),
          data,
        ),
        isTrue,
      );
    });
  });

  group('hidden categories', () {
    test('are per kind and can be shown again', () {
      var data = setCategoriesHidden(
        _sample(),
        ContentKind.live,
        ['a', 'b'],
        hidden: true,
        now: _at(10),
      );
      data = setCategoriesHidden(
        data,
        ContentKind.movie,
        ['a'],
        hidden: true,
        now: _at(10),
      );
      expect(data.hiddenIds(ContentKind.live), {'a', 'b'});
      expect(data.hiddenIds(ContentKind.movie), {'a'});

      data = setCategoriesHidden(
        data,
        ContentKind.live,
        ['a'],
        hidden: false,
        now: _at(11),
      );
      expect(data.hiddenIds(ContentKind.live), {'b'});
      // The "shown" record stays, so it wins a merge.
      expect(data.hidden['live:a']!.hidden, isFalse);
      expect(
        identical(
          setCategoriesHidden(
            data,
            ContentKind.live,
            ['b'],
            hidden: true,
            now: _at(12),
          ),
          data,
        ),
        isTrue,
      );
    });
  });

  group('JSON', () {
    FavouritesData full() {
      var data = setMembership(
        _sample(),
        'id0',
        _ch1,
        name: 'One',
        member: true,
        now: _at(10),
      );
      data = setMembership(
        data,
        'id2',
        _movie,
        name: 'Film',
        member: true,
        now: _at(11),
      );
      data = deleteCategory(data, 'id1', now: _at(12));
      return setCategoriesHidden(
        data,
        ContentKind.series,
        ['s|1:x'],
        hidden: true,
        now: _at(13),
      );
    }

    test('round-trips every record, tombstones included', () {
      final data = full();
      final back = FavouritesData.fromJson(
        jsonDecode(jsonEncode(data.toJson())),
      )!;
      expect(back.categories, data.categories);
      expect(back.memberships, data.memberships);
      expect(back.hidden, data.hidden);
      expect(back.hiddenIds(ContentKind.series), {'s|1:x'});
    });

    test('skips unreadable records and rejects non-data', () {
      final json = full().toJson();
      json['records'] = <Object?>[
        ...json['records']! as List,
        'junk',
        {'k': 'category:x', 't': 'later'},
        {'k': 'unknown:1', 't': 1, 'v': {}},
        {
          'k': 'member:x',
          't': 1,
          'v': {'kind': 'radio'},
        },
      ];
      expect(FavouritesData.fromJson(json)!.categories.length, 3);
      expect(FavouritesData.fromJson('nope'), isNull);
      expect(FavouritesData.fromJson({'version': 1}), isNull);
    });
  });

  group('merge', () {
    test('keeps the newest record, including deletions', () {
      final base = _sample();
      // Device A renames Sport; device B deletes News and adds a channel.
      final a = renameCategory(base, 'id0', 'Football', now: _at(20));
      var b = deleteCategory(base, 'id1', now: _at(21));
      b = setMembership(
        b,
        'id0',
        _ch1,
        name: 'One',
        member: true,
        now: _at(22),
      );
      for (final merged in [a.merge(b), b.merge(a)]) {
        expect(merged.categoriesOf(ContentKind.live).map((c) => c.name), [
          'Football',
        ]);
        expect(merged.categoriesContaining(_ch1), {'id0'});
      }
    });

    test('a later removal beats an earlier add', () {
      final added = setMembership(
        _sample(),
        'id0',
        _ch1,
        name: 'One',
        member: true,
        now: _at(10),
      );
      final removed = setMembership(
        added,
        'id0',
        _ch1,
        name: 'One',
        member: false,
        now: _at(11),
      );
      expect(added.merge(removed).isFavourite(_ch1), isFalse);
      expect(removed.merge(added).isFavourite(_ch1), isFalse);
    });
  });

  group('JsonFileFavouritesStore', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('favourites_test');
      file = File('${dir.path}/fav/key.json');
    });

    tearDown(() => dir.delete(recursive: true));

    test('saves and loads, and is empty without a file', () async {
      final store = JsonFileFavouritesStore(file);
      expect((await store.load()).categories, isEmpty);
      final data = _sample();
      await store.save(data);
      expect((await store.load()).categories, data.categories);
      expect(File('${file.path}.bak').existsSync(), isTrue);
    });

    test('falls back to the backup and keeps a damaged file', () async {
      final store = JsonFileFavouritesStore(file);
      await store.save(_sample());
      await store.load(); // Makes the backup.
      await file.writeAsString('{"records": [trunc');

      final loaded = await store.load();
      expect(loaded.categoriesOf(ContentKind.live).length, 2);
      expect(
        File('${file.path}.corrupt').readAsStringSync(),
        '{"records": [trunc',
      );
      expect(file.existsSync(), isFalse);
      // Saving again writes a fresh file.
      await store.save(loaded);
      expect((await store.load()).categories.length, 3);
    });

    test('is empty when file and backup are damaged', () async {
      await file.parent.create(recursive: true);
      await file.writeAsString('not json');
      await File('${file.path}.bak').writeAsString('[]');
      final loaded = await JsonFileFavouritesStore(file).load();
      expect(loaded.categories, isEmpty);
    });
  });

  group('catalogues', () {
    final live = LiveCatalog(
      categories: const [
        Category(id: 'a', name: 'A'),
        Category(id: 'b', name: 'B'),
      ],
      channels: const [
        LiveStream(id: '1', name: 'In A', categoryIds: ['a']),
        LiveStream(id: '2', name: 'In A and B', categoryIds: ['a', 'b']),
        LiveStream(id: '3', name: 'In B', categoryIds: ['b'], stableId: 's3'),
        LiveStream(id: '4', name: '### B ###', categoryIds: ['b']),
        LiveStream(id: '5', name: 'No category'),
      ],
    );

    test('live: hidden only when all categories are hidden', () {
      expect(live.countExcluding({}), 4);
      expect(live.countExcluding({'b'}), 3);
      expect(live.channelsExcluding({'b'}).map((c) => c.id), ['1', '2', '5']);
      expect(live.countExcluding({'a', 'b'}), 1);
    });

    test('live: lookup by stable id', () {
      expect(live.byStableId('s3')!.id, '3');
      expect(live.byStableId('1')!.name, 'In A');
      expect(live.byStableId('3'), isNull);
    });

    test('M3U stable ids use the tvg-id, made unique with the name', () {
      expect(
        m3uStableIds(const [
          M3uEntry(name: 'One', url: 'http://example.com/1', tvgId: 'one.se'),
          M3uEntry(name: 'Two HD', url: 'http://example.com/2', tvgId: 'two'),
          M3uEntry(name: 'Two SD', url: 'http://example.com/3', tvgId: 'two'),
          M3uEntry(name: ' Three ', url: 'http://example.com/4', tvgId: ''),
        ]),
        ['tvg:one.se', 'tvg:two|Two HD', 'tvg:two|Two SD', 'name:Three'],
      );
    });

    test('VOD: hidden categories are left out of all items', () {
      final movies = VodCatalog.movies(
        categories: const [
          Category(id: 'a', name: 'A'),
          Category(id: 'b', name: 'B'),
        ],
        items: const [
          Movie(streamId: 1, name: 'Alpha', categoryId: 'a'),
          Movie(streamId: 2, name: 'Beta', categoryId: 'b'),
          Movie(streamId: 3, name: 'Gamma', categoryId: 'a'),
          Movie(streamId: 4, name: 'Delta'),
        ],
        fetchedAt: _t0,
      );
      expect(movies.countExcluding({'a'}), 2);
      List<String> names(List<Movie> list) => [for (final m in list) m.name];
      expect(
        movies
            .query(scope: const VodScope.all(hidden: {'a'}))
            .map((m) => m.streamId),
        [2, 4],
      );
      expect(
        names(
          movies.query(
            scope: const VodScope.all(hidden: {'a'}),
            search: 'ta',
          ),
        ),
        ['Beta', 'Delta'],
      );
      // A chosen category still shows, even when hidden.
      expect(movies.query(scope: const VodScope.category('a')).length, 2);
      expect(names(movies.query(scope: const VodScope.ids([3, 99, 1]))), [
        'Gamma',
        'Alpha',
      ]);
      expect(
        names(movies.query(scope: const VodScope.ids([3, 1]), search: 'AL')),
        ['Alpha'],
      );
    });
  });
}
