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
const _ch3 = ItemRef(ContentKind.live, '103');
const _movie = ItemRef(ContentKind.movie, '7');

const _cats = [
  Category(id: 'a', name: 'Alpha'),
  Category(id: 'b', name: 'Beta'),
  Category(id: 'c', name: 'Gamma'),
];

List<String> _ids0(List<Category> c) => [for (final x in c) x.id];

/// [_sample] with channels One, Two, Three added to Sport (id0) in that
/// order, at minutes 10, 11, 12; listed newest first.
FavouritesData _withChannels() {
  var data = _sample();
  for (final (i, (item, name)) in [
    (_ch1, 'One'),
    (_ch2, 'Two'),
    (_ch3, 'Three'),
  ].indexed) {
    data = setMembership(
      data,
      'id0',
      item,
      name: name,
      member: true,
      now: _at(10 + i),
    );
  }
  return data;
}

List<String> _names(FavouritesData data, String id) => [
  for (final m in data.itemsIn(id)) m.name,
];

/// [data] as an older version saved it: items without an order.
Map<String, Object?> _withoutOrder(FavouritesData data) {
  final json = data.toJson();
  for (final r in json['records']! as List) {
    final record = r as Map<String, Object?>;
    if ((record['k']! as String).startsWith('member:')) {
      (record['v']! as Map<String, Object?>).remove('order');
    }
  }
  return jsonDecode(jsonEncode(json)) as Map<String, Object?>;
}

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

    test('a newly added item goes first', () {
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
      expect(data.itemsIn('id0').map((m) => m.name), ['One', 'Two']);
      // Removing and adding again puts it first again.
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
      expect(data.itemsIn('id0').map((m) => m.name), ['Two', 'One']);
      // Only the added item's record changed.
      expect(data.memberships['id0|live:101']!.updatedAt, _at(11));
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

  group('moveTarget', () {
    const ids = ['a', 'b', 'c', 'd'];

    test('up, down and to top, disabled at the ends', () {
      expect(moveTarget(ids, 'c', MoveStep.up), 1);
      expect(moveTarget(ids, 'b', MoveStep.down), 2);
      expect(moveTarget(ids, 'c', MoveStep.top), 0);
      expect(moveTarget(ids, 'a', MoveStep.up), isNull);
      expect(moveTarget(ids, 'a', MoveStep.top), isNull);
      expect(moveTarget(ids, 'd', MoveStep.down), isNull);
      expect(moveTarget(ids, 'x', MoveStep.up), isNull);
    });

    test('passes over skipped entries', () {
      // b is hidden: the visible order a, c, d.
      expect(moveTarget(ids, 'c', MoveStep.up, skip: {'b'}), 0);
      expect(moveTarget(ids, 'a', MoveStep.down, skip: {'b'}), 2);
      expect(moveTarget(['b', 'a'], 'a', MoveStep.up, skip: {'b'}), isNull);
      expect(moveTarget(['b', 'a'], 'a', MoveStep.top, skip: {'b'}), isNull);
      expect(moveTarget(['a', 'b'], 'a', MoveStep.down, skip: {'b'}), isNull);
    });
  });

  group('item order', () {
    test('move renumbers, touching only items whose position changes', () {
      var data = _withChannels();
      expect(_names(data, 'id0'), ['Three', 'Two', 'One']);
      data = moveFavouriteItem(data, 'id0', _ch1, toIndex: 0, now: _at(20));
      expect(_names(data, 'id0'), ['One', 'Three', 'Two']);
      data = moveFavouriteItem(data, 'id0', _ch3, toIndex: 2, now: _at(21));
      expect(_names(data, 'id0'), ['One', 'Two', 'Three']);
      // One was added first (order 0) and stayed at 0: never touched.
      expect(data.memberships['id0|live:101']!.updatedAt, _at(10));
      expect(data.memberships['id0|live:102']!.updatedAt, _at(21));
      expect(
        moveFavouriteItem(data, 'id0', _ch1, toIndex: -5, now: _at(22)),
        same(data),
      );
      expect(
        moveFavouriteItem(data, 'id1', _ch1, toIndex: 0, now: _at(22)),
        same(data),
      );
    });

    test('move to top with moveTarget', () {
      var data = _withChannels();
      final ids = [for (final m in data.itemsIn('id0')) m.item.id];
      final to = moveTarget(ids, _ch1.id, MoveStep.top)!;
      data = moveFavouriteItem(data, 'id0', _ch1, toIndex: to, now: _at(20));
      expect(_names(data, 'id0'), ['One', 'Three', 'Two']);
    });

    test('is per category', () {
      var data = _withChannels();
      data = setMembership(
        data,
        'id1',
        _ch1,
        name: 'One',
        member: true,
        now: _at(20),
      );
      data = setMembership(
        data,
        'id1',
        _ch2,
        name: 'Two',
        member: true,
        now: _at(21),
      );
      data = moveFavouriteItem(data, 'id1', _ch1, toIndex: 0, now: _at(22));
      expect(_names(data, 'id1'), ['One', 'Two']);
      expect(_names(data, 'id0'), ['Three', 'Two', 'One']);
    });

    test('a reorder on one device and an add on another merge', () {
      final base = _withChannels();
      final a = moveFavouriteItem(base, 'id0', _ch3, toIndex: 2, now: _at(20));
      final b = setMembership(
        base,
        'id0',
        const ItemRef(ContentKind.live, '104'),
        name: 'Four',
        member: true,
        now: _at(21),
      );
      for (final merged in [a.merge(b), b.merge(a)]) {
        expect(_names(merged, 'id0'), ['Four', 'Two', 'One', 'Three']);
      }
    });

    test('round-trips through JSON', () {
      final data = moveFavouriteItem(
        _withChannels(),
        'id0',
        _ch1,
        toIndex: 0,
        now: _at(20),
      );
      final back = FavouritesData.fromJson(
        jsonDecode(jsonEncode(data.toJson())),
      )!;
      expect(back.memberships, data.memberships);
      expect(_names(back, 'id0'), ['One', 'Three', 'Two']);
    });
  });

  group('migration of items saved without an order', () {
    /// Items added One, Two, Three, as an older version listed them.
    FavouritesData old() {
      var data = _sample();
      for (final (i, (item, name)) in [
        (_ch1, 'One'),
        (_ch2, 'Two'),
        (_ch3, 'Three'),
      ].indexed) {
        data = setMembership(
          data,
          'id0',
          item,
          name: name,
          member: true,
          now: _at(10 + i),
        );
      }
      return FavouritesData.fromJson(_withoutOrder(data))!;
    }

    test('keep the order they were added in, without a new change time', () {
      final data = old();
      expect(_names(data, 'id0'), ['One', 'Two', 'Three']);
      expect(data.memberships['id0|live:101']!.updatedAt, _at(10));
      expect(data.memberships['id0|live:103']!.updatedAt, _at(12));
      // Saved and read again: the same.
      final back = FavouritesData.fromJson(
        jsonDecode(jsonEncode(data.toJson())),
      )!;
      expect(back.memberships, data.memberships);
    });

    test('a new item then goes first; moves work', () {
      var data = setMembership(
        old(),
        'id0',
        const ItemRef(ContentKind.live, '104'),
        name: 'Four',
        member: true,
        now: _at(20),
      );
      expect(_names(data, 'id0'), ['Four', 'One', 'Two', 'Three']);
      data = moveFavouriteItem(data, 'id0', _ch3, toIndex: 1, now: _at(21));
      expect(_names(data, 'id0'), ['Four', 'Three', 'One', 'Two']);
    });

    test('next to ordered items, unordered ones go first, newest first', () {
      // This version's data, then two items added by an older version.
      var data = _withChannels();
      data = moveFavouriteItem(data, 'id0', _ch1, toIndex: 0, now: _at(20));
      for (final (i, id) in ['104', '105'].indexed) {
        data = setMembership(
          data,
          'id0',
          ItemRef(ContentKind.live, id),
          name: 'Old $id',
          member: true,
          now: _at(30 + i),
        );
      }
      final json = data.toJson();
      for (final r in json['records']! as List) {
        final record = r as Map<String, Object?>;
        if ((record['k']! as String).contains(':10') &&
            ['104', '105'].any((id) => (record['k']! as String).endsWith(id))) {
          (record['v']! as Map<String, Object?>).remove('order');
        }
      }
      final back = FavouritesData.fromJson(jsonDecode(jsonEncode(json)))!;
      expect(_names(back, 'id0'), [
        'Old 105',
        'Old 104',
        'One',
        'Three',
        'Two',
      ]);
    });

    test('a later record with an order wins over an older one without', () {
      final data = _withChannels();
      final json = data.toJson();
      final records = json['records']! as List;
      final first = records.cast<Map<String, Object?>>().firstWhere(
        (r) => r['k'] == 'member:id0|live:101',
      );
      // The same key once more, without an order, before it.
      records.insert(0, {
        ...first,
        'v': {...(first['v']! as Map<String, Object?>)}..remove('order'),
      });
      final back = FavouritesData.fromJson(jsonDecode(jsonEncode(json)))!;
      expect(back.memberships, data.memberships);
    });
  });

  group('provider category order', () {
    test('is the provider order until moved', () {
      final data = _sample();
      expect(data.orderedCategories(ContentKind.live, _cats), _cats);
      expect(data.categoryOrder(ContentKind.live), isNull);
    });

    test('move saves the whole order, per kind', () {
      final data = moveProviderCategory(
        _sample(),
        ContentKind.live,
        _cats,
        'c',
        toIndex: 0,
        now: _at(20),
      );
      expect(_ids0(data.orderedCategories(ContentKind.live, _cats)), [
        'c',
        'a',
        'b',
      ]);
      expect(data.categoryOrder(ContentKind.live)!.names, [
        'Gamma',
        'Alpha',
        'Beta',
      ]);
      expect(data.orderedCategories(ContentKind.movie, _cats), _cats);
      expect(
        moveProviderCategory(
          data,
          ContentKind.live,
          _cats,
          'c',
          toIndex: 0,
          now: _at(21),
        ),
        same(data),
      );
    });

    test('new categories go at the end, removed ones disappear', () {
      var data = moveProviderCategory(
        _sample(),
        ContentKind.live,
        _cats,
        'c',
        toIndex: 0,
        now: _at(20),
      );
      // The provider drops Beta and adds Delta and Epsilon.
      const later = [
        Category(id: 'e', name: 'Epsilon'),
        Category(id: 'a', name: 'Alpha'),
        Category(id: 'c', name: 'Gamma'),
        Category(id: 'd', name: 'Delta'),
      ];
      expect(_ids0(data.orderedCategories(ContentKind.live, later)), [
        'c',
        'a',
        'e',
        'd',
      ]);
      // The next move saves it without Beta.
      data = moveProviderCategory(
        data,
        ContentKind.live,
        later,
        'd',
        toIndex: 0,
        now: _at(21),
      );
      expect(data.categoryOrder(ContentKind.live)!.ids, ['d', 'c', 'a', 'e']);
    });

    test('reset, undo and merge', () {
      final moved = moveProviderCategory(
        _sample(),
        ContentKind.live,
        _cats,
        'c',
        toIndex: 0,
        now: _at(20),
      );
      final previous = moved.categoryOrder(ContentKind.live);
      final reset = resetCategoryOrder(moved, ContentKind.live, now: _at(21));
      expect(reset.orderedCategories(ContentKind.live, _cats), _cats);
      expect(reset.categoryOrders['live']!.deleted, isTrue);
      expect(
        resetCategoryOrder(reset, ContentKind.live, now: _at(22)),
        same(reset),
      );
      // The reset wins over the earlier move from another copy.
      expect(moved.merge(reset).categoryOrder(ContentKind.live), isNull);
      expect(reset.merge(moved).categoryOrder(ContentKind.live), isNull);

      final undone = restoreCategoryOrder(
        reset,
        ContentKind.live,
        previous,
        now: _at(22),
      );
      expect(_ids0(undone.orderedCategories(ContentKind.live, _cats)), [
        'c',
        'a',
        'b',
      ]);
      expect(
        restoreCategoryOrder(
          undone,
          ContentKind.live,
          null,
          now: _at(23),
        ).categoryOrder(ContentKind.live),
        isNull,
      );
    });

    test('round-trips through JSON, resets included', () {
      var data = moveProviderCategory(
        _sample(),
        ContentKind.live,
        _cats,
        'b',
        toIndex: 0,
        now: _at(20),
      );
      data = moveProviderCategory(
        data,
        ContentKind.series,
        _cats,
        'c',
        toIndex: 0,
        now: _at(21),
      );
      data = resetCategoryOrder(data, ContentKind.series, now: _at(22));
      final back = FavouritesData.fromJson(
        jsonDecode(jsonEncode(data.toJson())),
      )!;
      expect(back.categoryOrders, data.categoryOrders);
      expect(_ids0(back.orderedCategories(ContentKind.live, _cats)), [
        'b',
        'a',
        'c',
      ]);
      expect(back.categoryOrder(ContentKind.series), isNull);
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
