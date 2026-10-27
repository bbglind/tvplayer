import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../state/playlist_refresh.dart';
import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'settings_section.dart';

/// The name of [part] in Settings: "Channels", "TV guide".
String playlistPartLabel(PlaylistPart part) => switch (part) {
  PlaylistPart.channels => 'Channels',
  PlaylistPart.movies => 'Movies',
  PlaylistPart.series => 'Series',
  PlaylistPart.guide => 'TV guide',
};

/// [part] within a sentence: "channels", "the TV guide".
String playlistPartPhrase(PlaylistPart part) => switch (part) {
  PlaylistPart.guide => 'the TV guide',
  _ => playlistPartLabel(part).toLowerCase(),
};

/// [parts] within a sentence: "movies", "movies and series", "channels,
/// movies and the TV guide".
String playlistPartsPhrase(List<PlaylistPart> parts) {
  final words = [for (final p in parts) playlistPartPhrase(p)];
  if (words.length < 2) return words.join();
  return '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
}

/// Labels of the automatic refresh choices.
String autoRefreshLabel(AutoRefresh mode) => switch (mode) {
  AutoRefresh.off => 'Off',
  AutoRefresh.onStart => 'On app start',
  AutoRefresh.every6Hours => 'Every 6 hours',
  AutoRefresh.daily => 'Daily',
};

/// What the automatic refresh choice [mode] does, below the setting.
String autoRefreshDescription(AutoRefresh mode) => switch (mode) {
  AutoRefresh.daily =>
    'Once a day: the first time tvplayer is open on a new day (your local '
        'time), also when it stays open past midnight. Waits while '
        'something is playing.',
  _ =>
    'Runs only while tvplayer is open, and on start when the time has '
        'passed. Waits while something is playing.',
};

/// Settings › Playlist: when each part was last updated, "Refresh all"
/// and the automatic refresh choice.
class PlaylistSection extends ConsumerWidget {
  const PlaylistSection({super.key});

