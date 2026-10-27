import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../state/downloads_controller.dart';
import '../../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/compact.dart';
import 'settings_section.dart';

/// Asks for a folder, starting in [initial]; null when cancelled.
/// Overridden in tests.
final folderPickerProvider = Provider<Future<String?> Function(String initial)>(
  (ref) =>
      (initial) => getDirectoryPath(
        initialDirectory: initial,
        confirmButtonText: 'Choose',
      ),
);

/// Settings › Downloads & recording: the folder, the margins around
/// programmes, the longest recording and the disk space kept free.
class DownloadsSection extends ConsumerWidget {
  const DownloadsSection({super.key});

  Future<void> _save(
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

  Future<void> _pickFolder(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final folder = await ref.read(folderPickerProvider)(
      ref.read(downloadFolderProvider),
    );
    if (folder == null || !context.mounted) return;
    await _save(context, ref, settings.copyWith(downloadFolder: () => folder));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final folder = ref.watch(downloadFolderProvider);
    Widget dropdown({
      required String key,
      required int value,
      required List<int> choices,
      required String Function(int) label,
      required AppSettings Function(int) apply,
    }) => DropdownButton<int>(
      key: Key('settings.$key'),
      value: value,
      // Under the text in the phone layout, as wide as the row.
      isExpanded: isCompact(context),
      underline: const SizedBox.shrink(),
      dropdownColor: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.small),
      focusColor: AppColors.hover,
      items: [
        for (final c in choices)
          DropdownMenuItem(value: c, child: Text(label(c))),
      ],
      onChanged: (v) {
        if (v != null) _save(context, ref, apply(v));
      },
    );
    String minutes(int m) => m == 0 ? 'None' : '$m min';
    return SettingsSection(
      title: 'Downloads & recording',
      children: [
        ListTile(
          key: const Key('settings.downloadFolder'),
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Folder'),
          subtitle: Text(
            folder,
            key: const Key('settings.downloadFolder.path'),
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              if (settings.downloadFolder != null)
                TextButton(
                  key: const Key('settings.downloadFolder.reset'),
                  onPressed: () => _save(
                    context,
                    ref,
                    settings.copyWith(downloadFolder: () => null),
                  ),
                  child: const Text('Use default'),
                ),
              // Android's folder picker gives a content URI, not a path.
              if (!ref.watch(isAndroidProvider))
                OutlinedButton(
                  key: const Key('settings.downloadFolder.change'),
                  onPressed: () => _pickFolder(context, ref, settings),
                  child: const Text('Change…'),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.more_time),
          title: const Text('End margin'),
          subtitle: const Text(
            'Recorded and saved after a programme ends, in case it runs '
            'late.',
          ),
          trailing: dropdown(
            key: 'endMargin',
            value: settings.endMarginMinutes,
            choices: AppSettings.endMarginChoices,
            label: minutes,
            apply: (v) => settings.copyWith(endMarginMinutes: v),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Start margin (replay)'),
          subtitle: const Text(
            'Saved before a programme starts, when downloading it from the '
            'archive.',
          ),
          trailing: dropdown(
            key: 'startMargin',
            value: settings.startMarginMinutes,
            choices: AppSettings.startMarginChoices,
            label: minutes,
            apply: (v) => settings.copyWith(startMarginMinutes: v),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Maximum recording length'),
          subtitle: const Text(
            'A recording stops after this long, e.g. when the TV guide has '
            'no end time.',
          ),
          trailing: dropdown(
            key: 'maxRecording',
            value: settings.maxRecordingHours,
            choices: AppSettings.maxRecordingChoices,
            label: (h) => '$h h',
            apply: (v) => settings.copyWith(maxRecordingHours: v),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Minimum free disk space'),
          subtitle: const Text(
            'Downloads pause and recordings stop below this, keeping what '
            'was saved. A warning comes 1 GB before.',
          ),
          trailing: dropdown(
            key: 'minFree',
            value: settings.minFreeGb,
            choices: AppSettings.minFreeChoices,
            label: (g) => '$g GB',
            apply: (v) => settings.copyWith(minFreeGb: v),
          ),
        ),
      ],
    );
  }
}
