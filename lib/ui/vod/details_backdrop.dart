import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/compact.dart';
import 'poster.dart';

/// The app bar of a details page. The page extends behind it so a
/// backdrop reaches the top edge; once the page is scrolled under it, it
/// takes the page background so the back arrow stays readable.
PreferredSizeWidget detailsAppBar({List<Widget> actions = const []}) => AppBar(
  backgroundColor: WidgetStateColor.resolveWith(
    (states) => states.contains(WidgetState.scrolledUnder)
        ? AppColors.background
        : Colors.transparent,
  ),
  surfaceTintColor: Colors.transparent,
  actions: actions,
);

/// The top of a movie's or series' details page.
///
/// With a [backdropUrl] the image lies behind the top of the page and fades
/// into the page background: on the desktop across the width (16:9, at
/// most 60 % of the window height) with the [poster] and [details] on its
/// lower part, readable thanks to a fade from the left and one from the
/// bottom; on a phone edge to edge above the details.
///
/// Without one: the poster beside the details (desktop), or centred above
/// them (phone), as before backdrops.
class DetailsHeader extends StatelessWidget {
  const DetailsHeader({
    super.key,
    required this.backdropUrl,
    required this.poster,
    required this.details,
    this.progress,
    this.posterWidth = 260,
  });

  final String? backdropUrl;
  final Widget poster;
  final Widget details;

  /// How much was watched (0–1), shown on the phone's backdrop (the poster
  /// isn't shown there).
  final double? progress;

  /// Width of the poster on the desktop.
  final double posterWidth;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final padding = pagePadding(context);
    // Below the transparent app bar.
    final top = MediaQuery.paddingOf(context).top;
    final url = backdropUrl;
    if (url == null) {
      return Padding(
        padding: padding.copyWith(top: top + padding.top, bottom: 24),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ConstrainedBox(
                      key: const Key('details.picture'),
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: poster,
                    ),
                  ),
                  const SizedBox(height: 16),
                  details,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: posterWidth, child: poster),
                  const SizedBox(width: 32),
                  Expanded(child: details),
                ],
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (compact) {
          final height = width * 9 / 16;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: height,
                child: DetailsBackdrop(
                  url: url,
                  decodeWidth: 800,
                  progress: progress,
                  progressInset: padding.left,
                ),
              ),
              Padding(
                padding: padding.copyWith(top: 4, bottom: 24),
                child: details,
              ),
            ],
          );
        }
        final height = math.min(
          width * 9 / 16,
          MediaQuery.sizeOf(context).height * 0.6,
        );
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: height,
              child: DetailsBackdrop(
                url: url,
                decodeWidth: 1600,
                fromLeft: true,
              ),
            ),
            Padding(
              padding: padding.copyWith(
                top: math.max(top + padding.top, height * 0.4),
                bottom: 24,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: posterWidth, child: poster),
                  const SizedBox(width: 32),
                  Expanded(child: details),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A backdrop fading into the page background at the bottom (and with
/// [fromLeft], at the left, behind the text), with a light fade at the top
/// for the app bar.
class DetailsBackdrop extends StatelessWidget {
  const DetailsBackdrop({
    super.key = const Key('details.backdrop'),
    required this.url,
    required this.decodeWidth,
    this.fromLeft = false,
    this.progress,
    this.progressInset = 0,
  });

  final String url;
  final int decodeWidth;
  final bool fromLeft;
  final double? progress;
  final double progressInset;

  @override
  Widget build(BuildContext context) {
    const page = AppColors.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        Poster(
          url: url,
          decodeWidth: decodeWidth,
          alignment: Alignment.topCenter,
          background: page,
        ),
        // The app bar's arrow and menu stay readable on bright images.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.25],
              colors: [
                AppColors.scrim.withValues(alpha: 0.55),
                AppColors.scrim.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        if (fromLeft)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0, 0.55],
                colors: [
                  page.withValues(alpha: 0.85),
                  page.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.55, 1],
              colors: [page.withValues(alpha: 0), page],
            ),
          ),
        ),
        if (progress case final p?)
          Positioned(
            left: progressInset,
            right: progressInset,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: WatchProgressBar(p),
            ),
          ),
      ],
    );
  }
}
