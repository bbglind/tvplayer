import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../player/controls_visibility.dart';
import '../../player/playback_request.dart';
import '../../player/touch/device_controls.dart';
import '../../player/touch/touch_gestures.dart';
import '../../player/touch/touch_player.dart';
import '../../state/archive_listings.dart';
import '../../state/downloads_controller.dart';
import '../../state/player_stream.dart';
import '../../state/providers.dart';
import '../../state/watch_controller.dart';
import '../epg/now_next.dart';
import '../live/replay_mark.dart';
import '../theme/app_colors.dart';
import '../vod/provider_title.dart';
import 'open_channel.dart';
import 'player_controls.dart';
import 'player_debug.dart';
import 'track_panel.dart';

/// Plays a live channel, replay, movie, episode or recording on a phone
/// (Android), with media_kit: landscape, fullscreen without system bars,
/// back to portrait on leaving.
///
/// The controls are drawn over the video and hide 3 s after the last
/// touch; a tap on the video shows or hides them. A double tap on the left
/// or right seeks 10 s where seeking is possible, more taps seek on. A
/// vertical swipe changes the brightness of the app window (left half) or
/// the phone's media volume (right half).
///
/// Live TV pauses only on channels with an archive, and resumes from the
/// archive, like on the desktop. Movies and episodes start at their saved
/// position and save it as they play. Audio and subtitles are picked from
/// the settings (or a choice remembered for the series).
class TouchPlayerScreen extends ConsumerStatefulWidget {
  const TouchPlayerScreen({super.key, required this.request});

  final PlaybackRequest request;

  @override
  ConsumerState<TouchPlayerScreen> createState() => _TouchPlayerScreenState();
}

class _TouchPlayerScreenState extends ConsumerState<TouchPlayerScreen> {
  /// How often the position is saved while playing.
  static const _saveInterval = Duration(seconds: 10);

  /// How long a seek or level hint stays after the last change.
  static const _hintLinger = Duration(milliseconds: 600);

  /// Widest the side panels get.
  static const _panelWidth = 360.0;

  late final TouchPlayer _player;

  /// Read in [initState]: the phone is also restored from [dispose].
  late final DeviceControls _device;

  /// What plays now; pausing live TV and going live change it.
  late PlaybackRequest _request = widget.request;
  Uri? _url;

  /// For movies and episodes. Read up front: positions are also saved from
  /// [dispose], where [ref] can't be used.
  WatchController? _watch;

  final _controls = ControlsVisibility();
  late final _taps = TouchTaps(
    onTap: _onTap,
    onSeek: _onTapSeek,
    onSeekEnd: _onTapSeekEnd,
    canSeek: () => canSeekByTap(_request) && _player.loaded,
  );

  /// Last known position and duration, kept when the player stops
  /// reporting them.
  Duration? _position;
  Duration? _duration;
  DateTime? _lastSave;

  /// Track ids the automatic choice was made for; it runs again when new
  /// tracks appear.
  String? _pickedFor;

  /// The user chose a track; no more automatic choices.
  bool _manualTracks = false;

  /// Counts the media loaded; [_endHandled] is the one whose end was
  /// handled.
  int _load = 0;
  int? _endHandled;

  /// When the current media was loaded; a replay that ends right after
  /// loading has nothing more to give.
  DateTime? _loadedAt;

  /// Live TV paused: the moment it resumes from (see
  /// [ReplayTiming.liveDelay]); null while it plays.
  DateTime? _pausedAt;

  /// Counts "Behind live" up while paused.
  Timer? _pauseTicker;

  /// Where the double taps seek from, and the hint they show.
  Duration? _seekBase;
  DateTime? _replaySeekBase;
  ({TapSide side, Duration total})? _seekHint;
  Timer? _seekHintTimer;

  /// The swipe in progress: what it changes, the level it started from
  /// (null until read) and how far it went.
  SwipeTarget? _swipe;
  double? _swipeStart;
  double _swipeDy = 0;
  ({SwipeTarget target, double level})? _levelHint;
  Timer? _levelHintTimer;

