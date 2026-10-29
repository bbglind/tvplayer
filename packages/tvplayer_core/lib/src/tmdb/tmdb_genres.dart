import '../models/movie.dart';
import '../models/series.dart';
import '../vod/vod_query.dart';
import 'tmdb_links.dart';
import 'tmdb_models.dart';

/// Genre names of TMDB titles, by title.
typedef TmdbGenreIndex = Map<TmdbKey, List<String>>;

/// A genre name reduced for comparing: lower case, `&` as "and", without
/// spaces, hyphens, dots and apostrophes (`Sci-Fi & Fantasy` →
/// `scifiandfantasy`).
String genreKey(String name) => name
    .toLowerCase()
    .replaceAll('&', 'and')
    .replaceAll(RegExp(r"[\s\-.'’]"), '');

/// Provider genre names (by [genreKey]) and the TMDB series genre they
/// stand for.
const _providerToTmdbTv = {
  'action': 'Action & Adventure',
  'adventure': 'Action & Adventure',
  'actionandadventure': 'Action & Adventure',
  'actionadventure': 'Action & Adventure',
  'scifi': 'Sci-Fi & Fantasy',
  'sciencefiction': 'Sci-Fi & Fantasy',
  'scifiandfantasy': 'Sci-Fi & Fantasy',
  'sciencefictionandfantasy': 'Sci-Fi & Fantasy',
  'fantasy': 'Sci-Fi & Fantasy',
  'war': 'War & Politics',
  'politics': 'War & Politics',
  'warandpolitics': 'War & Politics',
  'kids': 'Kids',
  'children': 'Kids',
  'childrens': 'Kids',
  'documentary': 'Documentary',
  'documentaries': 'Documentary',
  'docu': 'Documentary',
  'reality': 'Reality',
  'realitytv': 'Reality',
  'talk': 'Talk',
  'talkshow': 'Talk',
  'soap': 'Soap',
  'soapopera': 'Soap',
  'animation': 'Animation',
  'animated': 'Animation',
  'comedy': 'Comedy',
  'crime': 'Crime',
  'drama': 'Drama',
  'family': 'Family',
  'mystery': 'Mystery',
  'news': 'News',
  'western': 'Western',
};

/// A provider's series genres ([splitGenres] output) as TMDB names them
/// for series (`Sci-Fi` → `Sci-Fi & Fantasy`, `Adventure` → `Action &
/// Adventure`), without duplicates. Names TMDB has no series genre for
/// (`Horror`, `Thriller`…) are kept, in title case when the provider sends
/// them all in lower or upper case.
List<String> providerGenresToTmdb(List<String> genres) {
  final seen = <String>{};
  return [
    for (final g in genres)
      if (_providerToTmdbTv[genreKey(g)] ?? _tidy(g) case final name
          when seen.add(name.toLowerCase()))
        name,
  ];
}

String _tidy(String name) {
  if (name != name.toLowerCase() && name != name.toUpperCase()) return name;
  return name
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// The TMDB genres of a movie (TMDB's movie genre names); none without a
/// TMDB title or before its genres are stored.
GenreSource<Movie> tmdbMovieGenres(TmdbLinks links, TmdbGenreIndex index) =>
    (m) => switch (links.movie(m.streamId)) {
      final link? => index[link.key] ?? const [],
      null => const [],
    };

/// The TMDB genres of a series (TMDB's series genre names); when it has
/// none, the provider's mapped by [providerGenresToTmdb].
GenreSource<Series> tmdbSeriesGenres(TmdbLinks links, TmdbGenreIndex index) =>
    (s) => switch (links.series(s.seriesId)) {
      TmdbLink(:final key) when index[key]?.isNotEmpty ?? false => index[key]!,
      _ => providerSeriesGenres(s),
    };

/// The provider's genres of [series] with TMDB's names.
List<String> providerSeriesGenres(Series series) =>
    providerGenresToTmdb(splitGenres(series.genre));

/// The family a genre belongs to for "Featured": movie and series genres
/// that mean the same (`Science Fiction`, `Fantasy` and `Sci-Fi &
/// Fantasy`; `Action`, `Adventure` and `Action & Adventure`; `War` and
/// `War & Politics`) share one, other names are their own.
String genreFamily(String name) => switch (genreKey(name)) {
  'sciencefiction' ||
  'fantasy' ||
  'scifi' ||
  'scifiandfantasy' ||
  'sciencefictionandfantasy' => 'scifiandfantasy',
  'action' ||
  'adventure' ||
  'actionandadventure' ||
  'actionadventure' => 'actionandadventure',
  'war' || 'warandpolitics' => 'warandpolitics',
  final key => key,
};
