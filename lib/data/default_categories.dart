import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

/// Whether this install gives new accounts the default categories, and which
/// accounts (by [providerKey]) already had their turn. Decided once, on the
/// first start with this feature; anything uncertain means no defaults.
final class DefaultCategoriesMarker {
  const DefaultCategoriesMarker({
    required this.eligible,
    this.seeded = const {},
  });

  final bool eligible;
  final Set<String> seeded;

  DefaultCategoriesMarker withSeeded(String key) =>
      DefaultCategoriesMarker(eligible: eligible, seeded: {...seeded, key});

  Map<String, Object?> toJson() => {
    'eligible': eligible,
    'seeded': seeded.toList(),
  };

  static DefaultCategoriesMarker fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final seeded = map['seeded'];
    return DefaultCategoriesMarker(
      eligible: map['eligible'] == true,
      seeded: {
        if (seeded is List)
          for (final key in seeded)
            if (key is String) key,
      },
    );
  }
}

abstract interface class DefaultCategoriesStore {
  /// The marker; not eligible when there is none or it can't be read.
  Future<DefaultCategoriesMarker> load();

  Future<void> save(DefaultCategoriesMarker marker);
}

/// [DefaultCategoriesStore] in `default_categories.json` in the app support
/// directory.
class FileDefaultCategoriesStore implements DefaultCategoriesStore {
  FileDefaultCategoriesStore([Future<Directory> Function()? root])
    : _root = root ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _root;

  /// What an install that ran before leaves in the app support directory.
  static const _existingData = [
    'settings.json',
    'favourites',
    'watch',
    'playlist',
    'downloads',
    'sync',
    'sync_backup',
    'tmdb.sqlite',
    'skip.sqlite',
  ];

  Future<File> get _file async =>
      File('${(await _root()).path}/default_categories.json');

  /// Writes the marker if there is none: eligible only when none of the
  /// app's data exists. Run before anything creates files in the directory.
  /// On failure there is no marker, which means not eligible.
  Future<void> prepare() async {
    try {
      final file = await _file;
      if (await file.exists()) return;
      final root = (await _root()).path;
      var eligible = true;
      for (final name in _existingData) {
        final type = await FileSystemEntity.type('$root/$name');
        if (type != FileSystemEntityType.notFound) eligible = false;
      }
      await save(DefaultCategoriesMarker(eligible: eligible));
    } catch (e) {
      debugPrint('Could not write the install marker (${e.runtimeType})');
    }
  }

  @override
  Future<DefaultCategoriesMarker> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) {
        return const DefaultCategoriesMarker(eligible: false);
      }
      return DefaultCategoriesMarker.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } on Exception {
      return const DefaultCategoriesMarker(eligible: false);
    }
  }

  @override
  Future<void> save(DefaultCategoriesMarker marker) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(marker.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}
