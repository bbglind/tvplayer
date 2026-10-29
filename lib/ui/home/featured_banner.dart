import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/home.dart';
import '../../state/tmdb.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/compact.dart';
import '../theme/widgets.dart';
import '../vod/movies_screen.dart';
import '../vod/poster.dart';
import '../vod/provider_title.dart';
import '../vod/series_screen.dart';
import 'home_playback.dart';
import 'home_row.dart';

/// "Featured": a large banner showing one of [picks] at a time, with its
/// backdrop (or poster), title, facts (after a NEW or TRENDING label when
/// trending items are mixed in), plot, Play and More info, and page dots. It moves on every [interval] unless hovered or focused; the dots
/// and the Left/Right keys page by hand.
class FeaturedBanner extends ConsumerStatefulWidget {
  const FeaturedBanner({super.key, required this.picks});

  final List<FeaturedPick> picks;

  static const interval = Duration(seconds: 8);

  /// Whether [picks] mix new and trending items, so each shows its label.
  static bool labelled(List<FeaturedPick> picks) =>
      picks.any((p) => p.source == FeaturedSource.trending);

  /// Banner height for [width] at the current text scale: wide windows get
  /// a wider-than-tall banner, and the title, facts, buttons and dots
  /// always fit. The label sits in the facts line, so it needs no room.
  /// The plot's two lines leave room for a title on two.
  static double height(BuildContext context, double width) {
    final text = Theme.of(context).textTheme;
    final compact = isCompact(context);
    // Buttons: 12 px padding above and below the label, at least 44.
    final button = math.max(44.0, 24 + lineHeight(context, text.labelLarge));
    final buttonRows = _buttonRows(
      context,
      compact ? width - 2 * _paddingOf(context) : width - 80,
    );
    final content =
        2 * _paddingOf(context) +
        lineHeight(context, _titleStyle(context)) +
        6 +
        lineHeight(context, text.bodyMedium) +
        10 +
        2 * lineHeight(context, text.bodyMedium) +
        _gap +
        buttonRows * button +
        (buttonRows - 1) * _buttonGap +
        _gap +
        _dotSize +
        // Rounding of line metrics.
        8;
    // On a phone just what it shows; the picture fills the rest.
    if (compact) return math.max(content, width * 0.75).ceilToDouble();
    return math.max(content, math.min(width * 0.4, 460.0)).ceilToDouble();
  }

  static const _buttonGap = 10.0;

  /// Rows Play and More info take in [textWidth]: two when they don't fit
  /// side by side (large text on a phone).
  static int _buttonRows(BuildContext context, double textWidth) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    double width(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      // Padding 20 + 20, icon 18 and the gap to the label 8.
      return w + 66;
    }

    return width('Play') + _buttonGap + width('More info') > textWidth ? 2 : 1;
  }

  static const _padding = 28.0;

  /// The padding around the text: smaller in the phone layout.
  static double _paddingOf(BuildContext context) =>
      isCompact(context) ? compactPagePadding : _padding;

  /// The hero title, smaller in the phone layout.
  static TextStyle? _titleStyle(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return isCompact(context)
        ? text.headlineMedium?.copyWith(fontSize: 26)
        : text.displayMedium;
  }

  static const _gap = 16.0;
  static const _dotSize = 28.0;

  @override
  ConsumerState<FeaturedBanner> createState() => _FeaturedBannerState();
}