  @override
  void initState() {
    super.initState();
    _device = ref.read(deviceControlsProvider);
    unawaited(_device.enterPlayer());
    _player = ref.read(touchPlayerFactoryProvider)(
      hwdec: ref.read(hwdecProvider),
    );
    _player.session?.debugPolling = ref.read(playerDebugProvider);
    _controls.autoHide = true;
    _controls.addListener(_rebuild);
    _player.addListener(_onChange);
    _url = playbackUrl(ref, _request);
    if (_url == null) return;
    if (_request.watchKey != null) _watch = ref.read(watchProvider.notifier);
    _needListing(_request);
    _open();
  }

  @override
  void dispose() {
    _taps.dispose();
    _seekHintTimer?.cancel();
    _levelHintTimer?.cancel();
    _pauseTicker?.cancel();
    _controls.dispose();
    _player.removeListener(_onChange);
    _saveProgress(later: true);
    _player.dispose();
    unawaited(_device.leavePlayer());
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// The time to the moment (not the clock's 30 s ticks).
  DateTime _now() => ref.read(clockProvider.notifier).now();

  void _open() {
    _load++;
    _loadedAt = _now();
    _lastSave = DateTime.now();
    unawaited(_player.open(_url!, start: _request.start));
  }

  void _onChange() {
    if (!mounted) return;
    _trackPosition();
    _pickTracks();
    _checkEnd();
    setState(() {});
  }

  void _trackPosition() {
    if (_request.watchKey == null || !_player.loaded) return;
    if (_player.duration case final d? when d > Duration.zero) _duration = d;
    if (_player.completed) {
      _position = _duration ?? _position;
    } else if (_player.position > Duration.zero) {
      // Not the 0 before the start position is reached.
      _position = _player.position;
    }
    final last = _lastSave;
    if (last != null && DateTime.now().difference(last) >= _saveInterval) {
      _saveProgress();
    }
  }

  /// Saves the last known position of a movie or episode. With [later],
  /// after the current frame's work, as providers can't change while
  /// widgets are being disposed.
  void _saveProgress({bool later = false}) {
    final key = _request.watchKey;
    final watch = _watch;
    final position = _position;
    if (key == null || watch == null || position == null) return;
    _lastSave = DateTime.now();
    final duration = _duration;
    final info = switch (_request) {
      EpisodePlayback(:final info) => info,
      _ => null,
    };
    void save() => watch.recordProgress(
      key,
      position: position,
      duration: duration,
      info: info,
    );
    later ? scheduleMicrotask(save) : save();
  }

  /// Chooses audio and subtitles once the tracks are known.
  void _pickTracks() {
    final tracks = _player.tracks;
    if (!_player.loaded || tracks.isEmpty || _manualTracks) return;
    final signature = [
      for (final t in tracks)
        if (t.type != TrackType.video) '${t.type.name}${t.id}',
    ].join(',');
    if (signature == _pickedFor) return;
    _pickedFor = signature;
    final pick = pickTracks(
      tracks,
      ref.read(appSettingsProvider).value?.trackPreferences ??
          const AppSettings().trackPreferences,
      memory: switch (_request) {
        EpisodePlayback(:final info) =>
          ref.read(watchProvider).seriesTracks[info.series.seriesId]?.memory,
        _ => null,
      },
    );
    if (pick.audioId case final id? when id != _player.audioId) {
      unawaited(_player.setAudioTrack(id));
    }
    if (pick.subtitleId != _player.subtitleId) {
      unawaited(_player.setSubtitleTrack(pick.subtitleId));
    }
  }

  void _selectSubtitle(int? id) {
    _manualTracks = true;
    unawaited(_player.setSubtitleTrack(id));
    _rememberTracks(audioId: _player.audioId, subtitleId: id);
  }

  void _selectAudio(int id) {
    _manualTracks = true;
    unawaited(_player.setAudioTrack(id));
    _rememberTracks(audioId: id, subtitleId: _player.subtitleId);
  }

  /// A manual choice holds for the rest of the series.
  void _rememberTracks({required int? audioId, required int? subtitleId}) {
    if (_request case EpisodePlayback(:final info)) {
      MediaTrack? find(TrackType type, int? id) =>
          _player.tracks.where((t) => t.type == type && t.id == id).firstOrNull;
      _watch?.rememberTracks(
        info.series.seriesId,
        TrackMemory.fromSelection(
          audio: find(TrackType.audio, audioId),
          subtitle: find(TrackType.subtitle, subtitleId),
        ),
      );
    }
  }

  /// At the end: a replay loads on or goes live; anything else leaves the
  /// player, its position saved.
  void _checkEnd() {
    if (!_player.completed || !_player.loaded || _endHandled == _load) return;
    _endHandled = _load;
    if (_request is ReplayPlayback) {
      final position = _replayPosition();
      if (position == null) return;
      final step = atEndOfArchive(
        position: position,
        now: _now(),
        loadedAt: _loadedAt,
      );
      scheduleMicrotask(() {
        if (!mounted) return;
        switch (step) {
          case EndOfArchive.goLive:
            _goLive();
          case EndOfArchive.reload:
            _replayFrom(position);
        }
      });
      return;
    }
    _saveProgress();
    scheduleMicrotask(() {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    });
  }

  /// A replay before the XMLTV guide needs the channel's past listing for
  /// its title and now/next (an API request, not a stream).
  void _needListing(PlaybackRequest request) {
    if (request case ReplayPlayback(:final channel)) {
      // Not while the widget tree builds (initState).
      scheduleMicrotask(() {
        if (mounted) ref.read(archiveListingsProvider.notifier).need(channel);
      });
    }
  }

  /// The live channel of live TV or a replay.
  LiveStream? get _channel => switch (_request) {
    LivePlayback(:final channel) || ReplayPlayback(:final channel) => channel,
    _ => null,
  };

  /// Plays [request] in this screen. [reuse]: the same channel, live or
  /// from its archive, where a chosen track stays.
  void _switchTo(PlaybackRequest request, {bool reuse = false}) {
    final url = playbackUrl(ref, request);
    if (url == null) return;
    if (ref.read(playerStreamProvider).request(request) ==
        StreamNeed.pauseDownload) {
      unawaited(_askPauseDownload(() => _switchTo(request, reuse: reuse)));
      return;
    }
    _saveProgress();
    _needListing(request);
    setState(() {
      _request = request;
      _url = url;
      _watch = request.watchKey == null
          ? null
          : ref.read(watchProvider.notifier);
      _position = null;
      _duration = null;
      _pickedFor = null;
      _clearPause();
      if (!reuse) _manualTracks = false;
    });
    _open();
  }

  Future<void> _askPauseDownload(VoidCallback play) async {
    if (!await confirmPauseDownload(context, ref) || !mounted) return;
    ref.read(downloadsProvider.notifier).pauseForPlayback();
    play();
  }

  /// The moment a replay shows now.
  DateTime? _replayPosition() {
    final request = _request;
    if (request is! ReplayPlayback) return null;
    return ReplayTimeline(request.timeshift.floored).clockAt(
      _player.loaded ? _player.position : request.start ?? Duration.zero,
    );
  }

  /// Plays the channel live.
  void _goLive() {
    final channel = _channel;
    if (channel == null || _request is LivePlayback && _pausedAt == null) {
      return;
    }
    ref.read(watchProvider.notifier).recordChannel(channel);
    _switchTo(LivePlayback(channel), reuse: true);
  }

  /// Plays the channel's archive from the real moment [from].
  void _replayFrom(DateTime from, {String? zone}) {
    final channel = _channel;
    if (channel == null) return;
    zone ??= switch (_request) {
      ReplayPlayback(:final serverZone) => serverZone,
      _ => ref.read(serverTimeZoneProvider).value,
    };
    if (zone == null) return;
    _switchTo(
      ReplayPlayback(
        channel,
        from: from,
        serverZone: zone,
        requestedAt: _now(),
      ),
      reuse: true,
    );
  }

  /// Seeks a replay to the real moment [target]: in the loaded stream when
  /// it has it, else by loading the archive from there; close to now it
  /// goes live.
  void _seekReplayTo(DateTime target) {
    final request = _request;
    final channel = _channel;
    if (request is! ReplayPlayback || channel == null) return;
    final now = _now();
    if (behindLive(target, now) <= ReplayTiming.liveThreshold) {
      _goLive();
      return;
    }
    final earliest = ReplayWindow(channel.archiveDays).earliest(now);
    final to = target.isBefore(earliest) ? earliest : target;
    final timeline = ReplayTimeline(request.timeshift.floored);
    if (_player.seekable && timeline.contains(to, _player.duration)) {
      unawaited(_player.seek(timeline.positionOf(to)));
    } else {
      _replayFrom(to);
    }
  }

  /// Whether live TV can pause: on channels with an archive, which it
  /// resumes from.
  bool get _canPauseLive => switch (_request) {
    LivePlayback(:final channel) => channel.hasReplay,
    _ => false,
  };

  /// Play/pause for what can pause; live TV without archive can't.
  void _togglePause() {
    if (_request.fixedLength) {
      unawaited(_player.playing ? _player.pause() : _player.play());
    } else if (_canPauseLive) {
      _pausedAt == null ? _pauseLive() : unawaited(_resumeLive());
    }
    _controls.activity();
  }

  /// Stops live TV and keeps its last picture.
  void _pauseLive() {
    if (!_canPauseLive || _pausedAt != null) return;
    unawaited(_player.pause());
    setState(() => _pausedAt = _now().subtract(ReplayTiming.liveDelay));
    _pauseTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Plays on from the moment of the pause, from the archive.
  Future<void> _resumeLive() async {
    final from = _pausedAt;
    if (from == null) return;
    final zone = await ref.read(serverTimeZoneProvider.future);
    if (!mounted || _pausedAt != from) return;
    _replayFrom(from, zone: zone);
  }

  void _clearPause() {
    _pauseTicker?.cancel();
    _pauseTicker = null;
    _pausedAt = null;
  }

  void _onTap() => _controls.visible ? _controls.hide() : _controls.activity();

  /// A double tap (and the taps after it): seeks from where the first one
  /// was.
  void _onTapSeek(Duration by, Duration total, TapSide side) {
    if (_request is ReplayPlayback) {
      final base = _replaySeekBase ??= _replayPosition();
      if (base != null) _seekReplayTo(base.add(total));
    } else {
      final base = _seekBase ??= _player.position;
      var to = base + total;
      if (to < Duration.zero) to = Duration.zero;
      if (_player.duration case final d? when d > Duration.zero && to > d) {
        to = d;
      }
      unawaited(_player.seek(to));
    }
    _seekHintTimer?.cancel();
    setState(() => _seekHint = (side: side, total: total));
  }

  void _onTapSeekEnd() {
    _seekBase = null;
    _replaySeekBase = null;
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(_hintLinger, () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  Future<void> _startSwipe(Offset at, Size size) async {
    final gestures = MediaQuery.systemGestureInsetsOf(context);
    final target = swipeTarget(
      at,
      size,
      sideEdge: [swipeSideEdge, gestures.left, gestures.right].reduce(math.max),
    );
    _swipe = target;
    _swipeStart = null;
    _swipeDy = 0;
    if (target == null) return;
    final level = switch (target) {
      SwipeTarget.volume => await _device.mediaVolume(),
      SwipeTarget.brightness => await _device.brightness(),
    };
    if (!mounted || _swipe != target) return;
    _swipeStart = level ?? 0.5;
    _applySwipe(size.height);
  }

  void _updateSwipe(double dy, double height) {
    if (_swipe == null) return;
    _swipeDy += dy;
    _applySwipe(height);
  }

  void _applySwipe(double height) {
    final target = _swipe;
    final start = _swipeStart;
    if (target == null || start == null) return;
    final level = levelAfterSwipe(start, _swipeDy, height);
    switch (target) {
      case SwipeTarget.volume:
        unawaited(_device.setMediaVolume(level));
      case SwipeTarget.brightness:
        unawaited(_device.setBrightness(level));
    }
    _levelHintTimer?.cancel();
    setState(() => _levelHint = (target: target, level: level));
  }

  void _endSwipe() {
    _swipe = null;
    _swipeStart = null;
    _levelHintTimer?.cancel();
    _levelHintTimer = Timer(_hintLinger, () {
      if (mounted) setState(() => _levelHint = null);
    });
  }

  /// Whether there is anything to choose in Subtitles and audio.
  bool get _hasTrackChoice {
    var audio = 0;
    for (final t in _player.tracks) {
      if (t.type == TrackType.subtitle) return true;
      if (t.type == TrackType.audio) audio++;
    }
    return audio > 1;
  }

  /// A side panel at the right edge, over the video; the controls stay
  /// while it is open.
  Future<void> _showPanel(
    Object reason,
    String label,
    double width,
    WidgetBuilder builder,
  ) async {
    _controls.hold(reason, true);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: label,
      barrierColor: AppColors.scrim.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) {
        final screen = MediaQuery.sizeOf(context).width;
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: math.min(width, screen * 0.7),
            height: double.infinity,
            child: Material(
              color: AppColors.surface,
              child: SafeArea(left: false, child: builder(context)),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
    if (mounted) _controls.hold(reason, false);
  }

  void _showTracks() => unawaited(
    _showPanel(
      #tracks,
      'Close subtitles and audio',
      _panelWidth,
      (context) => ListenableBuilder(
        listenable: _player,
        builder: (context, _) => TrackPanel(
          tracks: _player.tracks,
          audioId: _player.audioId,
          subtitleId: _player.subtitleId,
          onSubtitle: _selectSubtitle,
          onAudio: _selectAudio,
        ),
      ),
    ),
  );

  void _showDebug() => unawaited(
    _showPanel(#debug, 'Close debug info', 520, (context) {
      final session = _player.session;
      if (session == null) {
        return const Center(child: Text('No debug info'));
      }
      return PlayerDebugPanel(
        session: session,
        hwdecModes: Hwdec.modes,
        onHwdecChanged: (mode) {
          ref.read(hwdecProvider.notifier).set(mode);
          unawaited(session.setHwdec(mode));
        },
      );
    }),
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(playerDebugProvider, (_, on) {
      _player.session?.debugPolling = on;
    });
    if (_url == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No provider configured')),
      );
    }
    // Asked early, so resuming a pause doesn't wait for the provider.
    if (_canPauseLive) ref.watch(serverTimeZoneProvider);
    final loading = !_player.loaded && _player.error == null;
    return Scaffold(
      backgroundColor: AppColors.scrim,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              KeyedSubtree(
                key: const Key('player.video'),
                child: _player.buildVideo(context),
              ),
              GestureDetector(
                key: const Key('player.gestures'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) =>
                    _taps.tap(tapSide(d.localPosition.dx, size.width)),
                onVerticalDragStart: (d) =>
                    unawaited(_startSwipe(d.localPosition, size)),
                onVerticalDragUpdate: (d) =>
                    _updateSwipe(d.primaryDelta ?? 0, size.height),
                onVerticalDragEnd: (_) => _endSwipe(),
                onVerticalDragCancel: _endSwipe,
              ),
              if (loading || _player.buffering)
                const IgnorePointer(
                  child: Center(
                    child: CircularProgressIndicator(
                      key: Key('player.loading'),
                    ),
                  ),
                ),
              if (_seekHint case final hint?) _buildSeekHint(hint, size),
              if (_levelHint case final hint?) _buildLevelHint(hint),
              IgnorePointer(
                ignoring: !_controls.visible,
                child: AnimatedOpacity(
                  key: const Key('player.controls'),
                  opacity: _controls.visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildControls(context, loading: loading),
                ),
              ),
              if (_player.error case final error?) _buildError(error),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls(BuildContext context, {required bool loading}) {
    final scrim = AppColors.scrim.withValues(alpha: 0.75);
    final clear = AppColors.scrim.withValues(alpha: 0);
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [scrim, clear],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 16),
              child: _buildTopBar(context),
            ),
          ),
        ),
        Expanded(child: Center(child: loading ? null : _buildPlayPause())),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [scrim, clear],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _buildBottomBar(context, loading: loading),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final debug = ref.watch(playerDebugProvider);
    final tracks = _hasTrackChoice;
    return Row(
      children: [
        IconButton(
          key: const Key('player.back'),
          tooltip: 'Back (stops playback)',
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.titleMedium,
            child: _buildTitle(context),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('player.tracks'),
          tooltip: tracks
              ? 'Subtitles and audio'
              : 'No subtitles or other audio',
          icon: const Icon(Icons.subtitles_outlined),
          onPressed: tracks ? _showTracks : null,
        ),
        if (debug)
          IconButton(
            key: const Key('player.debugInfo'),
            tooltip: 'Debug info',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: _showDebug,
          ),
      ],
    );
  }

  /// The channel without the provider's replay mark, or the movie or
  /// episode without the provider's tag.
  Widget _buildTitle(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    return switch (_request) {
      LivePlayback(:final channel) => ChannelName(channel, style: style),
      ReplayPlayback(:final channel) => _ReplayTitle(
        channel: channel,
        position: _player.loaded ? _replayPosition() : null,
      ),
      MoviePlayback(:final movie) => ProviderTitle(movie.name, style: style),
      EpisodePlayback(:final info, :final episode) => ProviderTitle(
        info.series.name,
        title: _request.title(ref.watch(providerTagsProvider)),
        fullName: episodeFullName(info.series, episode),
        style: style,
      ),
      RecordingPlayback(:final name) => Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    };
  }

  /// The big play/pause in the middle, where it can pause: movies,
  /// episodes, recordings, replays, and live TV with an archive.
  Widget? _buildPlayPause() {
    final String tooltip;
    final bool paused;
    if (_request.fixedLength) {
      paused = !_player.playing;
      tooltip = paused ? 'Resume' : 'Pause';
    } else if (_canPauseLive) {
      paused = _pausedAt != null;
      tooltip = paused ? 'Resume' : 'Pause live TV';
    } else {
      return null;
    }
    return IconButton(
      key: Key(_request.fixedLength ? 'player.pause' : 'player.livePause'),
      tooltip: tooltip,
      iconSize: 56,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.scrim.withValues(alpha: 0.6),
      ),
      icon: Icon(paused ? Icons.play_arrow : Icons.pause),
      onPressed: _togglePause,
    );
  }

