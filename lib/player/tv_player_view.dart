import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../format.dart';
import '../ui/theme/app_colors.dart';
import 'player_session.dart';

/// Reusable video player: video, basic controls and an error banner. With
/// [showDebug], adds the mpv property overlay, an hwdec selector and the log.
/// Only [fixedLength] content gets a seek bar.
///
/// Never shows the stream URL.
class TvPlayerView extends StatefulWidget {
  const TvPlayerView({
    super.key,
    required this.url,
    required this.hwdec,
    this.hwdecModes = const [],
    this.onHwdecChanged,
    this.showDebug = false,
    this.fixedLength = false,
  });

  /// Contains credentials: never display or log it.
  final Uri url;
  final String hwdec;
  final List<String> hwdecModes;
  final ValueChanged<String>? onHwdecChanged;
  final bool showDebug;

  /// Whether the content has a fixed length (a movie or an episode). Live
  /// streams don't: mpv's duration there is only what is buffered.
  final bool fixedLength;

  @override
  State<TvPlayerView> createState() => _TvPlayerViewState();
}

class _TvPlayerViewState extends State<TvPlayerView> {
  late final PlayerSession _session = PlayerSession(hwdec: widget.hwdec)
    ..debugPolling = widget.showDebug;
  double? _seekDragValue;

  @override
  void initState() {
    super.initState();
    _session.open(widget.url);
  }

  @override
  void didUpdateWidget(TvPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) _session.open(widget.url);
    if (widget.hwdec != oldWidget.hwdec) _session.setHwdec(widget.hwdec);
    if (widget.showDebug != oldWidget.showDebug) {
      _session.debugPolling = widget.showDebug;
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) => Column(
        children: [
          if (_session.lastError != null) _buildErrorBanner(),
          if (widget.showDebug) _buildDebugBar(),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Video(
                    controller: _session.videoController,
                    controls: NoVideoControls,
                  ),
                ),
                if (widget.showDebug)
                  Positioned(top: 8, left: 8, child: _buildDebugOverlay()),
              ],
            ),
          ),
          _buildControls(),
          if (widget.showDebug) _buildLogPanel(),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      color: AppColors.live,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.onAccent),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              _session.lastError!,
              style: const TextStyle(color: AppColors.onAccent),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss the error',
            icon: const Icon(Icons.close, color: AppColors.onAccent),
            onPressed: _session.dismissError,
          ),
        ],
      ),
    );
  }

  Widget _buildDebugBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Text('hwdec'),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Hardware decoding',
            child: DropdownButton<String>(
              value: widget.hwdec,
              items: [
                for (final mode in {...widget.hwdecModes, widget.hwdec})
                  DropdownMenuItem(value: mode, child: Text(mode)),
              ],
              onChanged: widget.onHwdecChanged == null
                  ? null
                  : (v) {
                      if (v != null) widget.onHwdecChanged!(v);
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugOverlay() {
    final props = _session.properties;
    String p(String name) {
      final v = props[name];
      return (v == null || v.isEmpty) ? '-' : v;
    }

    final hwPixfmt = p('video-params/hw-pixelformat');
    final rows = <(String, String)>[
      ('hwdec (requested)', p('hwdec')),
      ('hwdec-current', p('hwdec-current')),
      ('video-codec', p('video-codec')),
      ('audio-codec', p('audio-codec')),
      (
        'video-params',
        '${formatResolution(props['video-params/w'] ?? '', props['video-params/h'] ?? '')}'
            ' ${p('video-params/pixelformat')}'
            '${hwPixfmt == '-' ? '' : ' (hw: $hwPixfmt)'}',
      ),
      ('container-fps', p('container-fps')),
      ('estimated-vf-fps', p('estimated-vf-fps')),
      (
        'dropped (vo/dec)',
        '${p('frame-drop-count')} / ${p('decoder-frame-drop-count')}',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.scrim.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: AppColors.textPrimary,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final (k, v) in rows) Text('${k.padRight(18)} $v')],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final player = _session.player;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                tooltip: playing ? 'Pause' : 'Resume',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: player.playOrPause,
              );
            },
          ),
          Expanded(
            child: widget.fixedLength
                ? _buildSeekBar()
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          StreamBuilder<double>(
            stream: player.stream.volume,
            initialData: player.state.volume,
            builder: (context, snapshot) {
              final volume = snapshot.data ?? 100;
              return Row(
                children: [
                  Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
                  SizedBox(
                    width: 140,
                    child: Slider(
                      value: volume.clamp(0, 100),
                      max: 100,
                      onChanged: player.setVolume,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar() {
    final player = _session.player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player.state.duration;
        final canSeek = _session.seekable && duration > Duration.zero;
        if (!canSeek) {
          return Text(
            formatDuration(position),
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        final max = duration.inMilliseconds.toDouble();
        final value = (_seekDragValue ?? position.inMilliseconds.toDouble())
            .clamp(0.0, max);
        return Row(
          children: [
            Text(formatDuration(Duration(milliseconds: value.round()))),
            Expanded(
              child: Slider(
                value: value,
                max: max,
                onChanged: (v) => setState(() => _seekDragValue = v),
                onChangeEnd: (v) async {
                  await player.seek(Duration(milliseconds: v.round()));
                  if (mounted) setState(() => _seekDragValue = null);
                },
              ),
            ),
            Text(formatDuration(duration)),
          ],
        );
      },
    );
  }

  Widget _buildLogPanel() {
    final scheme = Theme.of(context).colorScheme;
    final logs = _session.logs;
    return Container(
      height: 140,
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text('Log (${logs.length})'),
                const Spacer(),
                Tooltip(
                  message: 'Clear the log',
                  child: TextButton(
                    onPressed: _session.clearLogs,
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final entry = logs[logs.length - 1 - i];
                final t = entry.time;
                final ts =
                    '${t.hour.toString().padLeft(2, '0')}:'
                    '${t.minute.toString().padLeft(2, '0')}:'
                    '${t.second.toString().padLeft(2, '0')}';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SelectableText(
                    '$ts ${entry.level.padRight(5)} ${entry.text}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: entry.isError ? scheme.error : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
