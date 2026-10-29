import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/errors.dart';
import '../../format.dart';
import '../../player/playback_request.dart';
import '../../state/downloads_controller.dart';
import '../../state/providers.dart';
import '../../state/tmdb.dart';
import '../../state/variants.dart';
import '../downloads/download_actions.dart';
import '../downloads/download_button.dart';
import '../favourites/favourite_menu.dart';
import '../player/open_channel.dart';
import '../shell/app_messages.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../theme/compact.dart';
import 'details_backdrop.dart';
import 'details_menu.dart';
import 'other_sources.dart';
import 'poster.dart';
import 'provider_title.dart';
import 'tmdb_sections.dart';

/// One series: details (from the provider, gaps filled from TMDB), a tab
/// per season (specials last) with watched progress, the season's
/// episodes, then Cast, Recommendations and Other sources.
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

  /// "Reset progress": forgets where [episode] was stopped, with Undo.
  void _resetProgress(SeriesInfo info, Episode episode) {
    final messenger = ScaffoldMessenger.of(context);
    final watch = ref.read(watchProvider.notifier);
    final previous = watch.resetEpisode(info, episode);
    final name =
        '${plainTitle(ref, info.series.name)} '
        '${formatEpisodeCode(episode.season, episode.episodeNumber)}';
    showAppMessage(
      messenger,
      'Reset the progress of “$name”',
      key: const Key('progress.reset'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => watch.restoreProgressOf(previous, info: info),
      ),
    );
  }

  void _mark(SeriesInfo info, Iterable<Episode> episodes, bool watched) => ref
      .read(watchProvider.notifier)
      .markEpisodes(info, episodes, watched: watched);

  void _download(SeriesInfo info, Episode episode) {
    final item = ref
        .read(downloadsProvider.notifier)
        .addEpisode(info, episode, ref.read(providerTagsProvider));
    if (item != null) showAddedToDownloads(context, ref, downloadName(item));
  }

  void _downloadSeason(SeriesInfo info, int season) {
    final count = ref
        .read(downloadsProvider.notifier)
        .addSeason(info, season, ref.read(providerTagsProvider));
    if (count == 0) return;
    showAddedToDownloads(
      context,
      ref,
      plainTitle(ref, info.series.name),
      episodes: count,
    );
  }

  void _episodeAction(SeriesInfo info, Episode e, EpisodeAction action) {
    switch (action) {
      case EpisodeAction.markWatched || EpisodeAction.markUnwatched:
        _mark(info, [e], action == EpisodeAction.markWatched);
      case EpisodeAction.download:
        _download(info, e);
      case EpisodeAction.cancelDownload || EpisodeAction.removeDownload:
        final item = ref.read(downloadsProvider).forWatchKey(episodeKey(e.id));
        if (item != null) unawaited(removeDownloadFlow(context, ref, item));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A backdrop reaches the top edge, behind the back arrow.
      extendBodyBehindAppBar: true,
      appBar: detailsAppBar(
        actions: [DetailsMenu(item: seriesTmdbItem(widget.series))],
      ),
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
    final downloads = ref.watch(downloadsProvider);
    final series = widget.series;
    final tmdb = ref.watch(tmdbItemTitleProvider(seriesTmdbItem(series))).value;
    final shown = DetailsView.combine(
      provider: meta ?? _listMetadata(series),
      listPoster: series.coverUrl,
      listBackdrops: series.backdropUrls,
      listYear: series.year,
      listRating: series.rating,
      tmdb: tmdb,
      preferTmdbPosters: ref.watch(tmdbPreferPostersProvider),
      compact: isCompact(context),
    );
    // TMDB's episodes of the season shown: descriptions and stills where
    // the provider has none.
    final tmdbSeason = tmdb == null || season == null
        ? null
        : ref
              .watch(
                tmdbSeasonProvider((
                  tvId: tmdb.key.id,
                  number: season,
                  ongoing: tmdb.ongoing,
                )),
              )
              .value;
    return CustomScrollView(
      key: const Key('series.scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _buildHeader(context, info, meta, shown, watch),
        ),
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
              meta: withTmdbEpisode(
                meta?.episode(e),
                tmdbSeason?.episode(e.episodeNumber),
              ),
              fallbackImage: shown.posterUrls.primary,
              progress: view.progress(e),
              download: downloads.forWatchKey(episodeKey(e.id)),
              onPlay: () => _play(info, e),
              onAction: (action) => _episodeAction(info, e, action),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 36)),
        if (shown.people.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: CastRow(people: shown.people),
            ),
          ),
        SliverToBoxAdapter(
          child: RecommendationsRow(keys: shown.recommendations),
        ),
        SliverToBoxAdapter(
          child: OtherSourcesSection(
            inset: pageSide(context),
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

  /// The list entry's details, while the provider's details are missing.
  static MediaMetadata _listMetadata(Series s) => MediaMetadata(
    plot: s.plot,
    genre: s.genre,
    cast: s.cast,
    director: s.director,
    rating: s.rating,
    year: s.year,
    posterUrl: s.coverUrl,
    backdropUrls: s.backdropUrls,
  );

  Widget _buildHeader(
    BuildContext context,
    SeriesInfo info,
    MediaMetadata? meta,
    DetailsView shown,
    WatchData watch,
  ) {
    final theme = Theme.of(context);
    final series = widget.series;
    final rating = shown.rating;
    final seasons = seasonTabs(info).where((t) => t.number != 0).length;
    final tags = ref.watch(providerTagsProvider);
    final display = tags.display(series.name);
    final sources = seriesSources(ref, series);
    final view = _view;
    final facts = [
      if (shown.year case final year?) '$year',
      ?display.country,
      ?sources.labels.dateOf(series.seriesId),
      if (seasons > 0) seasons == 1 ? '1 season' : '$seasons seasons',
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}',
      ?shown.genre,
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
    final poster = AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Poster(
          url: shown.posterUrls.primary,
          fallbackUrl: shown.posterUrls.fallback,
          decodeWidth: 360,
          placeholder: Icons.tv,
        ),
      ),
    );
    final details = Column(
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
              _withResumeMenu(
                resume == null ? null : () => _resetProgress(info, next),
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
              ),
            FavouriteButton(
              item: seriesItemRef(series),
              name: series.name,
              labelled: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (shown.plot case final plot?)
          Text(
            plot,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        // The Cast row shows TMDB's cast with photos instead.
        if (shown.cast case final cast? when shown.people.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Cast: $cast',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
    return DetailsHeader(
      backdropUrl: shown.backdropUrl,
      poster: poster,
      details: details,
      posterWidth: 180,
    );
  }

  /// [button] with a "Reset progress" context menu while it resumes
  /// ([reset] not null). Always wrapped, so the button keeps its focus
  /// when it turns into "Play".
  static Widget _withResumeMenu(VoidCallback? reset, Widget button) =>
      ContextMenuRegion(
        actions: [
          if (reset != null)
            ItemMenuAction(
              key: const Key('resume.reset'),
              label: 'Reset progress',
              icon: Icons.restart_alt,
              onPressed: reset,
            ),
        ],
        child: button,
      );

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
      padding: isCompact(context)
          ? const EdgeInsets.fromLTRB(compactPagePadding - 6, 0, 4, 8)
          : const EdgeInsets.fromLTRB(36, 8, 36, 16),
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
            PopupMenuButton<_SeasonAction>(
              key: const Key('season.menu'),
              tooltip: 'Season options',
              onSelected: (action) => switch (action) {
                _SeasonAction.markWatched ||
                _SeasonAction.markUnwatched => _mark(
                  info,
                  info.episodesForSeason(selected),
                  action == _SeasonAction.markWatched,
                ),
                _SeasonAction.download => _downloadSeason(info, selected),
              },
              itemBuilder: (context) {
                final downloads = ref.read(downloadsProvider);
                final missing = info
                    .episodesForSeason(selected)
                    .any(
                      (e) => downloads.forWatchKey(episodeKey(e.id)) == null,
                    );
                return [
                  PopupMenuItem(
                    value: _SeasonAction.markWatched,
                    enabled: !progress.complete,
                    child: const Text('Mark season as watched'),
                  ),
                  PopupMenuItem(
                    value: _SeasonAction.markUnwatched,
                    enabled:
                        progress.watched > 0 ||
                        info
                            .episodesForSeason(selected)
                            .any((e) => isInProgress(_view.progress(e))),
                    child: const Text('Mark season as unwatched'),
                  ),
                  PopupMenuItem(
                    key: const Key('season.download'),
                    value: _SeasonAction.download,
                    enabled: missing,
                    child: const Text('Download season'),
                  ),
                ];
              },
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

/// The entries of the season menu.
enum _SeasonAction { markWatched, markUnwatched, download }

/// The entries of an episode's menu.
enum EpisodeAction {
  markWatched,
  markUnwatched,
  download,
  cancelDownload,
  removeDownload,
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    super.key,
    required this.episode,
    required this.title,
    required this.meta,
    required this.fallbackImage,
    required this.progress,
    required this.download,
    required this.onPlay,
    required this.onAction,
  });

  final Episode episode;

  /// The episode's own name (see [episodeDisplayTitle]).
  final String title;
  final EpisodeMetadata? meta;
  final String? fallbackImage;
  final WatchProgress? progress;

  /// Its entry in Downloads, if any.
  final DownloadItem? download;
  final VoidCallback onPlay;
  final ValueChanged<EpisodeAction> onAction;

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
        padding: EdgeInsets.fromLTRB(
          pageSide(context),
          0,
          pageSide(context),
          8,
        ),
        // The same menu as the ⋮ button: right click, long press (touch),
        // or the Menu key / Shift+F10 on the focused row.
        child: Builder(
          builder: (context) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
                  _openMenu(context, null, watched),
              const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
                  _openMenu(context, null, watched),
            },
            child: GestureDetector(
              key: const Key('episode.row'),
              onSecondaryTapUp: (d) =>
                  _openMenu(context, d.globalPosition, watched),
              onLongPressStart: (d) =>
                  _openMenu(context, d.globalPosition, watched),
              child: _buildTile(
                context,
                theme,
                watched: watched,
                fraction: fraction,
                duration: duration,
                plot: plot,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Mark as watched" and/or "Mark as unwatched" (both while it is in
  /// progress: unwatched starts it from the beginning again), then
  /// "Download", "Cancel download" or "Remove download".
  List<PopupMenuEntry<EpisodeAction>> _menuItems(bool watched) {
    final download = this.download;
    final started = isInProgress(progress);
    return [
      if (!watched)
        const PopupMenuItem(
          key: Key('episode.markWatched'),
          value: EpisodeAction.markWatched,
          child: Text('Mark as watched'),
        ),
      if (watched || started)
        const PopupMenuItem(
          key: Key('episode.markUnwatched'),
          value: EpisodeAction.markUnwatched,
          child: Text('Mark as unwatched'),
        ),
      if (download == null)
        const PopupMenuItem(
          key: Key('episode.download'),
          value: EpisodeAction.download,
          child: Text('Download'),
        )
      else if (download.isDone)
        const PopupMenuItem(
          key: Key('episode.removeDownload'),
          value: EpisodeAction.removeDownload,
          child: Text('Remove download'),
        )
      else
        const PopupMenuItem(
          key: Key('episode.cancelDownload'),
          value: EpisodeAction.cancelDownload,
          child: Text('Cancel download'),
        ),
    ];
  }

  /// Opens the episode menu at [position] (global), or at the row's top
  /// right when opened from the keyboard.
  Future<void> _openMenu(
    BuildContext context,
    Offset? position,
    bool watched,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final row = context.findRenderObject()! as RenderBox;
    final at = position ?? row.localToGlobal(row.size.topRight(Offset.zero));
    final local = overlay.globalToLocal(at);
    final value = await showMenu<EpisodeAction>(
      context: context,
      position: RelativeRect.fromRect(
        local & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: _menuItems(watched),
    );
    if (value != null) onAction(value);
  }

  Widget _buildTile(
    BuildContext context,
    ThemeData theme, {
    required bool watched,
    required double? fraction,
    required Duration? duration,
    required String? plot,
  }) => AppTile(
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
                    url: meta?.stillUrl ?? episode.coverUrl ?? fallbackImage,
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
                      tooltip: title == episode.title ? null : episode.title,
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
                  if (download case final d?) ...[
                    const SizedBox(width: 8),
                    if (d.isDone)
                      const DownloadedBadge(size: 18)
                    else
                      Tooltip(
                        message: downloadButtonState(d).$1,
                        child: Icon(
                          downloadButtonState(d).$2,
                          key: const Key('episode.downloading'),
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ],
              ),
              if (duration != null)
                Text(formatRuntime(duration), style: theme.textTheme.bodySmall),
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
        PopupMenuButton<EpisodeAction>(
          key: const Key('episode.menu'),
          tooltip: 'Episode options',
          onSelected: onAction,
          itemBuilder: (context) => _menuItems(watched),
        ),
      ],
    ),
  );
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
