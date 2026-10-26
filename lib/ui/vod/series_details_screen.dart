import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/errors.dart';
import '../../format.dart';
import '../../player/playback_request.dart';
import '../../state/providers.dart';
import '../../state/variants.dart';
import '../favourites/favourite_menu.dart';
import '../player/open_channel.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'other_sources.dart';
import 'poster.dart';
import 'provider_title.dart';

/// One series: details, a tab per season (specials last) with watched
/// progress, and the season's episodes.
class SeriesDetailsScreen extends ConsumerStatefulWidget {
  const SeriesDetailsScreen({super.key, required this.series});

  final Series series;

  @override
  ConsumerState<SeriesDetailsScreen> createState() => _SeriesDetailsState();
}

class _SeriesDetailsState extends ConsumerState<SeriesDetailsScreen> {
  late Future<SeriesInfo> _info;
  late Future<MediaMetadata?> _meta;

  /// The selected season; chosen from the watch history on first load.
  int? _season;
  SeriesInfo? _summarized;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final source = ref.read(vodSourceProvider);
    _info = source == null
        ? Future.error(StateError('No provider configured'))
        : source.seriesInfo(widget.series.seriesId);
    // Details are optional: the episodes show without them.
    _meta =
        (ref.read(metadataSourceProvider)?.series(widget.series) ??
                Future.value(null))
            .then<MediaMetadata?>((m) => m, onError: (Object _) => null);
  }

  /// How the episodes stand across the series' other sources.
  EpisodeGroupView get _view =>
      ref.watch(episodeViewProvider(widget.series.seriesId));

  void _play(SeriesInfo info, Episode episode) {
    final view = ref.read(episodeViewProvider(widget.series.seriesId));
    final start = resumePosition(view.progress(episode));
    openPlayback(context, ref, EpisodePlayback(info, episode, start: start));
  }

  void _mark(SeriesInfo info, Iterable<Episode> episodes, bool watched) => ref
      .read(watchProvider.notifier)
      .markEpisodes(info, episodes, watched: watched);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(
              message: describeProviderError(snapshot.error!),
              onRetry: () => setState(_load),
            );
          }
          final info = snapshot.data;
          if (info == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder(
            future: _meta,
            builder: (context, meta) => _buildLoaded(context, info, meta.data),
          );
        },
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    SeriesInfo info,
    MediaMetadata? meta,
  ) {
    final watch = ref.watch(watchProvider);
    final view = _view;
    final tabs = seasonTabs(info);
    if (!identical(info, _summarized)) {
      _summarized = info;
      // Keep the poster badge and "Continue watching" current, e.g. when
      // new episodes were added.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(watchProvider.notifier).refreshSeriesSummary(info);
        }
      });
    }
    if (_season == null || !tabs.any((t) => t.number == _season)) {
      _season = initialSeason(info, watch, group: view);
    }
    final season = _season;
    final episodes = season == null
        ? const <Episode>[]
        : info.episodesForSeason(season);
    return CustomScrollView(
      key: const Key('series.scroll'),
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context, info, meta, watch)),
        SliverToBoxAdapter(child: _buildSeasonBar(context, info, tabs, watch)),
        if (tabs.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No episodes'),
            ),
          ),
        SliverList.builder(
          itemCount: episodes.length,
          itemBuilder: (context, i) {
            final e = episodes[i];
            return _EpisodeTile(
              key: ValueKey('episode.${e.id}'),
              episode: e,
              title: episodeDisplayTitle(
                info.series,
                e,
                ref.watch(providerTagsProvider),
                title: meta?.episode(e)?.title,
              ),
              meta: meta?.episode(e),
              fallbackImage: meta?.posterUrl ?? widget.series.coverUrl,
              progress: view.progress(e),
              onPlay: () => _play(info, e),
              onMark: (watched) => _mark(info, [e], watched),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 36)),
        SliverToBoxAdapter(
          child: OtherSourcesSection(
            inset: 40,
            children: seriesPosters(
              context,
              ref,
              seriesSources(ref, widget.series),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    SeriesInfo info,
    MediaMetadata? meta,
    WatchData watch,
  ) {
    final theme = Theme.of(context);
    final series = widget.series;
    final rating = meta?.rating ?? series.rating;
    final tags = ref.watch(providerTagsProvider);
    final display = tags.display(series.name);
    final sources = seriesSources(ref, series);
    final view = _view;
    final facts = [
      if ((meta?.year ?? series.year) case final year?) '$year',
      ?display.country,
      ?sources.labels.dateOf(series.seriesId),
      ?(meta?.genre ?? series.genre),
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}',
    ];
    final next = upNext(info, watch, group: view) ?? _firstEpisode(info);
    final nextProgress = next == null ? null : view.progress(next);
    final resume = resumePosition(nextProgress);
    final from = switch (next == null || resume == null
        ? null
        : view.sourceOf(next)) {
      final id? => sources.labels.describe(id),
      null => null,
    };
    final lastPlayed = sources.lastPlayed == series.seriesId;
    return Padding(
      padding: AppSpacing.page.copyWith(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Poster(
                  url: meta?.posterUrl ?? series.coverUrl,
                  decodeWidth: 360,
                  placeholder: Icons.tv,
                ),
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProviderTitle(
                  series.name,
                  key: const Key('series.title'),
                  title: switch (meta?.title) {
                    final t? => tags.display(t).title,
                    null => null,
                  },
                  maxLines: 3,
                  large: true,
                  style: theme.textTheme.headlineMedium,
                ),
                if (facts.isNotEmpty || lastPlayed) ...[
                  const SizedBox(height: 6),
                  FactsLine(
                    facts,
                    lastPlayed: lastPlayed,
                    key: const Key('series.facts'),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (next != null)
                      FilledButton.icon(
                        key: const Key('series.playNext'),
                        autofocus: true,
                        onPressed: () => _play(info, next),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          '${resume != null ? 'Resume' : 'Play'} '
                          '${formatEpisodeCode(next.season, next.episodeNumber)}'
                          '${resume != null ? ' from ${formatDuration(resume)}' : ''}'
                          '${from != null ? ' (from $from)' : ''}',
                        ),
                      ),
                    FavouriteButton(
                      item: seriesItemRef(series),
                      name: series.name,
                      labelled: true,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if ((meta?.plot ?? series.plot) case final plot?)
                  Text(
                    plot,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                if ((meta?.cast ?? series.cast) case final cast?) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Cast: $cast',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Episode? _firstEpisode(SeriesInfo info) =>
      info.episodes.where((e) => e.season != 0).firstOrNull ??
      info.episodes.firstOrNull;

  Widget _buildSeasonBar(
    BuildContext context,
    SeriesInfo info,
    List<SeasonTab> tabs,
    WatchData watch,
  ) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    final selected = _season;
    final progress = selected == null
        ? null
        : seasonProgress(info, selected, watch, group: _view);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 8, 36, 16),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Room for the focus ring.
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  for (final tab in tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _seasonChip(info, tab, watch),
                    ),
                ],
              ),
            ),
          ),
          if (selected != null && progress != null)
            PopupMenuButton<bool>(
              key: const Key('season.menu'),
              tooltip: 'Season options',
              onSelected: (watched) =>
                  _mark(info, info.episodesForSeason(selected), watched),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: true,
                  enabled: !progress.complete,
                  child: const Text('Mark season as watched'),
                ),
                PopupMenuItem(
                  value: false,
                  enabled: progress.watched > 0,
                  child: const Text('Mark season as unwatched'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _seasonChip(SeriesInfo info, SeasonTab tab, WatchData watch) {
    final progress = seasonProgress(info, tab.number, watch, group: _view);
    final selected = tab.number == _season;
    return FocusRing(
      radius: AppRadius.pill,
      child: ChoiceChip(
        key: Key('season.${tab.number}'),
        // No padded tap target, so the ring hugs the chip.
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        selected: selected,
        avatar: progress.complete
            ? Icon(
                Icons.check_circle,
                key: const Key('season.complete'),
                color: selected ? AppColors.onAccent : AppColors.success,
              )
            : null,
        label: Text('${tab.name} · ${progress.label}'),
        onSelected: (_) => setState(() => _season = tab.number),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    super.key,
    required this.episode,
    required this.title,
    required this.meta,
    required this.fallbackImage,
    required this.progress,
    required this.onPlay,
    required this.onMark,
  });

  final Episode episode;

  /// The episode's own name (see [episodeDisplayTitle]).
  final String title;
  final EpisodeMetadata? meta;
  final String? fallbackImage;
  final WatchProgress? progress;
  final VoidCallback onPlay;
  final ValueChanged<bool> onMark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final watched = progress?.watched ?? false;
    final fraction = isInProgress(progress) ? progress!.fraction : null;
    final duration = meta?.duration ?? episode.duration;
    final plot = meta?.plot ?? episode.plot;
    return Opacity(
      // Watched episodes step back.
      opacity: watched ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 8),
        child: AppTile(
          onTap: onPlay,
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Poster(
                          url:
                              meta?.stillUrl ??
                              episode.coverUrl ??
                              fallbackImage,
                          placeholder: Icons.tv,
                        ),
                        if (fraction != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: WatchProgressBar(fraction),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: TruncatedText(
                            '${episode.episodeNumber}. $title',
                            key: const Key('episode.title'),
                            style: theme.textTheme.titleMedium,
                            tooltip: title == episode.title
                                ? null
                                : episode.title,
                          ),
                        ),
                        if (watched) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_circle,
                            key: const Key('episode.watched'),
                            size: 18,
                            color: AppColors.success,
                          ),
                        ],
                      ],
                    ),
                    if (duration != null)
                      Text(
                        formatRuntime(duration),
                        style: theme.textTheme.bodySmall,
                      ),
                    if (plot != null) ...[
                      const SizedBox(height: 4),
                      TruncatedText(
                        plot,
                        key: const Key('episode.plot'),
                        maxLines: 2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: 'Episode options',
                onSelected: onMark,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: !watched,
                    child: Text(
                      watched ? 'Mark as unwatched' : 'Mark as watched',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Could not load the episodes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
