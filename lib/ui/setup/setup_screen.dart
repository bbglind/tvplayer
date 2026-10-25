import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/setup_controller.dart';
import '../theme/app_colors.dart';

/// Add or edit the provider: Xtream (host, username, password) or an M3U
/// playlist URL, with a connection test.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.initial, this.onSaved});

  /// Prefills the form when editing an existing provider.
  final ProviderConfig? initial;

  /// Called after a successful save (e.g. to close an edit route).
  final VoidCallback? onSaved;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late ProviderType _type = widget.initial?.type ?? ProviderType.xtream;
  late final _host = TextEditingController(text: widget.initial?.host);
  late final _username = TextEditingController(text: widget.initial?.username);
  late final _password = TextEditingController(text: widget.initial?.password);
  late final _playlistUrl = TextEditingController(
    text: widget.initial?.playlistUrl,
  );
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_host, _username, _password, _playlistUrl]) {
      c.addListener(_onFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_host, _username, _password, _playlistUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() {
    ref.read(setupControllerProvider.notifier).formChanged();
    setState(() {}); // Re-evaluate button enablement.
  }

  /// The config described by the form, or null while it is incomplete.
  ProviderConfig? get _config => switch (_type) {
    ProviderType.xtream
        when _host.text.trim().isNotEmpty &&
            _username.text.trim().isNotEmpty &&
            _password.text.isNotEmpty =>
      ProviderConfig.xtream(
        host: _host.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      ),
    ProviderType.m3u when _playlistUrl.text.trim().isNotEmpty =>
      ProviderConfig.m3u(playlistUrl: _playlistUrl.text.trim()),
    _ => null,
  };

  Future<void> _save(ProviderConfig config) async {
    final ok = await ref.read(setupControllerProvider.notifier).save(config);
    if (ok) widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);
    final config = _config;
    final editing = widget.initial != null;

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit provider' : 'Add a provider')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ProviderType>(
                  segments: const [
                    ButtonSegment(
                      value: ProviderType.xtream,
                      label: Text('Xtream'),
                    ),
                    ButtonSegment(
                      value: ProviderType.m3u,
                      label: Text('M3U URL'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: state.busy
                      ? null
                      : (s) {
                          setState(() => _type = s.single);
                          controller.formChanged();
                        },
                ),
                const SizedBox(height: 24),
                if (_type == ProviderType.xtream) ...[
                  TextField(
                    key: const Key('setup.host'),
                    controller: _host,
                    decoration: const InputDecoration(
                      labelText: 'Host',
                      hintText: 'example.com:8080',
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('setup.username'),
                    controller: _username,
                    decoration: const InputDecoration(labelText: 'Username'),
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('setup.password'),
                    controller: _password,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                ] else
                  TextField(
                    key: const Key('setup.playlistUrl'),
                    controller: _playlistUrl,
                    decoration: const InputDecoration(
                      labelText: 'Playlist URL',
                      hintText: 'https://example.com/playlist.m3u',
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: config == null || state.busy
                          ? null
                          : () => controller.testConnection(config),
                      icon: state.testing
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textPrimary,
                              ),
                            )
                          : const Icon(Icons.network_check),
                      label: const Text('Test connection'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: config == null || state.busy
                          ? null
                          : () => _save(config),
                      child: const Text('Save'),
                    ),
                  ],
                ),
                if (state.result case final result?) ...[
                  const SizedBox(height: 16),
                  _StatusMessage(ok: result.ok, message: result.message),
                ],
                if (state.saveError case final error?) ...[
                  const SizedBox(height: 16),
                  _StatusMessage(ok: false, message: error),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          color: ok ? AppColors.success : AppColors.live,
        ),
        title: Text(message),
      ),
    );
  }
}
