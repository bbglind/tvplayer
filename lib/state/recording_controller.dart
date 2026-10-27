import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../data/app_settings.dart';
import '../format.dart';
import '../player/mpv/external_mpv_player.dart';
import 'downloads_controller.dart';
import 'providers.dart';

/// A recording in progress.
@immutable
final class ActiveRecording {
  const ActiveRecording({
    required this.id,
    required this.channel,
    required this.start,
    required this.plannedEnd,
    required this.now,
    this.bytes = 0,
    this.warning,
  });

  /// The downloads entry it is saved as.
  final String id;
  final LiveStream channel;
  final DateTime start;

  /// When it stops by itself: the programme's end plus the end margin, at
  /// most the maximum length after [start].
  final DateTime plannedEnd;

  /// The time of the last tick, for the elapsed time.
  final DateTime now;
  final int bytes;

  /// "The disk is almost full…" while it is.
  final String? warning;

  Duration get elapsed {
    final d = now.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  ActiveRecording copyWith({
    DateTime? now,
    int? bytes,
    String? Function()? warning,
  }) => ActiveRecording(
    id: id,
    channel: channel,
    start: start,
    plannedEnd: plannedEnd,
    now: now ?? this.now,
    bytes: bytes ?? this.bytes,
    warning: warning == null ? this.warning : warning(),
  );
}

/// What would stop a recording.
enum RecordingStop {
  /// Another channel.
  zap,

  /// Leaving the player (Stop, Back).
  leave,

  /// Closing the app.
  quit,
}

/// The planned end of a recording of [channel] started at [now]: the
/// programme on then in [guide] plus the end margin, capped at the
/// maximum length; also the programme's title.
({DateTime end, String? programme}) plannedRecording({
  required AppSettings settings,
  required GuideTime time,
  required EpgGuide? guide,
  required LiveStream channel,
  required DateTime now,
}) {
  final programme = guide?.nowAndNext(channel, time.unadjust(now)).now;
  return (
    end: recordingEnd(
      start: now,
      programmeEnd: programme == null ? null : time.adjust(programme.stop),
      endMargin: settings.endMargin,
      maxLength: settings.maxRecordingLength,
    ),
    programme: programme?.title,
  );
}

/// The one recording, made from what the external mpv plays ("Record
/// now" on live TV). It uses no stream of its own: it rides on the
/// player's, and ends with it.
final recordingProvider =
    NotifierProvider<RecordingController, ActiveRecording?>(
      RecordingController.new,
    );

class RecordingController extends Notifier<ActiveRecording?> {
  /// How often the elapsed time, the file and the end are checked.
  static const tick = Duration(seconds: 1);

  /// Ticks without the file growing before the recording is given up.
  static const stallTicks = 60;

  /// Ticks between disk space checks.
  static const spaceTicks = 30;

  Timer? _timer;
  ExternalMpvPlayer? _player;
  int _ticks = 0;
  int _stalled = 0;
  bool _stopping = false;

  /// Asks the user before something stops the recording; set by the open
  /// player, which shows the question. True to stop it.
  Future<bool> Function(RecordingStop reason)? confirmer;

  @override
  ActiveRecording? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  DateTime get _now => ref.read(clockProvider.notifier).now().toUtc();

  /// Whether a recording runs.
  bool get active => ref.mounted && state != null;

  SpacePolicy get _policy =>
      (ref.read(appSettingsProvider).value ?? const AppSettings()).spacePolicy;

