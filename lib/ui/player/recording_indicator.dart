import 'package:flutter/material.dart';

import '../../format.dart';
import '../../state/recording_controller.dart';
import '../theme/app_colors.dart';

/// "● REC 0:12:34" while recording: a `live` dot and the elapsed time (it
/// says REC, so it doesn't rely on colour). As a [pill] on a dark tile, for
/// the corner of the fullscreen video.
class RecordingIndicator extends StatelessWidget {
  const RecordingIndicator({
    super.key,
    required this.recording,
    this.pill = false,
  });

  final ActiveRecording recording;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: AppColors.live,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'REC ${formatElapsed(recording.elapsed)}',
          key: const Key('player.recordingTime'),
          maxLines: 1,
          style: style,
        ),
      ],
    );
    if (!pill) return content;
    return Container(
      key: const Key('player.recordingPill'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.scrim.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: content,
    );
  }
}
