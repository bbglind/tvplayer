import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

final _tags = ProviderTags.fromNames([
  for (var i = 0; i < 3; i++) ...['EN - A$i', 'NF - B$i', '4K-SC - C$i'],
]);

VariantGroups _groups(List<VariantItem> items) =>
    VariantGroups.build(items, _tags);

VariantItem _item(int id, String name, {String? tmdb, int? year}) =>
    (id: id, name: name, tmdbId: tmdb, year: year);

void main() {
  test('variants share a TMDB id; the item itself is left out', () {
    final g = _groups([
      _item(1, 'EN - Copper Valley (2024)', tmdb: '501', year: 2024),
      _item(2, 'NF - Copper Valley (2024)', tmdb: '501', year: 2024),
      _item(3, '4K-SC - Copper Valley', tmdb: '501'),
      _item(4, 'EN - Glass Tide (2024)', tmdb: '777', year: 2024),
    ]);
    expect(g.variantsOf(1), [2, 3]);
    expect(g.variantsOf(3), [1, 2]);
    expect(g.variantsOf(4), isEmpty);
    expect(g.groupOf(4), [4]);
    expect(g.keyOf(1), g.keyOf(2));
    expect(g.keyOf(1), isNot(g.keyOf(4)));
  });

  test('the same id with years far apart is not a variant', () {
    final g = _groups([
      _item(1, 'NF - Paper Moth (2025)', tmdb: '9', year: 2025),
      _item(2, 'EN - Paper Moth (1969)', tmdb: '9', year: 1969),
      _item(3, 'EN - Paper Moth (2026)', tmdb: '9', year: 2026),
    ]);
    expect(g.variantsOf(1), [3]);
    expect(g.variantsOf(2), isEmpty);
  });

  test('ids 0 or empty count as none', () {
    final g = _groups([
      _item(1, 'EN - Lantern Bay (2020)', tmdb: '0', year: 2020),
      _item(2, 'NF - Lantern Bay (2020)', tmdb: '', year: 2020),
      _item(3, 'EN - North Pier (2020)', tmdb: '0', year: 2020),
    ]);
    // Matched by title and year instead.
    expect(g.variantsOf(1), [2]);
    expect(g.variantsOf(3), isEmpty);
  });

  test('without an id the title and year must both match', () {
    final g = _groups([
      // Weekly shows: same name, no year, separate items.
      _item(1, 'EN - Night Bout'),
      _item(2, 'EN - Night Bout'),
      _item(3, 'EN - Lantern Bay (2020)', year: 2020),
      _item(4, 'NF - Lantern Bay! (2020)', year: 2020),
      _item(5, '4K-SC - Lantern Bay (2021)', year: 2021),
    ]);
    expect(g.variantsOf(1), isEmpty);
    // Punctuation doesn't matter; the year does.
    expect(g.variantsOf(3), [4]);
    expect(g.variantsOf(5), isEmpty);
  });

  test('an item without an id joins the one TMDB group of its title', () {
    final g = _groups([
      _item(1, 'EN - Copper Valley (2024)', tmdb: '501', year: 2024),
      _item(2, 'NF - Copper Valley (2024)', year: 2024),
    ]);
    expect(g.variantsOf(2), [1]);
  });

  test('no bridging between two works with the same title and year', () {
    final g = _groups([
      _item(1, 'EN - Echo (2023)', tmdb: '11', year: 2023),
      _item(2, 'NF - Echo (2023)', tmdb: '12', year: 2023),
      _item(3, '4K-SC - Echo (2023)', year: 2023),
      _item(4, 'EN - Echo (2023)', year: 2023),
    ]);
    expect(g.variantsOf(1), isEmpty);
    expect(g.variantsOf(2), isEmpty);
    // Grouped only with the other one without an id.
    expect(g.variantsOf(3), [4]);
  });

  test('built from catalogue models', () {
    final movies = VariantGroups.movies(const [
      Movie(streamId: 1, name: 'EN - A (2020)', tmdbId: '5'),
      Movie(streamId: 2, name: 'NF - A (2020)', tmdbId: '5'),
    ], _tags);
    expect(movies.variantsOf(1), [2]);
    final series = VariantGroups.series(const [
      Series(
        seriesId: 1,
        name: 'EN - S',
        tmdbId: '6',
        releaseDate: '2019-01-01',
      ),
      Series(seriesId: 2, name: 'NF - S (2019)', tmdbId: '6'),
    ], _tags);
    expect(series.variantsOf(2), [1]);
    expect(VariantGroups.empty.variantsOf(1), isEmpty);
  });
}