  Future<void> _setAutoRefresh(
    BuildContext context,
    WidgetRef ref,
    AutoRefresh mode,
  ) async {
    try {
      await ref.read(playlistStatusProvider.notifier).setAutoRefresh(mode);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save settings (${e.runtimeType})')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(availablePartsProvider);
    final status = ref.watch(playlistStatusProvider);
    final run = ref.watch(playlistRefreshProvider);
    final missing = ref.watch(missingItemsProvider);
    return SettingsSection(
      title: 'Playlist',
      children: [
        for (final part in PlaylistPart.values)
          _partTile(
            context,
            ref,
            part: part,
            available: available.contains(part),
            status: status.part(part),
            running: run.running == part,
            waiting: run.isWaiting(part),
          ),
        ListTile(
          leading: const Icon(Icons.autorenew),
          title: const Text('Automatic refresh'),
          subtitle: Text(autoRefreshDescription(status.autoRefresh)),
          trailing: DropdownButton<AutoRefresh>(
            key: const Key('settings.autoRefresh'),
            value: status.autoRefresh,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.small),
            focusColor: AppColors.hover,
            items: [
              for (final m in AutoRefresh.values)
                DropdownMenuItem(value: m, child: Text(autoRefreshLabel(m))),
            ],
            onChanged: (m) {
              if (m != null) unawaited(_setAutoRefresh(context, ref, m));
            },
          ),
        ),
        if (!missing.isEmpty) _missingTile(context, missing),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            children: [
              FilledButton.icon(
                key: const Key('settings.refreshAll'),
                onPressed: run.busy || available.isEmpty
                    ? null
                    : () => unawaited(
                        ref.read(playlistRefreshProvider.notifier).refreshAll(),
                      ),
                icon: const Icon(Icons.refresh),
                label: Text(
                  run.busy
                      ? 'Refreshing ${run.done + 1} of ${run.total}…'
                      : 'Refresh all',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How many items [part] holds now, e.g. "4,512 channels"; null when
/// nothing is loaded.
String? _count(WidgetRef ref, PlaylistPart part) => switch (part) {
  PlaylistPart.channels => switch (ref.watch(liveCatalogProvider).value) {
    final c? => formatCountOf(c.channelCount, 'channel', 'channels'),
    null => null,
  },
  PlaylistPart.movies => switch (ref.watch(movieCatalogProvider).catalog) {
    final c? => formatCountOf(c.items.length, 'movie', 'movies'),
    null => null,
  },
  PlaylistPart.series => switch (ref.watch(seriesCatalogProvider).catalog) {
    final c? => formatCountOf(c.items.length, 'series', 'series'),
    null => null,
  },
  PlaylistPart.guide => switch (ref.watch(guideProvider).guide) {
    final g? => formatCountOf(g.programCount, 'programme', 'programmes'),
    null => null,
  },
};

/// One part: when it was last updated and how much it holds, or what is
/// happening to it, or why its last update failed.
ListTile _partTile(
  BuildContext context,
  WidgetRef ref, {
  required PlaylistPart part,
  required bool available,
  required PartStatus status,
  required bool running,
  required bool waiting,
}) {
  final time = ref.watch(deviceTimeProvider);
  final now = time.local(ref.watch(clockProvider));
  String when(DateTime t) => formatUpdated(time.local(t), now);
  final count = available ? _count(ref, part) : null;
  final updated = status.updatedAt;
  final lastUpdate = updated == null
      ? 'Not downloaded yet'
      : 'Updated ${when(updated)}';
  final failed = available && status.failed && !running && !waiting;
  final kept = part == PlaylistPart.guide
      ? 'The previous guide is kept.'
      : 'The previous list is kept.';
  final String subtitle;
  if (!available) {
    subtitle = 'Not available for this provider';
  } else if (running) {
    subtitle = 'Updating…';
  } else if (waiting) {
    subtitle = 'Waiting…';
  } else if (failed) {
    subtitle = [
      'Last update failed ${when(status.failedAt!)}: ${status.error ?? ''}',
      if (count != null) kept,
      if (updated != null) 'Last successful update ${when(updated)}.',
    ].join(' ');
  } else {
    subtitle = [lastUpdate, ?count].join(' · ');
  }
  return ListTile(
    key: Key('settings.playlist.${part.name}'),
    leading: Icon(switch (part) {
      PlaylistPart.channels => Icons.live_tv_outlined,
      PlaylistPart.movies => Icons.movie_outlined,
      PlaylistPart.series => Icons.video_library_outlined,
      PlaylistPart.guide => Icons.calendar_view_week_outlined,
    }),
    title: Text(playlistPartLabel(part)),
    subtitle: Text(subtitle),
    enabled: available,
    trailing: running
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : failed
        ? Tooltip(
            message: 'Last update failed',
            child: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
          )
        : null,
  );
}

/// My items the provider no longer lists. Nothing is deleted; favourites
/// can be listed by name.
ListTile _missingTile(BuildContext context, MissingItems missing) {
  void showFavourites() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Favourites no longer listed'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in missing.favourites)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(m.name),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  final counts = [
    if (missing.favourites.isNotEmpty)
      formatCountOf(missing.favourites.length, 'favourite', 'favourites'),
    if (missing.continueWatching > 0)
      formatCountOf(
        missing.continueWatching,
        'Continue watching item',
        'Continue watching items',
      ),
    if (missing.recentChannels > 0)
      formatCountOf(
        missing.recentChannels,
        'recently viewed channel',
        'recently viewed channels',
      ),
  ];
  final favourites = missing.favourites.isNotEmpty;
  return ListTile(
    key: const Key('settings.playlist.missing'),
    leading: const Icon(Icons.link_off),
    title: const Text('No longer listed by the provider'),
    subtitle: Text(
      '${counts.join(', ')}. Nothing was deleted: they come back if the '
      'provider lists them again.',
    ),
    trailing: favourites ? const Icon(Icons.chevron_right) : null,
    onTap: favourites ? showFavourites : null,
  );
}
