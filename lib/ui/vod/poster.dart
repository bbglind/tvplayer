import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/poster_cache.dart';
import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

/// An image loaded through a [PosterLoader] (the disk cache).
///
/// [toString] hides the URL, since Flutter puts it in image error reports.
@immutable
class PosterImage extends ImageProvider<PosterImage> {
  const PosterImage(this.url, this.loader);

  final String url;
  final PosterLoader loader;

  @override
  Future<PosterImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    PosterImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await loader.load(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is PosterImage &&
      other.url == url &&
      identical(other.loader, loader);

  @override
  int get hashCode => Object.hash(url, loader);

  @override
  String toString() => 'PosterImage(<redacted>)';
}

/// A poster, cover, still or logo from [url], decoded at [decodeWidth]
/// pixels wide to save memory; [placeholder] while loading or on errors.
class Poster extends ConsumerWidget {
  const Poster({
    super.key,
    required this.url,
    this.decodeWidth = 300,
    this.fit = BoxFit.cover,
    this.placeholder = Icons.movie_outlined,
    this.background = AppColors.card,
  });

  final String? url;
  final int decodeWidth;
  final BoxFit fit;
  final IconData placeholder;

  /// Behind the placeholder icon.
  final Color background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = this.url;
    final fallback = ColoredBox(
      color: background,
      child: Center(child: Icon(placeholder, color: AppColors.textMuted)),
    );
    if (url == null || url.isEmpty) return fallback;
    return Image(
      image: ResizeImage(
        PosterImage(url, ref.watch(posterLoaderProvider)),
        width: decodeWidth,
      ),
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) =>
          frame == null && !sync ? fallback : child,
      // Also keeps load failures out of the log, which could otherwise
      // show provider details.
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// A thin bar showing how much was watched, for the bottom edge of a
/// thumbnail: accent over a dark translucent track.
class WatchProgressBar extends StatelessWidget {
  const WatchProgressBar(this.fraction, {super.key});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      key: const Key('poster.progress'),
      value: fraction,
      minHeight: 4,
      color: AppColors.accent,
      backgroundColor: AppColors.scrim.withValues(alpha: 0.6),
      borderRadius: BorderRadius.zero,
    );
  }
}

/// A round check mark on watched items.
class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('poster.watched'),
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: AppColors.success,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check, size: size, color: AppColors.onAccent),
    );
  }
}

/// A grid or row item: poster with watched badge or progress bar, title
/// and an optional second line. The focus ring goes around the poster.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.subtitle,
    this.watched = false,
    this.progress,
    this.placeholder = Icons.movie_outlined,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool watched;

  /// Watched fraction for a progress bar; null for none.
  final double? progress;
  final IconData placeholder;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _focused = f),
      onHover: (h) => setState(() => _hovered = h),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: FocusRing(
                visible: _focused,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Poster(
                        url: widget.imageUrl,
                        placeholder: widget.placeholder,
                      ),
                      if (_hovered)
                        ColoredBox(
                          color: AppColors.textPrimary.withValues(alpha: 0.07),
                        ),
                      if (widget.watched)
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: WatchedBadge(size: 14),
                        ),
                      if (widget.progress case final p? when !widget.watched)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: WatchProgressBar(p),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            if (widget.subtitle case final s?)
              Text(
                s,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}
