import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/providers.dart';
import '../../state/variants.dart';
import '../home/home_cards.dart';
import '../home/home_row.dart';
import '../theme/app_colors.dart';
import 'movies_screen.dart';
import 'series_screen.dart';

/// Tells sources apart: their provider label, and where two or more share
/// a label, the provider's date ("Added 24 Apr 2026", with the time when
/// the day is the same too, else "Source 2").
final class SourceLabels {
  SourceLabels(
    List<({int id, String name, DateTime? date})> sources,
    ProviderTags tags, {
    required String verb,
  }) {
    final byLabel = <String?, List<({int id, String name, DateTime? date})>>{};
    for (final s in sources) {
      final label = tags.display(s.name).label;
      _labels[s.id] = label;
      (byLabel[label] ??= []).add(s);
    }
    for (final same in byLabel.values) {
      if (same.length < 2) continue;
      String? day(DateTime? d) {
        if (d == null) return null;
        final l = d.toLocal();
        return '$verb ${l.day} ${monthNames[l.month - 1]} ${l.year}';
      }

      String? time(DateTime? d) {
        if (d == null) return null;
        final l = d.toLocal();
        String two(int n) => n.toString().padLeft(2, '0');
        return '${day(d)} ${two(l.hour)}:${two(l.minute)}';
      }

      bool distinct(List<String?> texts) =>
          !texts.contains(null) && texts.toSet().length == texts.length;
      final days = [for (final s in same) day(s.date)];
      final times = [for (final s in same) time(s.date)];
      final texts = distinct(days)
          ? days
          : distinct(times)
          ? times
          : [for (var i = 0; i < same.length; i++) 'Source ${i + 1}'];
      for (final (i, s) in same.indexed) {
        _dates[s.id] = texts[i]!;
      }
    }
  }

  final _labels = <int, String?>{};
  final _dates = <int, String>{};

  /// The provider's label of [id], e.g. `NF`.
  String? labelOf(int id) => _labels[id];

  /// The date that tells [id] apart from sources with the same label; null
  /// when its label is its own.
  String? dateOf(int id) => _dates[id];

  /// [id] in words, for "(from …)": `NF`, or `EN, added 24 Apr 2026`.
  String describe(int id) {
    final label = labelOf(id) ?? 'another source';
    return switch (dateOf(id)) {
      final d? => '$label, ${d[0].toLowerCase()}${d.substring(1)}',
      null => label,
    };
  }
}

/// The other sources of a movie or series, with which was played last.
final class Sources<T> {
  const Sources(this.variants, this.labels, this.lastPlayed);

  /// The other sources, the one played last first, then by label.
  final List<T> variants;
  final SourceLabels labels;

  /// The id of the source (this one included) played last, when there are
  /// other sources.
  final int? lastPlayed;
}

/// The other sources of [movie], without hidden categories.
Sources<Movie> movieSources(WidgetRef ref, Movie movie) {
  final catalog = ref.watch(movieCatalogProvider).catalog;
  final hidden = ref.watch(favouritesProvider).hiddenIds(ContentKind.movie);
  final variants = [
    for (final id
        in ref.watch(movieVariantsProvider).variantsOf(movie.streamId))
      if (catalog?.byId(id) case final m? when !hidden.contains(m.categoryId))
        m,
  ];
  final all = [movie, ...variants];
  final last = variants.isEmpty
      ? null
      : lastPlayed(ref.watch(watchProvider), [
          for (final m in all) movieKey(m.streamId),
        ]);
  final labels = SourceLabels(
    [for (final m in all) (id: m.streamId, name: m.name, date: m.added)],
    ref.watch(providerTagsProvider),
    verb: 'Added',
  );
  return Sources(
    _sorted(variants, (m) => m.streamId, labels, last, movieKey),
    labels,
    _id(last),
  );
}

/// The other sources of [series], without hidden categories.
Sources<Series> seriesSources(WidgetRef ref, Series series) {
  final catalog = ref.watch(seriesCatalogProvider).catalog;
  final hidden = ref.watch(favouritesProvider).hiddenIds(ContentKind.series);
  final variants = [
    for (final id
        in ref.watch(seriesVariantsProvider).variantsOf(series.seriesId))
      if (catalog?.byId(id) case final s? when !hidden.contains(s.categoryId))
        s,
  ];
  final all = [series, ...variants];
  final last = variants.isEmpty
      ? null
      : lastPlayed(ref.watch(watchProvider), [
          for (final s in all) seriesKey(s.seriesId),
        ]);
  final labels = SourceLabels(
    [for (final s in all) (id: s.seriesId, name: s.name, date: s.lastModified)],
    ref.watch(providerTagsProvider),
    verb: 'Updated',
  );
  return Sources(
    _sorted(variants, (s) => s.seriesId, labels, last, seriesKey),
    labels,
    _id(last),
  );
}

