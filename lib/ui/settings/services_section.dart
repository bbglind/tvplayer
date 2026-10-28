import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../data/provider_storage.dart';
import '../../format.dart';
import '../../state/providers.dart';
import '../../state/skip.dart';
import '../../state/tmdb.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/compact.dart';
import 'settings_section.dart';
import '../shell/app_messages.dart';

/// Settings › Services: TMDB (on/off, the key, Test connection, the
/// background fetch, posters, the image cache and removed matches), then
/// SkipDB and TheIntroDB (on/off, Test connection; TheIntroDB's optional
/// key).
class ServicesSection extends ConsumerStatefulWidget {
  const ServicesSection({super.key});

  @override
  ConsumerState<ServicesSection> createState() => _ServicesSectionState();
}

class _ServicesSectionState extends ConsumerState<ServicesSection> {
  /// The result of the last "Test connection", while shown.
  String? _testResult;
  bool _testing = false;

  /// Bumped to show the image cache's size again.
  int _cacheVersion = 0;

  Future<void> _save(AppSettings Function(AppSettings) apply) async {
    try {
      await ref.read(appSettingsProvider.notifier).change(apply);
    } catch (e) {
      if (mounted) {
        showAppMessage(
          ScaffoldMessenger.of(context),
          'Could not save settings (${e.runtimeType})',
          level: NoticeLevel.error,
        );
      }
    }
  }