class _FeaturedBannerState extends ConsumerState<FeaturedBanner> {
  Timer? _timer;
  int _index = 0;
  bool _hovered = false;
  bool _focused = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(FeaturedBanner.interval, (_) {
      if (!_hovered && !_focused) _go(1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _count => widget.picks.length;

  void _go(int by) {
    if (_count < 2) return;
    setState(() => _index = (_index + by) % _count);
  }

  void _show(int index) => setState(() => _index = index);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _play(VodPick pick) {
    switch (pick) {
      case MoviePick(:final movie):
        playMovie(context, ref, movie);
      case SeriesPick(:final series):
        playSeries(
          context,
          ref,
          series,
          onLoading: (v) {
            if (mounted) setState(() => _loading = v);
          },
        );
    }
  }

  void _details(VodPick pick) => switch (pick) {
    MoviePick(:final movie) => openMovie(context, movie),
    SeriesPick(:final series) => openSeries(context, series),
  };

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final index = _index.clamp(0, _count - 1);
    final featured = widget.picks[index];
    final pick = featured.pick;
    final labelled = FeaturedBanner.labelled(widget.picks);
    final details = ref.watch(featuredDetailsProvider(pick)).value;
    final view = _FeaturedView.of(
      pick,
      details,
      tmdbBackdrop: switch (pick) {
        MoviePick(:final movie) => movieBackdropUrl(ref, movie, large: true),
        SeriesPick(:final series) => seriesBackdropUrl(
          ref,
          series,
          large: true,
        ),
      },
      posters: switch (pick) {
        MoviePick(:final movie) => moviePosterUrls(
          ref,
          movie,
          providerPoster: details?.posterUrl,
          size: TmdbImageSize.w500,
        ),
        SeriesPick(:final series) => seriesPosterUrls(
          ref,
          series,
          providerPoster: details?.posterUrl,
          size: TmdbImageSize.w500,
        ),
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = FeaturedBanner.height(context, constraints.maxWidth);
        final pad = FeaturedBanner._paddingOf(context);
        final compact = isCompact(context);
        // On a phone the poster fills the banner like a backdrop.
        final posterWidth = view.backdrop == null && !compact
            ? (height - 2 * pad) * 2 / 3
            : 0.0;
        final textLeft = compact
            ? pad
            : view.backdrop == null
            ? pad + posterWidth + 32
            : 40.0;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (f) => setState(() => _focused = f),
            onKeyEvent: _onKey,
            child: SizedBox(
              key: const Key('home.featured'),
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.large),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: _Background(
                        key: ValueKey(pick),
                        view: view,
                        posterWidth: posterWidth,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        textLeft,
                        pad,
                        compact ? pad : 40,
                        pad,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                layoutBuilder: (current, previous) => Stack(
                                  alignment: Alignment.bottomLeft,
                                  children: [...previous, ?current],
                                ),
                                child: _Info(
                                  key: ValueKey(featured),
                                  view: view,
                                  source: labelled ? featured.source : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: FeaturedBanner._gap),
                          Wrap(
                            spacing: FeaturedBanner._buttonGap,
                            runSpacing: FeaturedBanner._buttonGap,
                            children: [
                              FilledButton.icon(
                                key: const Key('home.featured.play'),
                                onPressed: _loading ? null : () => _play(pick),
                                icon: _loading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.play_arrow),
                                label: const Text('Play'),
                              ),
                              OutlinedButton.icon(
                                key: const Key('home.featured.info'),
                                onPressed: () => _details(pick),
                                icon: const Icon(Icons.info_outline),
                                label: const Text('More info'),
                              ),
                            ],
                          ),
                          if (_count > 1) ...[
                            const SizedBox(height: FeaturedBanner._gap),
                            _Dots(
                              count: _count,
                              selected: index,
                              onSelect: _show,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What the banner shows of an item: catalogue data, completed by the
/// details when they have arrived.
final class _FeaturedView {
  const _FeaturedView({
    required this.title,
    required this.facts,
    required this.plot,
    required this.backdrop,
    required this.poster,
    required this.placeholder,
  });

  /// [tmdbBackdrop] comes before the provider's backdrop; the poster is
  /// the first of [posters] (see [moviePosterUrls]).
  factory _FeaturedView.of(
    VodPick pick,
    MediaMetadata? details, {
    String? tmdbBackdrop,
    List<String> posters = const [],
  }) {
    String? rating(double? r) =>
        r != null && r > 0 ? '★ ${r.toStringAsFixed(1)}' : null;
    switch (pick) {
      case MoviePick(:final movie):
        return _FeaturedView(
          title: movie.name,
          facts: [
            if ((details?.year ?? movie.year) case final y?) '$y',
            ?(details?.genre ?? movie.genre),
            if ((details?.duration ?? movie.duration) case final d?)
              formatRuntime(d),
            ?rating(details?.rating ?? movie.rating),
          ],
          plot: details?.plot ?? movie.plot,
          backdrop:
              tmdbBackdrop ??
              details?.backdropUrls.firstOrNull ??
              movie.backdropUrls.firstOrNull,
          poster: posters.firstOrNull,
          placeholder: Icons.movie_outlined,
        );
      case SeriesPick(:final series):
        final seasons = details == null
            ? 0
            : {
                for (final (season, _) in details.episodes.keys)
                  if (season != 0) season,
              }.length;
        return _FeaturedView(
          title: series.name,
          facts: [
            if ((details?.year ?? series.year) case final y?) '$y',
            ?(details?.genre ?? series.genre),
            if (seasons > 0) seasons == 1 ? '1 season' : '$seasons seasons',
            ?rating(details?.rating ?? series.rating),
          ],
          plot: details?.plot ?? series.plot,
          backdrop:
              tmdbBackdrop ??
              details?.backdropUrls.firstOrNull ??
              series.backdropUrls.firstOrNull,
          poster: posters.firstOrNull,
          placeholder: Icons.tv,
        );
    }
  }

  final String title;
  final List<String> facts;
  final String? plot;
  final String? backdrop;
  final String? poster;
  final IconData placeholder;
}

/// The backdrop with the dark bottom fade, or without one the poster at
/// the left on a `card` background.
class _Background extends StatelessWidget {
  const _Background({super.key, required this.view, required this.posterWidth});

  final _FeaturedView view;
  final double posterWidth;

  @override
  Widget build(BuildContext context) {
    // Without a backdrop, a phone shows the poster in its place.
    final backdrop = view.backdrop ?? (posterWidth == 0 ? view.poster : null);
    if (backdrop == null) {
      return ColoredBox(
        color: AppColors.card,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(FeaturedBanner._padding),
            child: SizedBox(
              width: posterWidth,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Poster(
                    url: view.poster,
                    decodeWidth: 480,
                    placeholder: view.placeholder,
                    background: AppColors.hover,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Poster(url: backdrop, decodeWidth: 1600, placeholder: view.placeholder),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.15, 0.55, 1],
              colors: [
                AppColors.scrim.withValues(alpha: 0),
                AppColors.scrim.withValues(alpha: 0.6),
                AppColors.scrim.withValues(alpha: 0.94),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Title, the label and facts, and plot.
class _Info extends StatelessWidget {
  const _Info({super.key, required this.view, this.source});

  final _FeaturedView view;

  /// Why the item is featured; null shows no label.
  final FeaturedSource? source;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProviderTitle(
          view.title,
          key: const Key('home.featured.title'),
          maxLines: 2,
          large: true,
          style: FeaturedBanner._titleStyle(context),
        ),
        if (view.facts.isNotEmpty || source != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (source case final source?) ...[
                _SourceLabel(source),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  view.facts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (view.plot case final plot? when plot.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Flexible(
            child: Text(
              plot.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

/// "NEW" or "TRENDING" at the start of the facts line: a badge like
/// REPLAY (`hover` background, `textPrimary`), trending with an arrow. No
/// taller than the facts text, so the banner needs no extra room.
class _SourceLabel extends StatelessWidget {
  const _SourceLabel(this.source);

  final FeaturedSource source;

  static const _size = 11.0;
  static const _iconSize = 14.0;
  static const _style = TextStyle(
    color: AppColors.textPrimary,
    fontSize: _size,
    fontWeight: FontWeight.w700,
    letterSpacing: _size * 0.08,
    height: 1.25,
  );

  @override
  Widget build(BuildContext context) {
    final trending = source == FeaturedSource.trending;
    return Container(
      key: Key('home.featured.label.${source.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trending) ...[
            const Icon(
              Icons.trending_up,
              size: _iconSize,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 4),
          ],
          Text(trending ? 'TRENDING' : 'NEW', maxLines: 1, style: _style),
        ],
      ),
    );
  }
}

/// Page dots: the selected one is a wider accent pill.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.selected,
    required this.onSelect,
  });

  final int count;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == selected,
            label: 'Featured item ${i + 1} of $count',
            child: FocusRing(
              radius: AppRadius.pill,
              inset: true,
              child: InkWell(
                key: Key('home.featured.dot.$i'),
                customBorder: const StadiumBorder(),
                onTap: () => onSelect(i),
                child: SizedBox(
                  width: FeaturedBanner._dotSize,
                  height: FeaturedBanner._dotSize,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == selected ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == selected
                            ? AppColors.accent
                            : AppColors.textDisabled,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