int? _id(String? key) => key == null ? null : int.tryParse(key.split(':')[1]);

List<T> _sorted<T>(
  List<T> items,
  int Function(T) idOf,
  SourceLabels labels,
  String? last,
  String Function(int) keyOf,
) {
  int rank(T item) => keyOf(idOf(item)) == last ? 0 : 1;
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      if (byRank != 0) return byRank;
      final la = labels.labelOf(idOf(a.$2)) ?? '\u{10FFFF}';
      final lb = labels.labelOf(idOf(b.$2)) ?? '\u{10FFFF}';
      final byLabel = la.compareTo(lb);
      return byLabel != 0 ? byLabel : a.$1.compareTo(b.$1);
    });
  return [for (final (_, item) in indexed) item];
}

/// Width of a poster in "Other sources": room for a date at text scale 1.4.
const sourcePosterWidth = 180.0;

/// "Other sources" on a details page: the other sources as posters, each
/// with its provider label; the one played last has a history icon, and
/// sources sharing a label show the provider's date.
class OtherSourcesSection extends StatelessWidget {
  const OtherSourcesSection({
    super.key,
    required this.children,
    this.inset = 0,
  });

  final List<Widget> children;

  /// Distance of the heading from the page edges.
  final double inset;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('details.sources'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Text(
            'Other sources',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          // The cards have room for the focus ring around them.
          padding: EdgeInsets.symmetric(horizontal: math.max(0, inset - 6)),
          child: HorizontalRow(
            height: posterCardHeight(
              context,
              sourcePosterWidth,
              aspectRatio: 2 / 3,
            ),
            itemWidth: sourcePosterWidth,
            spacing: 4,
            itemCount: children.length,
            itemBuilder: (context, i) => children[i],
          ),
        ),
      ],
    );
  }
}

/// The posters of [sources] of a movie.
List<Widget> moviePosters(BuildContext context, Sources<Movie> sources) => [
  for (final m in sources.variants)
    moviePoster(
      context,
      m,
      key: ValueKey('source.${m.streamId}'),
      subtitle:
          sources.labels.dateOf(m.streamId) ??
          (sources.lastPlayed == m.streamId ? 'Last played' : null),
      lastPlayed: sources.lastPlayed == m.streamId,
    ),
];

/// The posters of [sources] of a series, with where each stands.
List<Widget> seriesPosters(
  BuildContext context,
  WidgetRef ref,
  Sources<Series> sources,
) => [
  for (final s in sources.variants)
    seriesPoster(
      context,
      s,
      key: ValueKey('source.${s.seriesId}'),
      subtitle: _seriesSubtitle(ref, sources, s),
      lastPlayed: sources.lastPlayed == s.seriesId,
    ),
];

String? _seriesSubtitle(WidgetRef ref, Sources<Series> sources, Series s) {
  final progress = ref.watch(watchProvider).series[s.seriesId];
  final code = switch ((progress?.nextSeason, progress?.nextEpisodeNumber)) {
    (final season?, final episode?) => 'S$season · E$episode',
    _ => null,
  };
  final parts = [?sources.labels.dateOf(s.seriesId), ?code];
  if (parts.isNotEmpty) return parts.join(' · ');
  return sources.lastPlayed == s.seriesId ? 'Last played' : null;
}

/// The meta line of a details page ("2025 · GB · Drama"), with "Last
/// played" when this source was played last of its sources.
class FactsLine extends StatelessWidget {
  const FactsLine(this.facts, {super.key, this.lastPlayed = false});

  final List<String> facts;
  final bool lastPlayed;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AppColors.textMuted);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: facts.join(' · ')),
          if (lastPlayed) ...[
            if (facts.isNotEmpty) const TextSpan(text: ' · '),
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.history,
                  key: Key('details.lastPlayed'),
                  size: 16,
                  color: AppColors.accent,
                ),
              ),
            ),
            const TextSpan(text: 'Last played'),
          ],
        ],
      ),
      style: style,
    );
  }
}
