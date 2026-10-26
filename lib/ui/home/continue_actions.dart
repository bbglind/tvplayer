import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../favourites/favourite_menu.dart';
import '../vod/provider_title.dart';

/// How long the "Undo" of a removal stays offered.
const removeUndoDuration = Duration(seconds: 6);

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
        undo = () {
          if (previous != null) watch.restoreMovie(movie.streamId, previous);
        };
      } else {
        name = plainTitle(ref, series!.name);
        watch.removeSeriesFromContinue(series.seriesId);
        undo = () => watch.restoreSeries(series.seriesId);
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('continue.removed'),
            duration: removeUndoDuration,
            // With an action a snack bar stays until dismissed by default.
            persist: false,
            content: Text('Removed “$name” from Continue watching'),
            action: SnackBarAction(label: 'Undo', onPressed: undo),
          ),
        );
    },
  );
}
