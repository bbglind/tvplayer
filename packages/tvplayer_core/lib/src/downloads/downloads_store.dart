import 'dart:convert';
import 'dart:io';

import 'download_item.dart';

/// Persists the downloads list of one provider account.
abstract interface class DownloadsStore {
  /// The saved entries in queue order, and whether the user paused the
  /// queue; no entries when none are saved or they can't be read.
  Future<({List<DownloadItem> items, bool paused})> load();

  Future<void> save(List<DownloadItem> items, {bool paused = false});
}

/// [DownloadsStore] in a JSON file.
class JsonFileDownloadsStore implements DownloadsStore {
  JsonFileDownloadsStore(this.file);

  final File file;

  @override
  Future<({List<DownloadItem> items, bool paused})> load() async {
    const none = (items: <DownloadItem>[], paused: false);
    try {
      if (!await file.exists()) return none;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return none;
      final list = json['items'];
      if (list is! List) return none;
      return (
        items: [for (final e in list) ?DownloadItem.fromJson(e)],
        paused: json['paused'] == true,
      );
    } on Exception {
      return none;
    }
  }

  @override
  Future<void> save(List<DownloadItem> items, {bool paused = false}) async {
    await file.parent.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'items': [for (final i in items) i.toJson()],
        if (paused) 'paused': true,
      }),
    );
    await tmp.rename(file.path);
  }
}
