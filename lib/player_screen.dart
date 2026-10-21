import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'format.dart';

/// hwdec modes offered in the UI. Applied via the mpv `hwdec` property.
const _hwdecModes = ['auto-safe', 'vaapi', 'vaapi-copy', 'no'];
const _defaultHwdec = 'auto-safe';

/// Maximum number of log lines kept in memory.
const _maxLogLines = 500;

class _LogEntry {
  _LogEntry(this.level, this.text);

  final String level;
  final String text;
  final DateTime time = DateTime.now();

  bool get isError => level == 'error' || level == 'fatal';
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'tvplayer',
      logLevel: MPVLogLevel.warn,
    ),
  );
  late final VideoController _controller = VideoController(
    _player,
    configuration: const VideoControllerConfiguration(hwdec: _defaultHwdec),
  );

  final _urlController = TextEditingController();
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _logs = <_LogEntry>[];

  String _hwdec = _defaultHwdec;
  bool _showOverlay = true;
  bool _seekable = false;
  double? _seekDragValue;
  String? _lastError;
  Map<String, String> _props = const {};
  Timer? _pollTimer;

  NativePlayer? get _native {
    final platform = _player.platform;
    return platform is NativePlayer ? platform : null;
  }

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.stream.log.listen((log) {
        _addLog(log.level, '[${log.prefix}] ${log.text.trim()}');
      }),
      _player.stream.error.listen((error) {
        _addLog('error', error);
        setState(() => _lastError = error);
      }),
      _player.stream.playing.listen((playing) {
        if (playing) {
          _pollTimer ??= Timer.periodic(
            const Duration(seconds: 1),
            (_) => _refreshProperties(),
          );
        } else {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
        _refreshProperties();
      }),
      _player.stream.completed.listen((completed) {
        if (completed) _addLog('info', 'Playback ended');
      }),
    ]);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _urlController.dispose();
    _player.dispose();
    super.dispose();
  }

  void _addLog(String level, String text) {
    if (!mounted) return;
    setState(() {
      _logs.add(_LogEntry(level, text));
      if (_logs.length > _maxLogLines) {
        _logs.removeRange(0, _logs.length - _maxLogLines);
      }
    });
  }

  Future<void> _play() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _lastError = 'Enter a stream URL first');
      return;
    }
    setState(() {
      _lastError = null;
      _props = const {};
      _seekable = false;
    });
    // Don't log the URL itself: it may contain credentials.
    _addLog('info', 'Opening stream');
    try {
      await _player.open(Media(url));
    } catch (e) {
      _addLog('error', 'open failed: $e');
      setState(() => _lastError = 'open failed: $e');
    }
  }

  Future<void> _setHwdec(String value) async {
    setState(() => _hwdec = value);
    final native = _native;
    if (native == null) {
      _addLog('error', 'hwdec: native player not available');
      return;
    }
    try {
      await native.setProperty('hwdec', value);
      _addLog('info', 'hwdec set to $value');
    } catch (e) {
      _addLog('error', 'setting hwdec failed: $e');
    }
    await _refreshProperties();
  }

  Future<void> _refreshProperties() async {
    final native = _native;
    if (native == null || !mounted) return;
    const names = [
      'hwdec',
      'hwdec-current',
      'video-codec',
      'audio-codec',
      'video-params/w',
      'video-params/h',
      'video-params/pixelformat',
      'video-params/hw-pixelformat',
      'container-fps',
      'estimated-vf-fps',
      'frame-drop-count',
      'decoder-frame-drop-count',
      'seekable',
    ];
    final values = <String, String>{};
    try {
      for (final name in names) {
        values[name] = await native.getProperty(name);
      }
    } catch (e) {
      // Player may be disposed mid-poll; nothing to show then.
      return;
    }
    if (!mounted) return;
    setState(() {
      _props = values;
      _seekable = values['seekable'] == 'yes';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildUrlBar(),
            if (_lastError != null) _buildErrorBanner(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Video(
                      controller: _controller,
                      controls: NoVideoControls,
                    ),
                  ),
                  if (_showOverlay)
                    Positioned(top: 8, left: 8, child: _buildDebugOverlay()),
                ],
              ),
            ),
            _buildControls(),
            _buildLogPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Stream URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _play(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
          const SizedBox(width: 16),
          const Text('hwdec'),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _hwdec,
            items: [
              for (final mode in _hwdecModes)
                DropdownMenuItem(value: mode, child: Text(mode)),
            ],
            onChanged: (v) {
              if (v != null) _setHwdec(v);
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Toggle debug overlay',
            isSelected: _showOverlay,
            icon: const Icon(Icons.bug_report_outlined),
            selectedIcon: const Icon(Icons.bug_report),
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(_lastError!)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _lastError = null),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugOverlay() {
    String p(String name) {
      final v = _props[name];
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
        '${formatResolution(_props['video-params/w'] ?? '', _props['video-params/h'] ?? '')}'
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
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final (k, v) in rows) Text('${k.padRight(18)} $v')],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            initialData: _player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                tooltip: playing ? 'Pause' : 'Resume',
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: _player.playOrPause,
              );
            },
          ),
          Expanded(child: _buildSeekBar()),
          const SizedBox(width: 8),
          StreamBuilder<double>(
            stream: _player.stream.volume,
            initialData: _player.state.volume,
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
                      onChanged: _player.setVolume,
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
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = _player.state.duration;
        final canSeek = _seekable && duration > Duration.zero;
        if (!canSeek) {
          return Text(
            '${formatDuration(position)}  (not seekable)',
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
                  await _player.seek(Duration(milliseconds: v.round()));
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
                Text('Log (${_logs.length})'),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(_logs.clear),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _logs.length,
              itemBuilder: (context, i) {
                final entry = _logs[_logs.length - 1 - i];
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
