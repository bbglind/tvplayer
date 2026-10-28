import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/tmdb.dart';
import '../home/home_row.dart';
import '../theme/app_colors.dart';
import '../theme/compact.dart';
import 'movies_screen.dart';
import 'other_sources.dart';
import 'person_screen.dart';
import 'poster.dart';
import 'series_screen.dart';

/// Opens the page of the person [cast].
void openPerson(BuildContext context, TmdbCast cast) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonScreen(
          personId: cast.personId,
          name: cast.name,
          profilePath: cast.profilePath,
        ),
      ),
    );

/// Width of one member of the Cast row.
const castMemberWidth = 104.0;

/// Diameter of a cast photo.
const castPhotoSize = 88.0;

/// "Cast": round photos with the actor's and the character's name, in a
/// row that scrolls sideways; a photo opens the person's page. Nothing
/// when [people] is empty.
class CastRow extends StatelessWidget {
  const CastRow({super.key, required this.people});

  final List<TmdbCast> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final height =
        (12 +
                castPhotoSize +
                8 +
                lineHeight(context, text.titleSmall) +
                lineHeight(context, text.bodySmall))
            .ceilToDouble();
    return Column(
      key: const Key('details.cast'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pageSide(context)),
          child: Text('Cast', style: text.titleLarge),
        ),
        const SizedBox(height: 12),
        HorizontalRow(
          height: height,
          itemWidth: castMemberWidth,
          spacing: 4,
          itemCount: people.length,
          itemBuilder: (context, i) => _CastMember(people[i]),
        ),
      ],
    );
  }
}

class _CastMember extends StatelessWidget {
  const _CastMember(this.cast);

  final TmdbCast cast;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: 'Open ${cast.name}',
      child: InkWell(
        key: ValueKey('cast.${cast.personId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => openPerson(context, cast),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              ClipOval(
                child: SizedBox.square(
                  dimension: castPhotoSize,
                  child: Poster(
                    url: tmdbImageRefOrNull(
                      cast.profilePath,
                      TmdbImageSize.w185,
                    ),
                    decodeWidth: 200,
                    placeholder: Icons.person_outline,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cast.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.titleSmall,
              ),
              Text(
                cast.character ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Recommendations": TMDB's recommendations for a title that are in the
/// catalogue (not in hidden categories); nothing when none are.
class RecommendationsRow extends ConsumerWidget {
  const RecommendationsRow({super.key, required this.keys});

  final List<TmdbKey> keys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = catalogPosters(context, ref, keys);
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: OtherSourcesSection(
        key: const Key('details.recommendations'),
        title: 'Recommendations',
        inset: pageSide(context),
        children: children,
      ),
    );
  }
}

/// Posters of the catalogue titles of [keys] in their order, movies and
/// series mixed (see [catalogTitles]).
List<Widget> catalogPosters(
  BuildContext context,
  WidgetRef ref,
  List<TmdbKey> keys,
) => [
  for (final title in catalogTitles(ref, keys))
    switch (title) {
      Movie m => moviePoster(
        context,
        m,
        key: ValueKey('tmdb.movie.${m.streamId}'),
      ),
      Series s => seriesPoster(
        context,
        s,
        key: ValueKey('tmdb.series.${s.seriesId}'),
      ),
      _ => const SizedBox.shrink(),
    },
];
