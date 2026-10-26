import 'package:flutter/material.dart';
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
import 'other_sources.dart';
import 'poster.dart';
import 'provider_title.dart';

/// One movie: poster, facts, plot and cast from the metadata source, and
/// Play/Resume.
class MovieDetailsScreen extends ConsumerStatefulWidget {
  const MovieDetailsScreen({super.key, required this.movie});

  final Movie movie;

  @override
  ConsumerState<MovieDetailsScreen> createState() => _MovieDetailsState();
}

class _MovieDetailsState extends ConsumerState<MovieDetailsScreen> {
  late Future<MediaMetadata?> _details = _load();

  Future<MediaMetadata?> _load() =>
      ref.read(metadataSourceProvider)?.movie(widget.movie) ??
      Future.value(null);

  void _play({Duration? start}) =>
      openPlayback(context, ref, MoviePlayback(widget.movie, start: start));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder(
        future: _details,
        builder: (context, snapshot) => _buildBody(
          context,
          snapshot.data,
          loading: snapshot.connectionState != ConnectionState.done,
          error: snapshot.error,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MediaMetadata? meta, {
    required bool loading,
    required Object? error,
  }) {
    final movie = widget.movie;
    // Together with its other sources.
    final group = ref.watch(movieProgressProvider(movie.streamId));
    final progress = group?.progress;
    final watched = progress?.watched ?? false;
    final resume = resumePosition(progress);
    final sources = movieSources(ref, movie);
    final from = group == null || group.from == movie.streamId
        ? null
        : sources.labels.describe(group.from);
    final rating = meta?.rating ?? movie.rating;
    final tags = ref.watch(providerTagsProvider);
    final display = tags.display(movie.name);
    final facts = [
      if ((meta?.year ?? movie.year) case final year?) '$year',
      ?display.country,
      ?sources.labels.dateOf(movie.streamId),
      ?meta?.genre,
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}',
      if (meta?.duration case final d?) formatRuntime(d),
    ];
    return SingleChildScrollView(
      padding: AppSpacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMain(
            context,
            meta,
            loading: loading,
            error: error,
            progress: progress,
            watched: watched,
            resume: resume,
            from: from,
            facts: facts,
            display: display,
            tags: tags,
            lastPlayed: sources.lastPlayed == movie.streamId,
          ),
          const SizedBox(height: 36),
          OtherSourcesSection(children: moviePosters(context, sources)),
        ],
      ),
    );
  }

  Widget _buildMain(
    BuildContext context,
    MediaMetadata? meta, {
    required bool loading,
    required Object? error,
    required WatchProgress? progress,
    required bool watched,
    required Duration? resume,
    required String? from,
    required List<String> facts,
    required DisplayTitle display,
    required ProviderTags tags,
    required bool lastPlayed,
  }) {
    final theme = Theme.of(context);
    final movie = widget.movie;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 260,
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Poster(
                        url: meta?.posterUrl ?? movie.posterUrl,
                        decodeWidth: 520,
                      ),
                      if (isInProgress(progress) && progress!.fraction != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: WatchProgressBar(progress.fraction!),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: ProviderTitle(
                      movie.name,
                      key: const Key('movie.title'),
                      title: switch (meta?.title) {
                        final t? => tags.display(t).title,
                        null => null,
                      },
                      maxLines: 3,
                      large: true,
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                  if (watched) ...[
                    const SizedBox(width: 12),
                    const WatchedBadge(),
                  ],
                ],
              ),
              if (facts.isNotEmpty || lastPlayed) ...[
                const SizedBox(height: 6),
                FactsLine(
                  facts,
                  lastPlayed: lastPlayed,
                  key: const Key('movie.facts'),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (resume != null) ...[
                    FilledButton.icon(
                      key: const Key('movie.resume'),
                      autofocus: true,
                      onPressed: () => _play(start: resume),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(
                        'Resume from ${formatDuration(resume)}'
                        '${from == null ? '' : ' (from $from)'}',
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('movie.restart'),
                      onPressed: _play,
                      icon: const Icon(Icons.replay),
                      label: const Text('Play from start'),
                    ),
                  ] else
                    FilledButton.icon(
                      key: const Key('movie.play'),
                      autofocus: true,
                      onPressed: _play,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('movie.markWatched'),
                    onPressed: () => ref
                        .read(watchProvider.notifier)
                        .markMovie(movie, watched: !watched),
                    icon: Icon(watched ? Icons.remove_done : Icons.done_all),
                    label: Text(
                      watched ? 'Mark as unwatched' : 'Mark as watched',
                    ),
                  ),
                  FavouriteButton(
                    item: movieItemRef(movie),
                    name: movie.name,
                    labelled: true,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (loading)
                const LinearProgressIndicator()
              else if (error != null)
                Text(
                  'Details unavailable: ${describeProviderError(error)}',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (meta?.plot case final plot?) ...[
                Text(
                  plot,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (meta?.cast case final cast?) _Fact('Cast', cast),
              if (meta?.director case final director?)
                _Fact('Director', director),
              if (error != null)
                TextButton.icon(
                  onPressed: () => setState(() => _details = _load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled line such as "Cast: …".
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