  /// Starts recording [channel] from what [player] plays. Returns why it
  /// couldn't, or null when it records.
  Future<String?> start(LiveStream channel, ExternalMpvPlayer player) async {
    if (state != null) return null;
    final folder = ref.read(downloadFolderProvider);
    final free = await ref.read(freeSpaceProvider).at(folder);
    if (!ref.mounted) return null;
    final minFree = formatGb(_policy.minFree);
    if (free != null && _policy.check(free) == SpaceStatus.full) {
      return "Can't record: less than $minFree free on the disk.";
    }
    final now = _now;
    final plan = plannedRecording(
      settings: ref.read(appSettingsProvider).value ?? const AppSettings(),
      time: ref.read(guideTimeProvider),
      guide: ref.read(guideProvider).guide,
      channel: channel,
      now: now,
    );
    final downloads = ref.read(downloadsProvider.notifier);
    final item = downloads.addRecording(
      channel: channel,
      programme: plan.programme,
      from: now,
      plannedEnd: plan.end,
      localStart: ref.read(guideTimeProvider).local(now),
    );
    if (!await player.startRecording(item.path)) {
      await downloads.remove(item.id);
      return "Couldn't start recording: the player refused.";
    }
    if (!ref.mounted) return null;
    _player = player;
    _ticks = 0;
    _stalled = 0;
    state = ActiveRecording(
      id: item.id,
      channel: channel,
      start: now,
      plannedEnd: plan.end,
      now: now,
      warning: free != null && _policy.check(free) == SpaceStatus.low
          ? _lowText(minFree)
          : null,
    );
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => unawaited(_tick()));
    return null;
  }

  static String _lowText(String minFree) =>
      'The disk is almost full: the recording stops at $minFree free.';

  Future<void> _tick() async {
    if (!ref.mounted) return;
    final rec = state;
    if (rec == null || _stopping) return;
    final now = _now;
    if (!now.isBefore(rec.plannedEnd)) {
      await stop();
      return;
    }
    _ticks++;
    final item = ref.read(downloadsProvider).byId(rec.id);
    int? size;
    if (item != null) {
      try {
        size = File(item.path).lengthSync();
      } on FileSystemException {
        size = null;
      }
    }
    if (size != null && size > rec.bytes) {
      _stalled = 0;
      ref.read(downloadsProvider.notifier).recordingProgress(rec.id, size);
    } else if (++_stalled >= stallTicks) {
      await stop(note: 'Stopped: no data from the stream for a minute.');
      return;
    }
    String? Function()? warning;
    if (_ticks % spaceTicks == 0 && item != null) {
      final free = await ref
          .read(freeSpaceProvider)
          .at(File(item.path).parent.path);
      if (!ref.mounted || state?.id != rec.id) return;
      final minFree = formatGb(_policy.minFree);
      switch (free == null ? SpaceStatus.ok : _policy.check(free)) {
        case SpaceStatus.full:
          await stop(note: 'Stopped: less than $minFree free on the disk.');
          ref
              .read(downloadNoticeProvider.notifier)
              .show(
                'Recording stopped: less than $minFree free on the disk. '
                'What was recorded is kept.',
              );
          return;
        case SpaceStatus.low:
          warning = () => _lowText(minFree);
        case SpaceStatus.ok:
          warning = () => null;
      }
    }
    if (!ref.mounted || state?.id != rec.id) return;
    state = state!.copyWith(now: now, bytes: size, warning: warning);
  }

  /// Asks the open player whether to stop the recording for [reason];
  /// true when there is none or the user agrees.
  Future<bool> confirmStop(RecordingStop reason) async {
    if (state == null) return true;
    final ask = confirmer;
    return ask == null || await ask(reason);
  }

  /// Stops the recording, keeping the file; [note] says why when it
  /// stopped early.
  Future<void> stop({String? note}) async {
    // The app is closing: mpv quitting closes the file.
    if (!ref.mounted) return;
    final rec = state;
    if (rec == null || _stopping) return;
    _stopping = true;
    try {
      _timer?.cancel();
      _timer = null;
      await _player?.stopRecording();
      _player = null;
      if (!ref.mounted) return;
      ref
          .read(downloadsProvider.notifier)
          .finishRecording(rec.id, end: _now, note: note);
      state = null;
    } finally {
      _stopping = false;
    }
  }
}
