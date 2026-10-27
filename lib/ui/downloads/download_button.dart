import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../state/downloads_controller.dart';
import '../../state/navigation.dart';
import '../theme/app_colors.dart';

/// "Download" on a details page: queues the item, then says how its
/// download is doing ("Downloading 45 %", "Downloaded"); once it is in the
/// list the button opens the Downloads page.
class DownloadButton extends ConsumerWidget {
  const DownloadButton({
    super.key,
    required this.watchKey,
    required this.onDownload,
  });

  /// The movie's or episode's watch key, which its download shares.
  final String watchKey;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(
      downloadsProvider.select((s) => s.forWatchKey(watchKey)),
    );
    if (item == null) {
      return OutlinedButton.icon(
        key: const Key('details.download'),
        onPressed: onDownload,
        icon: const Icon(Icons.download_outlined),
        label: const Text('Download'),
      );
    }
    final (label, icon) = downloadButtonState(item);
    return Tooltip(
      message: 'Open Downloads',
      child: OutlinedButton.icon(
        key: const Key('details.download'),
        onPressed: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          ref.read(appSectionProvider.notifier).select(AppSection.downloads);
        },
        icon: Icon(icon, color: item.isDone ? AppColors.success : null),
        label: Text(label),
      ),
    );
  }
}

/// The label and icon of a download's button.
(String, IconData) downloadButtonState(DownloadItem item) =>
    switch (item.status) {
      DownloadStatus.done => ('Downloaded', Icons.download_done),
      DownloadStatus.running => (
        switch (item.fraction) {
          final f? => 'Downloading ${(f * 100).floor()} %',
          null => 'Downloading',
        },
        Icons.downloading,
      ),
      DownloadStatus.queued ||
      DownloadStatus.waiting => ('Queued for download', Icons.schedule),
      DownloadStatus.paused => ('Download paused', Icons.pause_circle_outline),
      DownloadStatus.failed => ('Download failed', Icons.error_outline),
      DownloadStatus.recording => ('Recording', Icons.fiber_manual_record),
    };
