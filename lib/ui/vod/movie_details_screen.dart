import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/errors.dart';
import '../../format.dart';
import '../../player/playback_request.dart';
import '../../state/providers.dart';
import '../player/open_channel.dart';
import 'poster.dart';

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
    final movie = widget.movie;
    return Scaffold(
      appBar: AppBar(title: Text(movie.name)),
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
    final theme = Theme.of(context);
    final movie = widget.movie;
    final progress = ref.watch(watchProvider).movie(movie.streamId);
    final watched = progress?.watched ?? false;
    final resume = resumePosition(progress);
    final rating = meta?.rating ?? movie.rating;
    final facts = [
      if ((meta?.year ?? movie.year) case final year?) '$year',
      ?meta?.genre,
      if (rating != null && rating > 0) '★ ${rating.toStringAsFixed(1)}',
      if (meta?.duration case final d?) formatRuntime(d),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 260,
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Poster(
                      url: meta?.posterUrl ?? movie.posterUrl,
                      decodeWidth: 520,
                    ),
                  ),
                ),
                if (isInProgress(progress) && progress!.fraction != null)
                  WatchProgressBar(progress.fraction!),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        meta?.title ?? movie.name,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    if (watched) ...[
                      const SizedBox(width: 8),
                      const WatchedBadge(),
                    ],
                  ],
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    facts.join(' · '),
                    key: const Key('movie.facts'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (resume != null) ...[
                      FilledButton.icon(
                        key: const Key('movie.resume'),
                        autofocus: true,
                        onPressed: () => _play(start: resume),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('Resume from ${formatDuration(resume)}'),
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
                  ],
                ),
                const SizedBox(height: 16),
                if (loading)
                  const LinearProgressIndicator()
                else if (error != null)
                  Text(
                    'Details unavailable: ${describeProviderError(error)}',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                if (meta?.plot case final plot?) ...[
                  Text(plot, style: theme.textTheme.bodyLarge),
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
      ),
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
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
