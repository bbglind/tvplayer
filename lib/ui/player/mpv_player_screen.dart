import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../format.dart';
import '../../player/mpv/external_mpv_player.dart';
import '../../player/mpv/video_embed.dart';
import '../../state/providers.dart';

enum _Mode {
  /// Asking the native side for an X11 window.
  embedding,

  /// mpv draws into the native video area of this screen.
  embedded,

  /// mpv has its own window; this screen only shows its status.
  external,
}

/// Plays one live channel with mpv: embedded in the app window on X11, in a
/// separate mpv window otherwise. Leaving the screen closes mpv; mpv exiting
/// leaves the screen.
class MpvPlayerScreen extends ConsumerStatefulWidget {
  const MpvPlayerScreen({super.key, required this.channel});

  final LiveStream channel;

  @override
  ConsumerState<MpvPlayerScreen> createState() => _MpvPlayerScreenState();
}

class _MpvPlayerScreenState extends ConsumerState<MpvPlayerScreen> {
  late final ExternalMpvPlayer _player = ref.read(externalMpvProvider);
  late final VideoEmbed? _embed = ref.read(embedMpvProvider)
      ? ref.read(videoEmbedProvider)
      : null;
  late _Mode _mode = _embed == null ? _Mode.external : _Mode.embedding;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Uri? _url;
  int? _session;
  bool _fullscreen = false;
  double? _seekDragValue;

  @override
  void initState() {
    super.initState();
    _url = ref.read(liveSourceProvider)?.streamUrl(widget.channel);
    if (_url == null) return;
    _player.addListener(_onChange);
    if (_embed case final embed?) {
      _subscriptions.addAll([
        embed.doubleClicks.listen((_) => _setFullscreen(!_fullscreen)),
        embed.fullscreenChanges.listen((v) {
          if (mounted) setState(() => _fullscreen = v);
        }),
      ]);
    }
    unawaited(_start(_url!));
  }

  Future<void> _start(Uri url) async {
    int? wid;
    if (_embed case final embed?) {
      try {
        wid = await embed.create();
      } on VideoEmbedException catch (e) {
        debugPrint(
          'Embedding mpv not possible (${e.reason}); '
          'using a separate mpv window.',
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _mode = wid == null ? _Mode.external : _Mode.embedded;
      _session = _player.open(url, title: widget.channel.name, wid: wid);
    });
    if (wid == null) unawaited(_embed?.hide());
  }

  bool get _isMine => _session != null && _player.state.session == _session;

  bool get _showVideo =>
      _mode != _Mode.external &&
      !(_isMine && _player.state.status == ExternalPlayerStatus.failed);

  void _onChange() {
    if (!_isMine || !mounted) return;
    switch (_player.state.status) {
      case ExternalPlayerStatus.exited
          when ModalRoute.of(context)?.isCurrent ?? false:
        Navigator.of(context).pop();
      case ExternalPlayerStatus.failed:
        // Show the error where the video was.
        _setFullscreen(false);
        unawaited(_embed?.hide());
      default:
    }
  }

  void _setFullscreen(bool value) {
    if (value == _fullscreen || _mode != _Mode.embedded) return;
    setState(() => _fullscreen = value);
    unawaited(_embed?.setFullscreen(value));
  }

  void _onVideoRect(Rect rect) {
    if (mounted && _showVideo) unawaited(_embed?.setRect(rect));
  }

  @override
  void dispose() {
    _player.removeListener(_onChange);
    for (final s in _subscriptions) {
      s.cancel();
    }
    if (_embed case final embed?) {
      unawaited(embed.hide());
      if (_fullscreen) unawaited(embed.setFullscreen(false));
    }
    if (_session case final session?) {
      unawaited(_player.stop(session: session));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_url == null) {
      body = const Center(child: Text('No provider configured'));
    } else {
      body = ListenableBuilder(
        listenable: _player,
        builder: (context, _) {
          final state = _isMine ? _player.state : const ExternalPlaybackState();
          return _showVideo
              ? _buildEmbedded(context, state)
              : _buildStatus(context, state);
        },
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _setFullscreen(false),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: _showVideo ? Colors.black : null,
          appBar: _fullscreen ? null : AppBar(title: Text(widget.channel.name)),
          body: body,
        ),
      ),
    );
  }

