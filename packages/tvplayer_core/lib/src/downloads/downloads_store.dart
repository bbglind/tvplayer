import 'dart:convert';
import 'dart:io';

import 'download_item.dart';

/// Persists the downloads list of one provider account.
abstract interface class DownloadsStore {
  /// The saved entries in queue order; empty when none are saved or they
  /// can't be read.
  Future<List<DownloadItem>> load();

  Future<void> save(List<DownloadItem> items);
}

/// [DownloadsStore] in a JSON file.
class JsonFileDownloadsStore implements DownloadsStore {
  JsonFileDownloadsStore(this.file);

  final File file;

  @override
  Future<List<DownloadItem>> load() async {
    try {
      if (!await file.exists()) return const [];
      final json = jsonDecode(await file.readAsString());
      final list = json is Map ? json['items'] : null;
      if (list is! List) return const [];
      return [for (final e in list) ?DownloadItem.fromJson(e)];
    } on Exception {
      return const [];
    }
  }

  @override
  Future<void> save(List<DownloadItem> items) async {
    await file.parent.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'items': [for (final i in items) i.toJson()],
      }),
    );
    await tmp.rename(file.path);
  }
}
