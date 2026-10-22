import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../data/provider_storage.dart';
import '../../state/guide_controller.dart';
import '../../state/providers.dart';
import '../epg/guide_screen.dart' show formatGuideDate, formatShift;
import '../setup/setup_screen.dart';
import 'time_zone_picker.dart';

/// Provider management, TV guide settings and the player debug toggle.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(savedProviderProvider).value;
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final time = ref.watch(guideTimeProvider);
    final guideState = ref.watch(guideProvider);
    final guide = guideState.guide;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Provider', style: Theme.of(context).textTheme.titleMedium),
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
        Wrap(
          spacing: 8,
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
              onPressed: config == null ? null : () => _remove(context, ref),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove provider'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('TV guide', style: Theme.of(context).textTheme.titleMedium),
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
            GuideState(supported: false) => 'Not available for this provider',
            GuideState(loading: true) => 'Updating…',
            _ when guide == null => guideState.error ?? 'Not downloaded yet',
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
        const Divider(height: 32),
        SwitchListTile(
          title: const Text('Player debug info'),
          subtitle: const Text('mpv property overlay, hwdec selector and log'),
          value: ref.watch(playerDebugProvider),
          onChanged: ref.read(playerDebugProvider.notifier).set,
        ),
      ],
    );
  }
}
