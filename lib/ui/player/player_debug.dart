import 'package:flutter/material.dart';

import '../../format.dart';
import '../../player/player_session.dart';
import '../theme/app_colors.dart';

/// The media_kit player's debug info (Settings › Player › "Player debug
/// info"): mpv properties, the hardware decoding mode and the log.
///
/// Never shows the stream URL: the session redacts it.
class PlayerDebugPanel extends StatelessWidget {
  const PlayerDebugPanel({
    super.key,
    required this.session,
    required this.hwdecModes,
    required this.onHwdecChanged,
  });

  final PlayerSession session;
  final List<String> hwdecModes;
  final ValueChanged<String> onHwdecChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        key: const Key('player.debug'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('hwdec'),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Hardware decoding',
                  child: DropdownButton<String>(
                    value: session.hwdec,
                    items: [
                      for (final mode in {...hwdecModes, session.hwdec})
                        DropdownMenuItem(value: mode, child: Text(mode)),
                    ],
                    onChanged: (v) {
                      if (v != null) onHwdecChanged(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _Properties(session.properties),
          ),
          const SizedBox(height: 8),
          Expanded(child: _Log(session)),
        ],
      ),
    );
  }
}

class _Properties extends StatelessWidget {
  const _Properties(this.props);

  final Map<String, String> props;

  @override
  Widget build(BuildContext context) {
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
    return DefaultTextStyle(
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: AppColors.textPrimary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final (k, v) in rows) Text('${k.padRight(18)} $v')],
      ),
    );
  }
}

class _Log extends StatelessWidget {
  const _Log(this.session);

  final PlayerSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logs = session.logs;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text('Log (${logs.length})'),
                const Spacer(),
                Tooltip(
                  message: 'Clear the log',
                  child: TextButton(
                    onPressed: session.clearLogs,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
