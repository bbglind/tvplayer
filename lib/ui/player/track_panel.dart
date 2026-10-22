import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// Subtitle (with "Off") and audio track choice, from mpv's track list.
class TrackPanel extends StatelessWidget {
  const TrackPanel({
    super.key,
    required this.tracks,
    required this.audioId,
    required this.subtitleId,
    required this.onSubtitle,
    required this.onAudio,
    this.onClose,
  });

  final List<MediaTrack> tracks;
  final int? audioId;
  final int? subtitleId;

  /// Called with a subtitle track id, or null for off.
  final ValueChanged<int?> onSubtitle;
  final ValueChanged<int> onAudio;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subs = [
      for (final t in tracks)
        if (t.type == TrackType.subtitle) t,
    ];
    final audio = [
      for (final t in tracks)
        if (t.type == TrackType.audio) t,
    ];
    final subLabels = trackLabels(subs);
    final audioLabels = trackLabels(audio);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    Widget option(String label, bool selected, VoidCallback onTap, Key key) =>
        ListTile(
          key: key,
          dense: true,
          selected: selected,
          leading: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
          ),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: onTap,
        );
    return Material(
      key: const Key('player.tracks'),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(child: header('Subtitles')),
              if (onClose != null)
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
            ],
          ),
          option(
            'Off',
            subtitleId == null,
            () => onSubtitle(null),
            const Key('player.sub.off'),
          ),
          for (final t in subs)
            option(
              subLabels[t.id]!,
              t.id == subtitleId,
              () => onSubtitle(t.id),
              Key('player.sub.${t.id}'),
            ),
          header('Audio'),
          if (audio.isEmpty)
            const ListTile(dense: true, title: Text('No audio tracks yet')),
          for (final t in audio)
            option(
              audioLabels[t.id]!,
              t.id == audioId,
              () => onAudio(t.id),
              Key('player.audio.${t.id}'),
            ),
        ],
      ),
    );
  }
}
