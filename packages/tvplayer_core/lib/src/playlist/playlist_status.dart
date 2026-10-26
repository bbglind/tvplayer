import 'dart:convert';
import 'dart:io';

import '../util/json.dart';

/// A part of a provider's playlist that is downloaded on its own.
enum PlaylistPart {
  channels,
  movies,
  series,
  guide;

  static PlaylistPart? byName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// When the playlist is refreshed without being asked. The app has no
/// background service: timed choices run only while it is open, and on
/// start when the time has passed.
enum AutoRefresh {
  off,
  onStart,
  every6Hours,
  daily;

  static const defaultMode = daily;

  /// How long a part stays fresh; null when not timed.
  Duration? get interval => switch (this) {
    every6Hours => const Duration(hours: 6),
    daily => const Duration(days: 1),
    off || onStart => null,
  };

  static AutoRefresh? byName(String? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// The last download of one [PlaylistPart].
final class PartStatus {
  const PartStatus({this.updatedAt, this.failedAt, this.error});

  /// The last successful download (UTC); null when never.
  final DateTime? updatedAt;

  /// The last failed download (UTC), when it came after [updatedAt].
  final DateTime? failedAt;

  /// Why it failed, in words for the user. Never contains URLs or
  /// credentials.
  final String? error;

  static const empty = PartStatus();

  /// Whether the last attempt failed.
  bool get failed => failedAt != null;

  PartStatus succeeded(DateTime at) => PartStatus(updatedAt: at);

  PartStatus failedWith(DateTime at, String message) =>
      PartStatus(updatedAt: updatedAt, failedAt: at, error: message);

  Map<String, Object?> toJson() => {
    'updated': ?updatedAt?.millisecondsSinceEpoch,
    'failed': ?failedAt?.millisecondsSinceEpoch,
    'error': ?error,
  };

  static PartStatus fromJson(Object? json) {
    final map = readMap(json) ?? const {};
    DateTime? time(String key) => switch (readInt(map[key])) {
      final ms? => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      null => null,
    };
    final failedAt = time('failed');
    return PartStatus(
      updatedAt: time('updated'),
      failedAt: failedAt,
      error: failedAt == null ? null : readString(map['error']),
    );
  }
}

/// The automatic refresh choice and the last download of each part, for
/// one provider.
final class PlaylistStatus {
  const PlaylistStatus({
    this.autoRefresh = AutoRefresh.defaultMode,
    this.parts = const {},
  });

  final AutoRefresh autoRefresh;
  final Map<PlaylistPart, PartStatus> parts;

  static const empty = PlaylistStatus();

  PartStatus part(PlaylistPart p) => parts[p] ?? PartStatus.empty;

  PlaylistStatus withPart(PlaylistPart p, PartStatus status) =>
      PlaylistStatus(autoRefresh: autoRefresh, parts: {...parts, p: status});

  PlaylistStatus withAutoRefresh(AutoRefresh mode) =>
      PlaylistStatus(autoRefresh: mode, parts: parts);

  /// These with [p] last updated at [at] when nothing is known about it
  /// yet, e.g. from a cache made before the status was kept.
  PlaylistStatus seeded(PlaylistPart p, DateTime at) {
    final current = part(p);
    if (current.updatedAt != null || current.failed) return this;
    return withPart(p, PartStatus(updatedAt: at));
  }

  Map<String, Object?> toJson() => {
    'autoRefresh': autoRefresh.name,
    'parts': {for (final e in parts.entries) e.key.name: e.value.toJson()},
  };

  /// Lenient inverse of [toJson]: unknown parts are dropped, and missing
  /// ones are never updated.
  static PlaylistStatus fromJson(Object? json) {
    final map = readMap(json) ?? const {};
    final parts = readMap(map['parts']) ?? const {};
    return PlaylistStatus(
      autoRefresh:
          AutoRefresh.byName(readString(map['autoRefresh'])) ??
          AutoRefresh.defaultMode,
      parts: {
        for (final e in parts.entries)
          ?PlaylistPart.byName(e.key): PartStatus.fromJson(e.value),
      },
    );
  }
}

/// Persists [PlaylistStatus].
abstract interface class PlaylistStatusStore {
  /// The saved status, or [PlaylistStatus.empty] when there is none or it
  /// can't be read.
  Future<PlaylistStatus> load();

  Future<void> save(PlaylistStatus status);
}

/// [PlaylistStatusStore] in a JSON [file].
class JsonFilePlaylistStatusStore implements PlaylistStatusStore {
  JsonFilePlaylistStatusStore(this.file);

  final File file;

  @override
  Future<PlaylistStatus> load() async {
    try {
      if (!await file.exists()) return PlaylistStatus.empty;
      return PlaylistStatus.fromJson(jsonDecode(await file.readAsString()));
    } on Exception {
      return PlaylistStatus.empty;
    }
  }

  @override
  Future<void> save(PlaylistStatus status) async {
    await file.parent.create(recursive: true);
    // Write then rename, so a crash never leaves a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(status.toJson()));
    await tmp.rename(file.path);
  }
}
