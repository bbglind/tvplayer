import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../favourites/favourite_menu.dart';
import '../vod/movies_screen.dart';
import '../vod/provider_title.dart';
import '../vod/series_screen.dart';
import '../shell/app_messages.dart';

/// "Go to movie": opens the details page of [movie].
ItemMenuAction goToMovieAction(BuildContext context, Movie movie) =>
    ItemMenuAction(
      key: const Key('context.goTo'),
      label: 'Go to movie',
      icon: Icons.movie_outlined,
      onPressed: () => openMovie(context, movie),
    );

/// "Go to series": opens the details page of [series] on [season], the
/// season of the episode it continues with.
ItemMenuAction goToSeriesAction(
  BuildContext context,
  Series series, {
  int? season,
}) => ItemMenuAction(
  key: const Key('context.goTo'),
  label: 'Go to series',
  icon: Icons.video_library_outlined,
  onPressed: () => openSeries(context, series, season: season),
);

/// "Remove from Continue watching" for [movie] or [series]: clears a
/// movie's resume position, or takes a series out until it is watched
/// again, then offers "Undo" in a snack bar.
ItemMenuAction removeFromContinueAction(
  BuildContext context,
  WidgetRef ref, {
  Movie? movie,
  Series? series,
}) {
  assert((movie == null) != (series == null));
  return ItemMenuAction(
    key: const Key('context.removeContinue'),
    label: 'Remove from Continue watching',
    icon: Icons.remove_circle_outline,
    onPressed: () {
      final messenger = ScaffoldMessenger.of(context);
      final watch = ref.read(watchProvider.notifier);
      final String name;
      final VoidCallback undo;
      if (movie != null) {
        name = plainTitle(ref, movie.name);
        final previous = watch.removeMovieFromContinue(movie.streamId);
        undo = () => watch.restoreMovies(previous);
      } else {
        name = plainTitle(ref, series!.name);
        watch.removeSeriesFromContinue(series.seriesId);
        undo = () => watch.restoreSeries(series.seriesId);
      }
      showAppMessage(
        messenger,
        'Removed “$name” from Continue watching',
        key: const Key('continue.removed'),
        action: SnackBarAction(label: 'Undo', onPressed: undo),
      );
    },
  );
}
