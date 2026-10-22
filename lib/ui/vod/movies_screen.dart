import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/providers.dart';
import 'movie_details_screen.dart';
import 'poster.dart';
import 'vod_browser.dart';

/// The Movies tab: categories, search, "Continue watching" and a poster
/// grid.
class MoviesScreen extends ConsumerWidget {
  const MoviesScreen({super.key});

  static void _open(BuildContext context, Movie movie) => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => MovieDetailsScreen(movie: movie),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(movieCatalogProvider);
    final filter = ref.watch(movieFilterProvider);
    final watch = ref.watch(watchProvider);
    final catalog = state.catalog;
    final filterNotifier = ref.read(movieFilterProvider.notifier);
    return VodBrowser<Movie>(
      what: 'movies',
      state: state,
      filter: filter,
      onCategory: filterNotifier.selectCategory,
      onQuery: filterNotifier.setQuery,
      onRefresh: ref.read(movieCatalogProvider.notifier).refresh,
      continueWatching: [
        if (catalog != null)
          for (final (id, progress) in continueMovies(watch))
            if (catalog.byId(id) case final movie?)
              PosterCard(
                key: ValueKey('continue.${movie.streamId}'),
                title: movie.name,
                subtitle: 'Resume at ${formatDuration(progress.position)}',
                imageUrl: movie.posterUrl,
                progress: progress.fraction,
                onTap: () => _open(context, movie),
              ),
      ],
      itemBuilder: (context, movie) {
        final progress = watch.movie(movie.streamId);
        return PosterCard(
          key: ValueKey(movie.streamId),
          title: movie.name,
          subtitle: movie.year?.toString(),
          imageUrl: movie.posterUrl,
          watched: progress?.watched ?? false,
          progress: isInProgress(progress) ? progress!.fraction : null,
          onTap: () => _open(context, movie),
        );
      },
    );
  }
}
