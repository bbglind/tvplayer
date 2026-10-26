import 'package:flutter/material.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'player_hint.dart';

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
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Text(text.toUpperCase(), style: theme.textTheme.labelMedium),
    );
    Widget option(
      String label,
      String tooltip,
      bool selected,
      VoidCallback onTap,
      Key key,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: PlayerTooltip(
        message: tooltip,
        side: true,
        child: FocusRing(
          radius: AppRadius.small,
          inset: true,
          child: ListTile(
            key: key,
            dense: true,
            selected: selected,
            leading: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? AppColors.accent : AppColors.textMuted,
            ),
            title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: onTap,
          ),
        ),
      ),
    );
    return Material(
      key: const Key('player.tracks'),
      color: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        children: [
          Row(
            children: [
              Expanded(child: header('Subtitles')),
              if (onClose != null)
                PlayerTooltip(
                  message: 'Close (Esc)',
                  side: true,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ),
            ],
          ),
          option(
            'Off',
            'Turn subtitles off',
            subtitleId == null,
            () => onSubtitle(null),
            const Key('player.sub.off'),
          ),
          for (final t in subs)
            option(
              subLabels[t.id]!,
              'Show these subtitles',
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
              'Play this audio track',
              t.id == audioId,
              () => onAudio(t.id),
              Key('player.audio.${t.id}'),
            ),
        ],
      ),
    );
  }
}
