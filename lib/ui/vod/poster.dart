import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/poster_cache.dart';
import '../../state/providers.dart';

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
  });

  final String? url;
  final int decodeWidth;
  final BoxFit fit;
  final IconData placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = this.url;
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(placeholder)),
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

/// A thin bar showing how much was watched.
class WatchProgressBar extends StatelessWidget {
  const WatchProgressBar(this.fraction, {super.key});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      key: const Key('poster.progress'),
      value: fraction,
      minHeight: 4,
      backgroundColor: Colors.black54,
    );
  }
}

/// A round check mark on watched items.
class WatchedBadge extends StatelessWidget {
  const WatchedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('poster.watched'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Icon(Icons.check, size: 16, color: scheme.onPrimary),
    );
  }
}

/// A grid or row item: poster with watched badge or progress bar, title
/// and an optional second line.
class PosterCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Poster(url: imageUrl, placeholder: placeholder),
                    if (watched)
                      const Positioned(top: 6, right: 6, child: WatchedBadge()),
                    if (progress case final p? when !watched)
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
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (subtitle case final s?)
              Text(
                s,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
