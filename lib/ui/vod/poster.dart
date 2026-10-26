import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/poster_cache.dart';
import '../../state/providers.dart';
import '../favourites/favourite_menu.dart';
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
    this.alignment = Alignment.center,
    this.placeholder = Icons.movie_outlined,
    this.background = AppColors.card,
  });

  final String? url;
  final int decodeWidth;
  final BoxFit fit;

  /// Which part stays visible when [fit] crops the image.
  final Alignment alignment;
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
      alignment: alignment,
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
///
/// With a [favourite] item it gets a favourite star at the top left (shown
/// on hover or focus, or when it is a favourite) and a context menu.
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
    this.favourite,
    this.focusNode,
    this.actions = const [],
    this.imageAlignment = Alignment.center,
    this.decodeWidth = 300,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool watched;

  /// Watched fraction for a progress bar; null for none.
  final double? progress;
  final IconData placeholder;
  final ItemRef? favourite;
  final FocusNode? focusNode;

  /// More context menu entries (with a [favourite] only).
  final List<ItemMenuAction> actions;

  /// Which part of the image stays visible when it is cropped, e.g. the
  /// top of a poster in a 16:9 thumbnail.
  final Alignment imageAlignment;
  final int decodeWidth;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favourite = widget.favourite;
    final card = _buildCard(theme);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: favourite == null
          ? card
          // The star sits beside the context menu, not in it: menu
          // anchors nest.
          : Stack(
              children: [
                Positioned.fill(
                  child: ItemContextMenu(
                    item: favourite,
                    name: widget.title,
                    actions: widget.actions,
                    child: card,
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: FavouriteButton(
                    item: favourite,
                    name: widget.title,
                    revealed: _hovered || _focused,
                    backdrop: AppColors.scrim.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCard(ThemeData theme) {
    return InkWell(
      onTap: widget.onTap,
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
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
                        alignment: widget.imageAlignment,
                        decodeWidth: widget.decodeWidth,
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
            TruncatedText(
              widget.title,
              maxLines: 2,
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
