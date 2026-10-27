import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'poster.dart';

/// The picture at the top of a movie's or series' details in the phone
/// layout: the backdrop across the width (16:9, with the bottom fade and
/// [progress]) when there is one, else the [poster] centred, at most 180
/// wide.
class DetailsPicture extends StatelessWidget {
  const DetailsPicture({
    super.key = const Key('details.picture'),
    required this.backdropUrl,
    required this.poster,
    this.progress,
  });

  final String? backdropUrl;
  final Widget poster;

  /// How much of it was watched (0–1), shown on the backdrop.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final url = backdropUrl;
    if (url == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: poster,
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Poster(
              url: url,
              decodeWidth: 800,
              placeholder: Icons.movie_outlined,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.5, 1],
                  colors: [
                    AppColors.scrim.withValues(alpha: 0),
                    AppColors.scrim.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            if (progress case final p?)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: WatchProgressBar(p),
              ),
          ],
        ),
      ),
    );
  }
}
