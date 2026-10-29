import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../data/provider_storage.dart';
import '../../format.dart';
import '../../state/playlist_refresh.dart';
import '../../state/providers.dart';
import '../../state/sync.dart';
import '../shell/app_messages.dart';
import '../theme/compact.dart';
import 'services_section.dart' show KeyDialog;
import 'settings_section.dart';

/// Sync with the user's own sync server: on/off, the address, the token,
/// Test connection, the last sync and Sync now. Off, only the switch.
class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key});

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  bool _testing = false;

  void _message(String text, NoticeLevel level) {
    if (!mounted) return;
    showAppMessage(ScaffoldMessenger.of(context), text, level: level);
  }

  Future<void> _save(AppSettings Function(AppSettings) apply) async {
    try {
      await ref.read(appSettingsProvider.notifier).change(apply);
    } catch (e) {
      _message('Could not save settings (${e.runtimeType})', NoticeLevel.error);
    }
  }

  Future<void> _editAddress(String? current) async {
    final address = await showDialog<String>(
      context: context,
      builder: (context) => _AddressDialog(current: current),
    );
    if (address == null) return;
    await _save((s) => s.copyWith(syncServer: () => address));
  }

  Future<void> _enterToken() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => KeyDialog(
        title: 'Sync token',
        help:
            'Paste the token that the sync server printed for this device '
            '(tvplayer_sync_server token create).',
        hint: 'tvps_…',
        fieldKey: const Key('settings.syncToken.field'),
        saveKey: const Key('settings.syncToken.save'),
        save: (ref, text) => ref.read(syncTokenProvider.notifier).save(text),
      ),
    );
    if (saved == true) {
      ref.read(syncProvider.notifier).request(SyncReason.start);
    }
  }

  Future<void> _removeToken() async {
    try {
      await ref.read(syncTokenProvider.notifier).remove();
    } on ProviderStorageException catch (e) {
      _message(e.message, NoticeLevel.error);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final (text, ok) = await ref.read(syncProvider.notifier).testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    _message(text, ok ? NoticeLevel.success : NoticeLevel.error);
  }

  Future<void> _syncNow() async {
    final error = await ref.read(syncProvider.notifier).syncNow();
    _message(
      error ?? 'Synced.',
      error == null ? NoticeLevel.success : NoticeLevel.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final on = settings.syncEnabled;
    return SettingsSection(
      title: 'Sync',
      children: [
        SwitchListTile(
          key: const Key('settings.sync'),
          secondary: const Icon(Icons.sync),
          title: const Text('Sync'),
          subtitle: const Text(
            'Keep watch progress, favourites and settings the same on your '
            'devices, through your own sync server.',
          ),
          value: on,
          onChanged: (v) => _save((s) => s.copyWith(syncEnabled: v)),
        ),
        if (on) ..._details(settings),
      ],
    );
  }

  List<Widget> _details(AppSettings settings) {
    final address = settings.syncServer;
    final token = ref.watch(syncTokenProvider);
    final status = ref.watch(syncProvider);
    final android = ref.watch(isAndroidProvider);
    final ready =
        parseSyncServerAddress(address ?? '') != null && token.value != null;
    final time = ref.watch(deviceTimeProvider);
    final now = time.local(ref.watch(clockProvider));
    return [
      ListTile(
        key: const Key('settings.syncServer'),
        leading: const Icon(Icons.dns_outlined),
        title: const Text('Server address'),
        subtitle: Text(
          address ?? 'Not set',
          key: const Key('settings.syncServer.value'),
        ),
        trailing: OutlinedButton(
          key: const Key('settings.syncServer.edit'),
          onPressed: () => _editAddress(address),
          child: const Text('Edit…'),
        ),
      ),
      ListTile(
        key: const Key('settings.syncToken'),
        leading: const Icon(Icons.key_outlined),
        title: const Text('Token'),
        subtitle: Text(switch (token) {
          AsyncError(:final error) => switch (error) {
            ProviderStorageException(:final message) => message,
            _ => 'Could not read the token (${error.runtimeType})',
          },
          AsyncData(value: _?) =>
            android
                ? 'Saved, encrypted on this device.'
                : 'Saved in the system keyring.',
          AsyncData() => 'Not set',
          _ => 'Reading…',
        }, key: const Key('settings.syncToken.state')),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (token.value != null)
              TextButton(
                key: const Key('settings.syncToken.remove'),
                onPressed: _removeToken,
                child: const Text('Remove token'),
              ),
            OutlinedButton(
              key: const Key('settings.syncToken.enter'),
              onPressed: _enterToken,
              child: const Text('Enter token…'),
            ),
          ],
        ),
      ),
      ListTile(
        key: const Key('settings.syncStatus'),
        leading: const Icon(Icons.cloud_sync_outlined),
        title: Text(switch (status.lastSync) {
          final t? => 'Last sync: ${formatUpdated(time.local(t), now)}',
          null => 'Last sync: Never',
        }, key: const Key('settings.syncStatus.last')),
        subtitle: Text(
          status.running
              ? 'Syncing…'
              : status.error == null
              ? 'Syncs at start, when playback stops, every 5 minutes and '
                    'after changes.'
              : 'Last sync failed: ${status.error}',
          key: const Key('settings.syncStatus.state'),
        ),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const Key('settings.syncTest'),
              onPressed: ready && !_testing ? _test : null,
              child: Text(_testing ? 'Testing…' : 'Test connection'),
            ),
            OutlinedButton.icon(
              key: const Key('settings.syncNow'),
              onPressed: ready && !status.running ? _syncNow : null,
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          ],
        ),
      ),
    ];
  }
}

/// Asks for the sync server's address; pops it (trimmed) when valid.
class _AddressDialog extends StatefulWidget {
  const _AddressDialog({this.current});

  final String? current;

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  late final _controller = TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (parseSyncServerAddress(text) == null) {
      setState(
        () => _error =
            'Enter an address like http://192.0.2.10:8787 or '
            'https://sync.example.com.',
      );
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server address'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isCompact(context) ? 320 : 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The address of your sync server: http:// on your home '
              'network, or https:// through a reverse proxy.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('settings.syncServer.field'),
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://sync.example.com',
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('settings.syncServer.save'),
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
