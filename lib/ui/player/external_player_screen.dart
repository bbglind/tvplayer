import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../player/mpv/external_mpv_player.dart';
import '../../state/providers.dart';

/// Plays one live channel in an external mpv window and shows its status.
/// Leaving the screen closes mpv; mpv exiting leaves the screen.
class ExternalPlayerScreen extends ConsumerStatefulWidget {
  const ExternalPlayerScreen({super.key, required this.channel});

  final LiveStream channel;

  @override
  ConsumerState<ExternalPlayerScreen> createState() =>
      _ExternalPlayerScreenState();
}

class _ExternalPlayerScreenState extends ConsumerState<ExternalPlayerScreen> {
  late final ExternalMpvPlayer _player = ref.read(externalMpvProvider);
  int? _session;

  @override
  void initState() {
    super.initState();
    final source = ref.read(liveSourceProvider);
    if (source != null) {
      _session = _player.open(
        source.streamUrl(widget.channel),
        title: widget.channel.name,
      );
    }
    _player.addListener(_onChange);
  }

  void _onChange() {
    final state = _player.state;
    if (state.session == _session &&
        state.status == ExternalPlayerStatus.exited &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onChange);
    if (_session case final session?) {
      unawaited(_player.stop(session: session));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: _session == null
          ? const Center(child: Text('No provider configured'))
          : ListenableBuilder(
              listenable: _player,
              builder: (context, _) => _buildStatus(context, _player.state),
            ),
    );
  }

  Widget _buildStatus(BuildContext context, ExternalPlaybackState state) {
    final theme = Theme.of(context);
    final failed = state.status == ExternalPlayerStatus.failed;
    final (icon, title) = switch (state.status) {
      ExternalPlayerStatus.failed => (Icons.error_outline, 'Playback failed'),
      ExternalPlayerStatus.playing when state.paused => (
        Icons.pause_circle_outline,
        'Paused in mpv',
      ),
      ExternalPlayerStatus.playing => (
        Icons.open_in_new,
        'Playing in the mpv window',
      ),
      ExternalPlayerStatus.exited => (Icons.stop_circle_outlined, 'mpv closed'),
      _ => (Icons.hourglass_empty, 'Starting mpv…'),
    };
    final position = state.position;
    final duration = state.duration;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: failed ? theme.colorScheme.error : null,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleLarge),
            if (state.error case final error?) ...[
              const SizedBox(height: 8),
              SelectableText(error, textAlign: TextAlign.center),
            ],
            if (position != null) ...[
              const SizedBox(height: 8),
              Text(
                duration == null || duration == Duration.zero
                    ? formatDuration(position)
                    : '${formatDuration(position)} / '
                          '${formatDuration(duration)}',
                key: const Key('external.position'),
              ),
            ],
            const SizedBox(height: 16),
            failed
                ? FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to channels'),
                  )
                : FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
          ],
        ),
      ),
    );
  }
}