  Widget _buildEmbedded(BuildContext context, ExternalPlaybackState state) {
    // The native area covers the placeholder; Flutter can't draw over it,
    // so controls go below.
    final video = _RectReporter(
      onRect: _onVideoRect,
      child: const ColoredBox(
        key: Key('mpv.video'),
        color: Colors.black,
        child: SizedBox.expand(),
      ),
    );
    if (_fullscreen) return video;
    return Column(
      children: [
        Expanded(child: video),
        _buildControls(context, state),
      ],
    );
  }

  Widget _buildControls(BuildContext context, ExternalPlaybackState state) {
    final starting =
        _mode == _Mode.embedding ||
        state.status == ExternalPlayerStatus.starting;
    return Material(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: state.paused ? 'Resume' : 'Pause',
              icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
              onPressed: starting ? null : _player.togglePause,
            ),
            Expanded(
              child: starting
                  ? const LinearProgressIndicator()
                  : _buildSeekBar(context, state),
            ),
            const SizedBox(width: 16),
            _DropReadout(state),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Fullscreen (double-click video, Esc to leave)',
              icon: const Icon(Icons.fullscreen),
              onPressed: starting ? null : () => _setFullscreen(true),
            ),
            IconButton(
              tooltip: 'Stop',
              icon: const Icon(Icons.stop),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar(BuildContext context, ExternalPlaybackState state) {
    final position = state.position ?? Duration.zero;
    final duration = state.duration;
    if (duration == null || duration <= Duration.zero) {
      return Text(
        formatDuration(position),
        key: const Key('mpv.position'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final max = duration.inMilliseconds.toDouble();
    final value = (_seekDragValue ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      max,
    );
    return Row(
      children: [
        Text(
          formatDuration(Duration(milliseconds: value.round())),
          key: const Key('mpv.position'),
        ),
        Expanded(
          child: Slider(
            value: value,
            max: max,
            onChanged: (v) => setState(() => _seekDragValue = v),
            onChangeEnd: (v) async {
              await _player.seek(Duration(milliseconds: v.round()));
              if (mounted) setState(() => _seekDragValue = null);
            },
          ),
        ),
        Text(formatDuration(duration)),
      ],
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
                key: const Key('mpv.position'),
              ),
            ],
            if (state.status == ExternalPlayerStatus.playing) ...[
              const SizedBox(height: 8),
              _DropReadout(state),
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

/// mpv's dropped-frame counters; mpv's own stats overlay isn't reachable
/// when embedded (its key bindings are off).
class _DropReadout extends StatelessWidget {
  const _DropReadout(this.state);

  final ExternalPlaybackState state;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatDrops(state.voDrops, state.decoderDrops),
      key: const Key('mpv.drops'),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontFamily: 'monospace'),
    );
  }
}

/// Reports its child's rectangle in logical pixels of the app view whenever
/// it changes (window resize, fullscreen, route transitions).
class _RectReporter extends SingleChildRenderObjectWidget {
  const _RectReporter({required this.onRect, super.child});

  final ValueChanged<Rect> onRect;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRectReporter(onRect);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRectReporter renderObject,
  ) => renderObject.onRect = onRect;
}

class _RenderRectReporter extends RenderProxyBox {
  _RenderRectReporter(this.onRect);

  ValueChanged<Rect> onRect;
  Rect? _last;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final rect = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    if (rect == _last) return;
    _last = rect;
    SchedulerBinding.instance.addPostFrameCallback((_) => onRect(rect));
  }
}
