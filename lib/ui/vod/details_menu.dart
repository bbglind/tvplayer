import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/providers.dart';
import '../../state/tmdb.dart';
import '../favourites/favourite_menu.dart';

/// The ⋮ of a movie's or series' details page: "Remove from favourites"
/// while it is in one of my categories ([favourite], named [name]), and
/// "Wrong TMDB match? Remove it" while the title is linked to TMDB.
/// Hidden when it has neither.
class DetailsMenu extends ConsumerWidget {
  const DetailsMenu({
    super.key,
    required this.item,
    required this.favourite,
    required this.name,
  });

  final TmdbItem item;
  final ItemRef favourite;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(tmdbLinkProvider(item)).value;
    final isFavourite = ref.watch(
      favouritesProvider.select((d) => d.isFavourite(favourite)),
    );
    if (link == null && !isFavourite) return const SizedBox.shrink();
    final remove = removeFromFavouritesAction(context, ref, favourite, name);
    return PopupMenuButton<void>(
      key: const Key('details.menu'),
      tooltip: 'More options',
      itemBuilder: (context) => [
        if (isFavourite)
          PopupMenuItem(
            key: remove.key,
            onTap: remove.onPressed,
            child: Text(remove.label),
          ),
        if (link != null)
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
