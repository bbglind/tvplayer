import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../data/provider_storage.dart';
import '../../state/guide_controller.dart';
import '../../state/providers.dart';
import '../epg/guide_screen.dart' show formatGuideDate, formatShift;
import '../setup/setup_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'category_settings_screen.dart';
import 'language_list_editor.dart';
import 'settings_section.dart';
import 'time_zone_picker.dart';

/// Provider management, TV guide settings and player options.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove provider?'),
        content: const Text(
          'The saved connection details are deleted from the keyring.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(savedProviderProvider.notifier).remove();
    } on ProviderStorageException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _saveSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    try {
      await ref.read(appSettingsProvider.notifier).set(settings);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save settings (${e.runtimeType})')),
        );
      }
    }
  }

  Future<void> _pickTimeZone(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final choice = await showTimeZonePicker(
      context,
      current: settings.guideTimeZone,
      deviceZone: ref.read(deviceTimeZoneProvider),
    );
    if (choice == null || !context.mounted) return;
    await _saveSettings(
      context,
      ref,
      settings.copyWith(guideTimeZone: () => choice.zone),
    );
  }

  Future<void> _editLanguages(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings, {
    required bool subtitles,
  }) async {
    final codes = await showLanguageListEditor(
      context,
      title: subtitles ? 'Subtitle languages' : 'Audio languages',
      initial: subtitles ? settings.subtitleLanguages : settings.audioLanguages,
      emptyHint: subtitles
          ? 'No subtitles will be chosen automatically'
          : "Each stream's default audio is used",
    );
    if (codes == null || !context.mounted) return;
    await _saveSettings(
      context,
      ref,
      subtitles
          ? settings.copyWith(subtitleLanguages: codes)
          : settings.copyWith(audioLanguages: codes),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(savedProviderProvider).value;
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final time = ref.watch(guideTimeProvider);
    final guideState = ref.watch(guideProvider);
    final guide = guideState.guide;
    final favourites = ref.watch(favouritesProvider);
    return ListView(
      padding: AppSpacing.page,
      children: [
        SettingsSection(
          title: 'Provider',
          children: [
            ListTile(
              leading: const Icon(Icons.dns),
              title: Text(switch (config?.type) {
                ProviderType.xtream => 'Xtream',
                ProviderType.m3u => 'M3U playlist',
                null => 'None',
              }),
              subtitle: const Text(
                'Connection details are stored in the system keyring.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: config == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => SetupScreen(
                                initial: config,
                                onSaved: () => Navigator.of(context).pop(),
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit provider'),
                  ),
                  OutlinedButton.icon(
                    onPressed: config == null
                        ? null
                        : () => _remove(context, ref),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove provider'),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'TV guide',
          children: [
            ListTile(
              key: const Key('settings.timeZone'),
              leading: const Icon(Icons.public),
              title: const Text('Time zone'),
              subtitle: Text(
                settings.guideTimeZone == null
                    ? 'Device time zone (${ref.watch(deviceTimeZoneProvider)})'
                    : settings.guideTimeZone!,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickTimeZone(context, ref, settings),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Time shift'),
              subtitle: const Text(
                'Moves all guide times, for providers whose times are wrong.',
              ),
              trailing: DropdownButton<int>(
                key: const Key('settings.shift'),
                value: settings.guideShiftHours,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.small),
                focusColor: AppColors.hover,
                items: [
                  for (
                    var h = -AppSettings.maxShiftHours;
                    h <= AppSettings.maxShiftHours;
                    h++
                  )
                    DropdownMenuItem(
                      value: h,
                      child: Text(h == 0 ? 'None' : formatShift(h)),
                    ),
                ],
                onChanged: (h) => _saveSettings(
                  context,
                  ref,
                  settings.copyWith(guideShiftHours: h),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Guide data'),
              subtitle: Text(switch (guideState) {
                GuideState(supported: false) =>
                  'Not available for this provider',
                GuideState(loading: true) => 'Updating…',
                _ when guide == null =>
                  guideState.error ?? 'Not downloaded yet',
                _ =>
                  'Updated ${formatGuideDate(time, guide.fetchedAt)} '
                      '${time.formatLocalHm(guide.fetchedAt)}, '
                      '${guide.programCount} programmes'
                      '${guideState.error == null ? '' : ' · last update failed'}',
              }),
              trailing: IconButton(
                tooltip: 'Refresh TV guide',
                icon: const Icon(Icons.refresh),
                onPressed: guideState.supported && !guideState.loading
                    ? ref.read(guideProvider.notifier).refresh
                    : null,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Subtitles and audio',
          children: [
            SwitchListTile(
              key: const Key('settings.subtitlesOn'),
              title: const Text('Subtitles on by default'),
              subtitle: const Text(
                'Off still shows forced subtitles for foreign-language parts.',
              ),
              value: settings.subtitlesOn,
              onChanged: (v) => _saveSettings(
                context,
                ref,
                settings.copyWith(subtitlesOn: v),
              ),
            ),
            ListTile(
              key: const Key('settings.subtitleLanguages'),
              leading: const Icon(Icons.subtitles_outlined),
              title: const Text('Subtitle languages'),
              subtitle: Text(
                describeLanguages(settings.subtitleLanguages, empty: 'None'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _editLanguages(context, ref, settings, subtitles: true),
            ),
            ListTile(
              key: const Key('settings.audioLanguages'),
              leading: const Icon(Icons.record_voice_over_outlined),
              title: const Text('Audio languages'),
              subtitle: Text(
                describeLanguages(
                  settings.audioLanguages,
                  empty: 'Stream default',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _editLanguages(context, ref, settings, subtitles: false),
            ),
            const ListTile(
              dense: true,
              subtitle: Text(
                'Choosing a track while playing a series is remembered for the '
                'rest of that series.',
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Player',
          children: [
            SwitchListTile(
              key: const Key('settings.playbackStats'),
              title: const Text('Show playback statistics'),
              subtitle: const Text('Dropped-frame counters below the video'),
              value: settings.showPlaybackStats,
              onChanged: (v) => _saveSettings(
                context,
                ref,
                settings.copyWith(showPlaybackStats: v),
              ),
            ),
            SwitchListTile(
              title: const Text('Player debug info'),
              subtitle: const Text(
                'mpv property overlay, hwdec selector and log',
              ),
              value: ref.watch(playerDebugProvider),
              onChanged: ref.read(playerDebugProvider.notifier).set,
            ),
          ],
        ),
        SettingsSection(
          title: 'Categories',
          children: [
            for (final (kind, icon, label) in [
              (ContentKind.live, Icons.live_tv_outlined, 'Live TV'),
              (ContentKind.movie, Icons.movie_outlined, 'Movies'),
              (ContentKind.series, Icons.tv_outlined, 'Series'),
            ])
              ListTile(
                key: Key('settings.categories.${kind.name}'),
                leading: Icon(icon),
                title: Text(label),
                subtitle: Text(describeCategories(favourites, kind)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CategorySettingsScreen(kind: kind),
                  ),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: 'Search',
          children: [
            SwitchListTile(
              key: const Key('settings.searchHidden'),
              title: const Text('Show hidden categories in global search'),
              subtitle: const Text(
                'Also find channels, movies and series in provider categories '
                'you have hidden.',
              ),
              value: settings.showHiddenInGlobalSearch,
              onChanged: (v) => _saveSettings(
                context,
                ref,
                settings.copyWith(showHiddenInGlobalSearch: v),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
