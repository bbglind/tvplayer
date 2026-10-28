import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/tmdb.dart';

/// The ⋮ of a movie's or series' details page, while the title is linked
/// to TMDB: "Wrong TMDB match? Remove it".
class DetailsMenu extends ConsumerWidget {
  const DetailsMenu({super.key, required this.item});

  final TmdbItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(tmdbLinkProvider(item)).value;
    if (link == null) return const SizedBox.shrink();
    return PopupMenuButton<void>(
      key: const Key('details.menu'),
      tooltip: 'More options',
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('details.removeMatch'),
          onTap: () => unawaited(_confirm(context, ref, link)),
          child: const Text('Wrong TMDB match? Remove it'),
        ),
      ],
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    TmdbLink link,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the TMDB match?'),
        content: const Text(
          "This title won't be matched with TMDB again. You can allow it "
          'again in Settings › Services.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('details.removeMatch.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true) return;
    await ref.read(tmdbMatchesProvider.notifier).remove(item.kind, link);
  }
}