  Widget _buildBottomBar(BuildContext context, {required bool loading}) {
    final channel = _channel;
    final request = _request;
    if (request is ReplayPlayback) {
      return Row(
        children: [
          Expanded(child: _buildReplaySeekBar(request, loading: loading)),
          const SizedBox(width: 8),
          _buildGoLive(channel!),
        ],
      );
    }
    if (_pausedAt case final pausedAt?) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'Paused · Behind live '
              '${formatBehindLive(behindLive(pausedAt, _now()))}',
              key: const Key('live.paused'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          _buildGoLive(channel!),
        ],
      );
    }
    if (request is LivePlayback) {
      return NowNextLine(channel: request.channel);
    }
    final showRemaining = ref.watch(
      appSettingsProvider.select((s) => s.value?.showRemainingTime ?? false),
    );
    return PlayerSeekBar(
      position: _player.position,
      duration: _player.loaded ? _player.duration : null,
      showRemaining: showRemaining,
      onToggleRemaining: () => ref
          .read(appSettingsProvider.notifier)
          .remember((s) => s.copyWith(showRemainingTime: !s.showRemainingTime)),
      onSeek: (p) => unawaited(_player.seek(p)),
      onDragging: (v) => _controls.hold(#seek, v),
      touch: true,
    );
  }

  Widget _buildGoLive(LiveStream channel) => Tooltip(
    message: 'Go live: watch ${channelDisplayName(channel)} live',
    child: OutlinedButton.icon(
      key: const Key('player.goLive'),
      onPressed: _goLive,
      icon: const Icon(Icons.skip_next),
      label: const Text('LIVE'),
    ),
  );

  /// The replay's seek bar in clock time, over the programme at the
  /// playing position or, behind live, up to now. While a new stretch of
  /// the archive loads ([loading]) it shows where it will start.
  Widget _buildReplaySeekBar(ReplayPlayback request, {required bool loading}) {
    final channel = request.channel;
    final position = loading ? request.from : _replayPosition() ?? request.from;
    final time = ref.watch(guideTimeProvider);
    final now = ref.watch(clockProvider);
    final program = watchNowNext(ref, channel, at: position)?.now;
    final range = replaySeekRange(
      position: position,
      now: now,
      earliest: ReplayWindow(channel.archiveDays).earliest(now),
      programStart: program == null ? null : time.adjust(program.start),
      programStop: program == null ? null : time.adjust(program.stop),
    );
    return ReplaySeekBar(
      position: position,
      from: range.from,
      to: range.to,
      time: time,
      behind: range.to == now ? behindLive(position, now) : null,
      loading: loading,
      onSeek: _seekReplayTo,
      onDragging: (v) => _controls.hold(#seek, v),
      touch: true,
    );
  }

  /// "+30 s" on the side the taps seek to.
  Widget _buildSeekHint(({TapSide side, Duration total}) hint, Size size) {
    final seconds = hint.total.inSeconds;
    final back = seconds < 0;
    return Positioned(
      top: 0,
      bottom: 0,
      left: back ? 0 : null,
      right: back ? null : 0,
      width: size.width / 3,
      child: IgnorePointer(
        child: Center(
          child: _Pill(
            key: const Key('player.seekHint'),
            children: [
              Icon(back ? Icons.fast_rewind : Icons.fast_forward),
              const SizedBox(width: 8),
              Text(back ? '−${-seconds} s' : '+$seconds s'),
            ],
          ),
        ),
      ),
    );
  }

  /// The brightness or volume while a swipe changes it.
  Widget _buildLevelHint(({SwipeTarget target, double level}) hint) {
    final percent = (hint.level * 100).round();
    final icon = switch (hint.target) {
      SwipeTarget.brightness => Icons.brightness_6_outlined,
      SwipeTarget.volume when percent == 0 => Icons.volume_off_outlined,
      SwipeTarget.volume => Icons.volume_up_outlined,
    };
    final name = switch (hint.target) {
      SwipeTarget.brightness => 'Brightness',
      SwipeTarget.volume => 'Volume',
    };
    return Align(
      alignment: const Alignment(0, -0.6),
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: '$name $percent %',
          child: _Pill(
            key: const Key('player.levelHint'),
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  value: hint.level,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text('$percent %'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(String error) => Align(
    alignment: Alignment.topCenter,
    child: SafeArea(
      child: Material(
        key: const Key('player.error'),
        color: AppColors.live,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.onAccent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.onAccent),
                ),
              ),
              IconButton(
                tooltip: 'Dismiss the error',
                icon: const Icon(Icons.close, color: AppColors.onAccent),
                onPressed: _player.dismissError,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "REPLAY", then the programme at [position] and the channel.
class _ReplayTitle extends ConsumerWidget {
  const _ReplayTitle({required this.channel, required this.position});

  final LiveStream channel;
  final DateTime? position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = this.position;
    final name = channelDisplayName(channel);
    final program = position == null
        ? null
        : watchNowNext(ref, channel, at: position)?.now;
    return Row(
      children: [
        const ReplayBadge(),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            program == null ? name : '${program.title} · $name',
            key: const Key('replay.title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A rounded `scrim` pill over the video for the seek and level hints.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.scrim.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: IconTheme.merge(
        data: const IconThemeData(color: AppColors.textPrimary),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    ),
  );
}
