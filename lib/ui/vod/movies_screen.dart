import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/playlist_refresh.dart';
import '../../state/providers.dart';
import '../../state/variants.dart';
import '../home/continue_actions.dart';
import 'movie_details_screen.dart';
import 'poster.dart';
import 'vod_browser.dart';

/// Opens the details page of [movie].
void openMovie(BuildContext context, Movie movie) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => MovieDetailsScreen(movie: movie)),
);

/// The poster of [movie] in a grid: title, year (or [subtitle]),
/// favourite star and watch state, together with its other sources.
/// [lastPlayed] marks the source played last.
Widget moviePoster(
  BuildContext context,
  Movie movie, {
  Key? key,
  FocusNode? focusNode,
  String? subtitle,
  bool lastPlayed = false,
}) => Consumer(
  builder: (context, ref, _) {
    final progress = ref.watch(movieProgressProvider(movie.streamId))?.progress;
    return PosterCard(
      key: key ?? ValueKey(movie.streamId),
      focusNode: focusNode,
      title: movie.name,
      favourite: movieItemRef(movie),
      subtitle: subtitle ?? movie.year?.toString(),
      subtitleIcon: lastPlayed ? Icons.history : null,
      subtitleIconTooltip: lastPlayed ? 'Last played' : null,
      imageUrl: movie.posterUrl,
      watched: progress?.watched ?? false,
      progress: isInProgress(progress) ? progress!.fraction : null,
      onTap: () => openMovie(context, movie),
    );
  },
);

/// The Movies tab: categories, search, sort and filters, "Continue
/// watching" and a poster grid.
class MoviesScreen extends ConsumerWidget {
  const MoviesScreen({super.key});

  static void _open(BuildContext context, Movie movie) =>
      openMovie(context, movie);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(movieCatalogProvider);
    final filter = ref.watch(movieFilterProvider);
    final watch = ref.watch(watchProvider);
    final catalog = state.catalog;
    return VodBrowser<Movie>(
      title: 'Movies',
      what: 'movies',
      kind: ContentKind.movie,
      state: state,
      filter: filter,
      notifier: ref.read(movieFilterProvider.notifier),
      categoryOf: (item) => item.categoryId,
      itemRef: movieItemRef,
      onRefresh: () => refreshPlaylistPart(ref, PlaylistPart.movies),
      continueWatching: [
        if (catalog != null)
          for (final (id, progress) in continueMovieGroups(
            watch,
            ref.watch(movieVariantsProvider).groupOf,
          ))
            if (catalog.byId(id) case final movie?)
              (
                movie,
                PosterCard(
                  key: ValueKey('continue.${movie.streamId}'),
                  title: movie.name,
                  favourite: movieItemRef(movie),
                  subtitle: 'Resume at ${formatDuration(progress.position)}',
                  imageUrl: movie.posterUrl,
                  progress: progress.fraction,
                  actions: [
                    removeFromContinueAction(context, ref, movie: movie),
                  ],
                  onTap: () => _open(context, movie),
                ),
              ),
      ],
      itemBuilder: (context, movie) => moviePoster(context, movie),
    );
  }
}
