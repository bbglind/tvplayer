import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/provider_storage.dart';
import '../../state/providers.dart';
import '../setup/setup_screen.dart';

/// Provider management and the player debug toggle.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(savedProviderProvider).value;
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
