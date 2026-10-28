import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/tmdb.dart';
import '../theme/app_colors.dart';
import '../theme/compact.dart';
import 'other_sources.dart';
import 'poster.dart';
import 'tmdb_sections.dart';

/// A person from a Cast row: photo, name and biography, then the movies
/// and series of the catalogue they acted in.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({
    super.key,
    required this.personId,
    required this.name,
    this.profilePath,
  });

  final int personId;

  /// Shown while the details load.
  final String name;
  final String? profilePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(tmdbPersonProvider(personId));
    final data = person.value;
    final theme = Theme.of(context);
    final compact = isCompact(context);
    final photoSize = compact ? 120.0 : 160.0;
    final photo = ClipOval(
      child: SizedBox.square(
        dimension: photoSize,
        child: Poster(
          key: const Key('person.photo'),
          url: tmdbImageUrlOrNull(
            data?.profilePath ?? profilePath,
            TmdbImageSize.w342,
          ),
          decodeWidth: 340,
          placeholder: Icons.person_outline,
        ),
      ),
    );
    final about = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          data?.name ?? name,
          key: const Key('person.name'),
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        if (person.isLoading)
          const LinearProgressIndicator()
        else if (data == null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  "Couldn't load this person's details.",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => ref.invalidate(tmdbPersonProvider(personId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          )
        else if (data.biography case final bio?)
          _Biography(bio),
      ],
    );
    final side = pageSide(context);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(side, 8, side, 32),
            child: compact
                ? Column(children: [photo, const SizedBox(height: 16), about])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      photo,
                      const SizedBox(width: 32),
                      Expanded(child: about),
                    ],
                  ),
          ),
          if (data != null) ..._titles(context, ref, data),
        ],
      ),
    );
  }

  List<Widget> _titles(BuildContext context, WidgetRef ref, TmdbPerson p) {
    final newestFirst = [...p.credits]
      ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    final keys = [for (final c in newestFirst) c.key];
    final movies = catalogPosters(context, ref, [
      for (final k in keys)
        if (k.kind == TmdbKind.movie) k,
    ]);
    final series = catalogPosters(context, ref, [
      for (final k in keys)
        if (k.kind == TmdbKind.tv) k,
    ]);
    if (movies.isEmpty && series.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
          child: Text(
            "None of ${p.name}'s movies or series are in your playlist.",
            key: const Key('person.empty'),
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ];
    }
    return [
      if (movies.isNotEmpty)
        OtherSourcesSection(
          key: const Key('person.movies'),
          title: 'Movies',
          inset: pageSide(context),
          children: movies,
        ),
      if (movies.isNotEmpty && series.isNotEmpty) const SizedBox(height: 36),
      if (series.isNotEmpty)
        OtherSourcesSection(
          key: const Key('person.series'),
          title: 'Series',
          inset: pageSide(context),
          children: series,
        ),
    ];
  }
}

/// A biography of four lines, with "More" and "Less" when it is longer.
class _Biography extends StatefulWidget {
  const _Biography(this.text);

  final String text;

  @override
  State<_Biography> createState() => _BiographyState();
}

class _BiographyState extends State<_Biography> {
  static const _lines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: AppColors.textSecondary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              key: const Key('person.biography'),
              maxLines: _expanded ? null : _lines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: style,
            ),
            if (long)
              TextButton(
                key: const Key('person.more'),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Less' : 'More'),
              ),
          ],
        );
      },
    );
  }
}