  Future<void> _enterKey() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _KeyDialog(
        title: 'TMDB key',
        help:
            'Paste your API Read Access Token or API Key from '
            'themoviedb.org › Settings › API.',
        hint: 'API Read Access Token or API Key',
        fieldKey: const Key('settings.tmdbKey.field'),
        saveKey: const Key('settings.tmdbKey.save'),
        save: (ref, text) =>
            ref.read(tmdbCredentialProvider.notifier).save(text),
      ),
    );
    if (saved == true && mounted) setState(() => _testResult = null);
  }

  Future<void> _removeKey() async {
    try {
      await ref.read(tmdbCredentialProvider.notifier).remove();
      if (mounted) setState(() => _testResult = null);
    } on ProviderStorageException catch (e) {
      if (mounted) {
        showAppMessage(
          ScaffoldMessenger.of(context),
          e.message,
          level: NoticeLevel.error,
        );
      }
    }
  }

  Future<void> _test(TmdbCredential credential) async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final failure = await ref.read(tmdbConnectionTesterProvider)(credential);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = describeTmdbTest(failure);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final credential = ref.watch(tmdbCredentialProvider);
    final key = credential.value;
    final on = settings.tmdbEnabled;
    final android = ref.watch(isAndroidProvider);
    return SettingsSection(
      title: 'Services',
      children: [
        SwitchListTile(
          key: const Key('settings.tmdb'),
          secondary: const Icon(Icons.movie_filter_outlined),
          title: const Text('TMDB'),
          subtitle: const Text(
            'Fill in missing details, background images, cast and '
            'recommendations from The Movie Database.',
          ),
          value: on,
          onChanged: (v) => _save((s) => s.copyWith(tmdbEnabled: v)),
        ),
        ListTile(
          key: const Key('settings.tmdbKey'),
          leading: const Icon(Icons.key_outlined),
          title: const Text('TMDB key'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (credential) {
                AsyncError(:final error) => switch (error) {
                  ProviderStorageException(:final message) => message,
                  _ => 'Could not read the key (${error.runtimeType})',
                },
                AsyncData(value: _?) =>
                  android
                      ? 'Saved, encrypted on this device.'
                      : 'Saved in the system keyring.',
                AsyncData() => 'Not set',
                _ => 'Reading…',
              }, key: const Key('settings.tmdbKey.state')),
              if (_testResult case final result?)
                Text(
                  result,
                  key: const Key('settings.tmdbTest.result'),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (key != null)
                TextButton(
                  key: const Key('settings.tmdbKey.remove'),
                  onPressed: _removeKey,
                  child: const Text('Remove key'),
                ),
              if (key != null)
                OutlinedButton(
                  key: const Key('settings.tmdbTest'),
                  onPressed: _testing ? null : () => _test(key),
                  child: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
              OutlinedButton(
                key: const Key('settings.tmdbKey.enter'),
                onPressed: _enterKey,
                child: const Text('Enter key…'),
              ),
            ],
          ),
        ),
        if (on && key != null) _progressTile(settings),
        SwitchListTile(
          key: const Key('settings.tmdbPosters'),
          secondary: const Icon(Icons.image_outlined),
          title: const Text('Prefer TMDB posters'),
          subtitle: const Text(
            "Use TMDB posters where they exist; the provider's otherwise.",
          ),
          value: settings.tmdbPreferPosters,
          onChanged: on
              ? (v) => _save((s) => s.copyWith(tmdbPreferPosters: v))
              : null,
        ),
        _cacheTile(settings),
        if (ref.watch(tmdbMatchesProvider).removedCount case final n
            when n > 0 && on)
          ListTile(
            key: const Key('settings.tmdbRemoved'),
            leading: const Icon(Icons.link_off),
            title: Text('Removed matches: ${formatCount(n)}'),
            subtitle: const Text('Titles that no longer use TMDB info.'),
            trailing: OutlinedButton(
              key: const Key('settings.tmdbRemoved.allow'),
              onPressed: () =>
                  ref.read(tmdbMatchesProvider.notifier).allowAgain(),
              child: const Text('Allow matching again'),
            ),
          ),
        const _SkipServices(),
      ],
    );
  }

  Widget _progressTile(AppSettings settings) {
    final progress = ref.watch(tmdbSyncProvider);
    final paused = settings.tmdbPaused;
    final state = switch (progress?.state) {
      null => 'Counting titles…',
      TmdbSyncState.running => 'Fetching in the background.',
      TmdbSyncState.upToDate => 'Up to date.',
      TmdbSyncState.paused => 'Paused.',
      TmdbSyncState.pausedForPlayback => 'Paused while playing.',
      TmdbSyncState.waitingForNetwork => 'Waiting for the network.',
      TmdbSyncState.keyRejected => "Stopped: TMDB didn't accept the key.",
    };
    return ListTile(
      key: const Key('settings.tmdbProgress'),
      leading: const Icon(Icons.sync),
      title: Text(switch (progress) {
        final p? =>
          'TMDB info: ${formatCount(p.done)} of '
              '${formatCountOf(p.total, 'title', 'titles')}',
        null => 'TMDB info',
      }, key: const Key('settings.tmdbProgress.count')),
      subtitle: Text(state, key: const Key('settings.tmdbProgress.state')),
      trailing: Tooltip(
        message: paused
            ? 'Continue fetching TMDB info'
            : 'Stop fetching TMDB info for now',
        child: OutlinedButton.icon(
          key: const Key('settings.tmdbPause'),
          onPressed: () =>
              ref.read(tmdbSyncProvider.notifier).setPaused(!paused),
          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
          label: Text(paused ? 'Resume' : 'Pause'),
        ),
      ),
    );
  }

  Widget _cacheTile(AppSettings settings) {
    final cache = ref.watch(tmdbImageLoaderProvider);
    final limit = settings.tmdbImageCacheMb * 1000 * 1000;
    return ListTile(
      key: const Key('settings.tmdbCache'),
      leading: const Icon(Icons.photo_library_outlined),
      title: const Text('Image cache'),
      subtitle: FutureBuilder(
        key: ValueKey(_cacheVersion),
        future: cache.totalBytes,
        builder: (context, size) => Text(
          'TMDB images: ${size.hasData ? formatBytes(size.data!) : '…'} '
          'of ${formatBytes(limit)}',
          key: const Key('settings.tmdbCache.size'),
        ),
      ),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<int>(
            key: const Key('settings.tmdbCache.limit'),
            value: settings.tmdbImageCacheMb,
            isExpanded: false,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.small),
            focusColor: AppColors.hover,
            items: [
              for (final mb in AppSettings.tmdbImageCacheChoices)
                DropdownMenuItem(
                  value: mb,
                  child: Text(formatBytes(mb * 1000 * 1000)),
                ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await _save((s) => s.copyWith(tmdbImageCacheMb: v));
              if (mounted) setState(() => _cacheVersion++);
            },
          ),
          TextButton(
            key: const Key('settings.tmdbCache.clear'),
            onPressed: () async {
              await cache.clear();
              if (mounted) setState(() => _cacheVersion++);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// Asks for a service key and saves it with [save]; pops true when saved.
class _KeyDialog extends ConsumerStatefulWidget {
  const _KeyDialog({
    required this.title,
    required this.help,
    required this.hint,
    required this.fieldKey,
    required this.saveKey,
    required this.save,
  });

  final String title;
  final String help;
  final String hint;
  final Key fieldKey;
  final Key saveKey;

  /// Throws [FormatException] (shown under the field) or
  /// ProviderStorageException.
  final Future<void> Function(WidgetRef ref, String text) save;

  @override
  ConsumerState<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends ConsumerState<_KeyDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(ref, _controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } on ProviderStorageException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isCompact(context) ? 320 : 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.help),
            const SizedBox(height: 16),
            TextField(
              key: widget.fieldKey,
              controller: _controller,
              autofocus: true,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: widget.hint,
                errorText: _error,
                errorMaxLines: 4,
              ),
              onSubmitted: (_) => _saving ? null : _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: widget.saveKey,
          onPressed: _saving ? null : _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// SkipDB and TheIntroDB: on/off and Test connection each, and
/// TheIntroDB's optional key.
class _SkipServices extends ConsumerStatefulWidget {
  const _SkipServices();

  @override
  ConsumerState<_SkipServices> createState() => _SkipServicesState();
}

class _SkipServicesState extends ConsumerState<_SkipServices> {
  /// The result of the last "Test connection" per service, while shown.
  final _results = <SkipService, String>{};
  final _testing = <SkipService>{};

  static String _name(SkipService service) => switch (service) {
    SkipService.skipDb => 'SkipDB',
    SkipService.introDb => 'TheIntroDB',
  };

  Future<void> _save(AppSettings Function(AppSettings) apply) async {
    try {
      await ref.read(appSettingsProvider.notifier).change(apply);
    } catch (e) {
      if (mounted) {
        showAppMessage(
          ScaffoldMessenger.of(context),
          'Could not save settings (${e.runtimeType})',
          level: NoticeLevel.error,
        );
      }
    }
  }

  Future<void> _test(SkipService service) async {
    setState(() {
      _testing.add(service);
      _results.remove(service);
    });
    final key = service == SkipService.introDb
        ? ref.read(introDbKeyProvider).value
        : null;
    final failure = await ref.read(skipConnectionTesterProvider)(
      service,
      key: key,
    );
    if (!mounted) return;
    setState(() {
      _testing.remove(service);
      _results[service] = describeSkipTest(_name(service), failure);
    });
  }

  Future<void> _enterKey() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _KeyDialog(
        title: 'TheIntroDB key',
        help:
            'Optional. Paste the API key from your own account on '
            'theintrodb.org; it raises the daily limit of lookups.',
        hint: 'API key',
        fieldKey: const Key('settings.introDbKey.field'),
        saveKey: const Key('settings.introDbKey.save'),
        save: (ref, text) => ref.read(introDbKeyProvider.notifier).save(text),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _results.remove(SkipService.introDb));
    }
  }

  Future<void> _removeKey() async {
    try {
      await ref.read(introDbKeyProvider.notifier).remove();
      if (mounted) setState(() => _results.remove(SkipService.introDb));
    } on ProviderStorageException catch (e) {
      if (mounted) {
        showAppMessage(
          ScaffoldMessenger.of(context),
          e.message,
          level: NoticeLevel.error,
        );
      }
    }
  }

  Widget _serviceTile(
    SkipService service, {
    required String description,
    required bool on,
    required ValueChanged<bool> onChanged,
  }) {
    final id = service.name;
    final result = _results[service];
    final testing = _testing.contains(service);
    return ListTile(
      key: Key('settings.$id'),
      leading: const Icon(Icons.fast_forward_outlined),
      title: Text(_name(service)),
      // The test button below the text, so the title keeps its room on a
      // phone.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          if (result != null)
            Text(
              result,
              key: Key('settings.${id}Test.result'),
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: Key('settings.${id}Test'),
            onPressed: on && !testing ? () => _test(service) : null,
            child: Text(testing ? 'Testing…' : 'Test connection'),
          ),
        ],
      ),
      trailing: Switch(
        key: Key('settings.$id.switch'),
        value: on,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.watch(appSettingsProvider).value ?? const AppSettings();
    final key = ref.watch(introDbKeyProvider);
    final android = ref.watch(isAndroidProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _serviceTile(
          SkipService.skipDb,
          description:
              'Skip intro and Skip recap buttons, and credits times that '
              'bring the next episode sooner, from skipdb.tv.',
          on: settings.skipDbEnabled,
          onChanged: (v) => _save((s) => s.copyWith(skipDbEnabled: v)),
        ),
        _serviceTile(
          SkipService.introDb,
          description:
              "The same from theintrodb.org, for what SkipDB doesn't "
              'have. Kept only while the app runs.',
          on: settings.introDbEnabled,
          onChanged: (v) => _save((s) => s.copyWith(introDbEnabled: v)),
        ),
        ListTile(
          key: const Key('settings.introDbKey'),
          leading: const Icon(Icons.key_outlined),
          title: const Text('TheIntroDB key (optional)'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (key) {
                AsyncError(:final error) => switch (error) {
                  ProviderStorageException(:final message) => message,
                  _ => 'Could not read the key (${error.runtimeType})',
                },
                AsyncData(value: _?) =>
                  android
                      ? 'Saved, encrypted on this device.'
                      : 'Saved in the system keyring.',
                AsyncData() =>
                  'Not set. A key of your own raises the daily limit.',
                _ => 'Reading…',
              }, key: const Key('settings.introDbKey.state')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (key.value != null)
                    TextButton(
                      key: const Key('settings.introDbKey.remove'),
                      onPressed: _removeKey,
                      child: const Text('Remove key'),
                    ),
                  OutlinedButton(
                    key: const Key('settings.introDbKey.enter'),
                    onPressed: _enterKey,
                    child: const Text('Enter key…'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
