import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/archive_epg_repository.dart';
import '../data/errors.dart';
import 'providers.dart';

/// Where the past listing of one channel stands.
enum ArchiveStatus {
  /// Not asked for.
  none,

  /// Waiting or being downloaded.
  loading,

  /// The last download failed (see [ArchiveListingsController.retryAfter]).
  failed,

  /// Downloaded.
  loaded,
}

/// The past listings of the channels with replay, by [LiveStream.id].
@immutable
final class ArchiveListingsState {
  const ArchiveListingsState({
    this.entries = const {},
    this.loading = const {},
    this.failed = const {},
  });

  final Map<String, ArchiveEntry> entries;

  /// Channels waiting or being downloaded.
  final Set<String> loading;

  /// When each channel's last download failed.
  final Map<String, DateTime> failed;

  ArchiveStatus statusOf(String id) {
    if (loading.contains(id)) return ArchiveStatus.loading;
    if (failed.containsKey(id)) return ArchiveStatus.failed;
    if (entries.containsKey(id)) return ArchiveStatus.loaded;
    return ArchiveStatus.none;
  }
}

/// Downloads past listings (see [LiveSource.archiveListings]) of the
/// channels the TV guide shows further back than its XMLTV data, **one
/// request at a time**, and caches them on disk (see
/// [ArchiveEpgRepository]).
class ArchiveListingsController extends Notifier<ArchiveListingsState> {
  /// A cached listing is downloaded again when older than this.
  static const maxAge = Duration(hours: 12);

  /// After a failure a channel waits this long before it is tried again.
  static const retryAfter = Duration(minutes: 5);

  /// Programmes older than this are never kept (the longest archive).
  static const maxDays = 7;

  /// Saving waits this long for more downloads to finish.
  static const saveDelay = Duration(seconds: 2);

  final _queue = <LiveStream>[];
  String? _current;
  bool _running = false;
  int _generation = 0;
  Future<void>? _cacheRead;
  Timer? _save;

  @override
  ArchiveListingsState build() {
    final source = ref.watch(liveSourceProvider);
    final key = ref.watch(providerKeyProvider);
    final generation = ++_generation;
    _queue.clear();
    _current = null;
    // A download of the previous provider ends on its own.
    _running = false;
    ref.onDispose(() => _save?.cancel());
    if (source == null || key == null) {
      _cacheRead = null;
      return const ArchiveListingsState();
    }
    _cacheRead = _readCache(key, generation);
    return const ArchiveListingsState();
  }

  Future<void> _readCache(String key, int generation) async {
    final cached = await ref.read(archiveEpgRepositoryProvider).load(key);
    if (generation != _generation || !ref.mounted) return;
    final now = ref.read(clockProvider);
    state = ArchiveListingsState(
      entries: {..._pruned(cached, now), ...state.entries},
      loading: state.loading,
      failed: state.failed,
    );
  }

  /// [entries] without programmes older than [maxDays] and without
  /// listings that hold nothing any more.
  static Map<String, ArchiveEntry> _pruned(
    Map<String, ArchiveEntry> entries,
    DateTime now,
  ) {
    final earliest = now.subtract(const Duration(days: maxDays));
    return {
      for (final MapEntry(:key, :value) in entries.entries)
        if (value.programs.where((p) => p.stop.isAfter(earliest)).toList()
            case final kept when kept.isNotEmpty)
          key: ArchiveEntry(fetchedAt: value.fetchedAt, programs: kept),
    };
  }

  /// Wants the past listings of [channels], most wanted first. Replaces
  /// what was wanted before, so channels scrolled out of view are dropped;
  /// the one downloading finishes.
  void want(Iterable<LiveStream> channels) {
    _queue
      ..clear()
      ..addAll(channels.where(_needs));
    _changed();
    unawaited(_pump());
  }

  /// Wants the past listing of [channel] before the others.
  void need(LiveStream channel) {
    if (!_needs(channel)) return;
    _queue
      ..removeWhere((c) => c.id == channel.id)
      ..insert(0, channel);
    _changed();
    unawaited(_pump());
  }

  bool _needs(LiveStream channel) {
    if (!channel.hasReplay || channel.id == _current) return false;
    final now = ref.read(clockProvider);
    if (state.failed[channel.id] case final at?
        when now.difference(at) < retryAfter) {
      return false;
    }
    final entry = state.entries[channel.id];
    return entry == null || now.difference(entry.fetchedAt) >= maxAge;
  }

  void _changed() {
    if (!ref.mounted) return;
    state = ArchiveListingsState(
      entries: state.entries,
      loading: {for (final c in _queue) c.id, ?_current},
      failed: state.failed,
    );
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    final generation = _generation;
    try {
      await _cacheRead;
      while (_queue.isNotEmpty && generation == _generation && ref.mounted) {
        final channel = _queue.removeAt(0);
        if (!_needs(channel)) continue;
        _current = channel.id;
        _changed();
        await _download(channel, generation);
        if (generation != _generation || !ref.mounted) return;
        _current = null;
        _changed();
      }
    } finally {
      if (generation == _generation) _running = false;
    }
  }

  Future<void> _download(LiveStream channel, int generation) async {
    final source = ref.read(liveSourceProvider);
    if (source == null) return;
    try {
      final listings = await source.archiveListings(channel);
      if (generation != _generation || !ref.mounted) return;
      final now = ref.read(clockProvider);
      final earliest = now.subtract(Duration(days: channel.archiveDays));
      // Only the past is needed: the guide has what comes.
      final past =
          listings
              .where((p) => p.start.isBefore(now) && p.stop.isAfter(earliest))
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      state = ArchiveListingsState(
        entries: {
          ...state.entries,
          channel.id: ArchiveEntry(fetchedAt: now, programs: past),
        },
        loading: state.loading,
        failed: {...state.failed}..remove(channel.id),
      );
      _scheduleSave();
    } catch (e) {
      // Only the plain description: never the URL or credentials.
      debugPrint('Past programmes failed: ${describeRefreshError(e)}');
      if (generation != _generation || !ref.mounted) return;
      state = ArchiveListingsState(
        entries: state.entries,
        loading: state.loading,
        failed: {...state.failed, channel.id: ref.read(clockProvider)},
      );
    }
  }

  void _scheduleSave() {
    final key = ref.read(providerKeyProvider);
    if (key == null) return;
    _save?.cancel();
    _save = Timer(saveDelay, () {
      if (!ref.mounted) return;
      unawaited(
        ref
            .read(archiveEpgRepositoryProvider)
            .save(key, state.entries)
            .catchError((Object e) {
              debugPrint('Could not save past programmes (${e.runtimeType})');
            }),
      );
    });
  }
}

/// Past listings of the active provider's channels with replay.
final archiveListingsProvider =
    NotifierProvider<ArchiveListingsController, ArchiveListingsState>(
      ArchiveListingsController.new,
    );

/// The TV guide together with the past listings; null while there is no
/// guide.
final guideLookupProvider = Provider<GuideLookup?>((ref) {
  final guide = ref.watch(guideProvider.select((s) => s.guide));
  if (guide == null) return null;
  final archive = ref.watch(archiveListingsProvider.select((s) => s.entries));
  return GuideLookup(guide, {
    for (final MapEntry(:key, :value) in archive.entries) key: value.programs,
  });
});
