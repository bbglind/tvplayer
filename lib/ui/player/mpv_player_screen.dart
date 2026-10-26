import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../format.dart';
import '../../player/controls_visibility.dart';
import '../../player/mpv/external_mpv_player.dart';
import '../../player/mpv/osd_mirror.dart';
import '../../player/mpv/video_embed.dart';
import '../../player/playback_request.dart';
import '../../player/pointer_forwarder.dart';
import '../../player/video_gestures.dart';
import '../../player/video_pointer.dart';
import '../../state/archive_listings.dart';
import '../../state/providers.dart';
import '../../state/variants.dart';
import '../../state/watch_controller.dart';
import '../epg/now_next.dart';
import '../favourites/favourite_menu.dart';
import '../favourites/favourite_panel.dart';
import '../live/replay_mark.dart';
import '../theme/app_colors.dart';
import '../vod/provider_title.dart';
import 'next_episode_card.dart';
import 'open_channel.dart';
import 'player_controls.dart';
import 'player_hint.dart';
import 'player_shortcuts.dart';
import 'track_panel.dart';
import 'zap_panel.dart';

enum _Mode {
  /// Asking the native side for an X11 window.
  embedding,

  /// mpv draws into the native video area of this screen.
  embedded,

  /// mpv has its own window; this screen only shows its status.
  external,
}

/// The side panel shown beside the video (or over it in fullscreen).
enum _Panel { none, tracks, favourites, zap }

/// mpv overlay ids of the parts shown over the video in fullscreen.
abstract final class _Overlay {
  static const bottom = 1;
  static const panel = 2;
}

/// Plays a live channel, movie or episode with mpv: embedded in the app
/// window on X11, in a separate mpv window otherwise. Leaving the screen
/// closes mpv; mpv exiting leaves the screen, except at the end of an
/// episode that has a next one, which then starts or is offered.
///
/// Windowed, the controls and panels sit below and beside the video. In
/// fullscreen the video fills the screen and they are shown over it by
/// mpv ([OsdMirror]), appearing on mouse movement or a key and hiding
/// again after a few seconds.
///
/// Mouse on the video: a click pauses (live TV: shows the controls), a
/// double click toggles fullscreen, the wheel changes the volume.
///
/// Zapping and the next episode play in this same screen, so fullscreen
/// stays and Back returns to where playback started.
///
/// Movies and episodes save their position as they play. Audio and
/// subtitles are picked from the settings (or a choice remembered for the
/// series) when playback starts.
class MpvPlayerScreen extends ConsumerStatefulWidget {
  const MpvPlayerScreen({super.key, required this.request});

  final PlaybackRequest request;

  @override
  ConsumerState<MpvPlayerScreen> createState() => _MpvPlayerScreenState();
}

class _MpvPlayerScreenState extends ConsumerState<MpvPlayerScreen> {
  /// How often the position is saved while playing.
  static const _saveInterval = Duration(seconds: 10);

  /// How long the volume must stay put before it is saved.
  static const _volumeSaveDelay = Duration(seconds: 1);

  /// Whether the hint line is also part of the fullscreen bar (drawn by
  /// mpv). Off: fullscreen shows no hints, as before.
  static const _fullscreenHints = true;

  late final ExternalMpvPlayer _player = ref.read(externalMpvProvider);
  late final VideoEmbed? _embed = ref.read(embedMpvProvider)
      ? ref.read(videoEmbedProvider)
      : null;

  /// Read in [initState]: settings are also saved from [dispose], where
  /// [ref] can't be used.
  late final AppSettingsNotifier _settings;

  /// What plays now; zapping and the next episode change it.
  late PlaybackRequest _request = widget.request;

  /// For movies and episodes. Read up front: positions are also saved from
  /// [dispose], where [ref] can't be used.
  WatchController? _watch;
  late _Mode _mode = _embed == null ? _Mode.external : _Mode.embedding;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Uri? _url;
  int? _session;

  /// The native video area mpv draws into; reused for every session.
  int? _wid;
  bool _fullscreen = false;
  _Panel _panel = _Panel.none;

  /// The episode played to its end and the next one is offered.
  bool _ended = false;

  /// Seconds until the next episode starts, while its card shows.
  int? _countdown;

  /// The countdown was cancelled; it comes back after seeking out of it.
  bool _nextCancelled = false;

  /// Last known position and duration, kept when mpv stops reporting them.
  Duration? _position;
  Duration? _duration;
  DateTime? _lastSave;

  /// Track ids the automatic choice was made for; it runs again when new
  /// tracks appear (e.g. teletext found later on live TV).
  String? _pickedFor;

  /// The user chose a track; no more automatic choices.
  bool _manualTracks = false;

  double? _savedVolume;
  Timer? _volumeSave;

  final _controls = ControlsVisibility();

  /// The hint of the control under the mouse or with keyboard focus.
  final _hints = PlayerHintController();
  late final _gestures = VideoGestures(
    onClick: _onVideoClick,
    onDoubleClick: () => _setFullscreen(!_fullscreen),
    onWheelSteps: (steps) =>
        unawaited(_player.changeVolume(-steps * PlayerShortcuts.volumeStep)),
  );
  PointerForwarder? _forwarder;

  final _shortcutsFocus = FocusNode(debugLabel: 'player');
  final _barFocus = FocusNode(
    debugLabel: 'player.controls',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final _playNowFocus = FocusNode(debugLabel: 'player.playNow');

  /// The parts of the fullscreen overlay that take the pointer.
  final _barKey = GlobalKey(debugLabel: 'player.bar');
  final _cardKey = GlobalKey(debugLabel: 'player.card');
  final _panelKey = GlobalKey(debugLabel: 'player.panel');

  @override
  void initState() {
    super.initState();
    _settings = ref.read(appSettingsProvider.notifier);
    _url = playbackUrl(ref, _request);
    if (_url == null) return;
    _needListing(_request);
    if (_request.watchKey != null) _watch = ref.read(watchProvider.notifier);
    _player.addListener(_onChange);
    _controls.addListener(_onControlsChange);
    _barFocus.addListener(_onBarFocus);
    if (_embed case final embed?) {
      _subscriptions.addAll([
        embed.pointerEvents.listen(_onPointer),
        embed.fullscreenChanges.listen((v) {
          if (!mounted) return;
          setState(() => _fullscreen = v);
          _fullscreenChanged();
        }),
      ]);
    }
    unawaited(_start(_url!));
  }

  AppSettings get _appSettings =>
      ref.read(appSettingsProvider).value ?? const AppSettings();

  Future<void> _start(Uri url) async {
    int? wid;
    if (_embed case final embed?) {
      try {
        wid = await embed.create();
      } on VideoEmbedException catch (e) {
        debugPrint(
          'Embedding mpv not possible (${e.reason}); '
          'using a separate mpv window.',
        );
      }
    }
    if (!mounted) return;
    _savedVolume = _appSettings.playerVolume.toDouble();
    setState(() {
      _wid = wid;
      _mode = wid == null ? _Mode.external : _Mode.embedded;
      _lastSave = DateTime.now();
      _loadedAt = _now();
      _session = _player.open(
        url,
        title: _request.title(ref.read(providerTagsProvider)),
        wid: wid,
        start: _request.start,
        volume: _appSettings.playerVolume,
        keepOpen: _request is ReplayPlayback,
      );
    });
    if (wid == null) unawaited(_embed?.hide());
  }

  /// The time to the moment (not the clock's 30 s ticks).
  DateTime _now() => ref.read(clockProvider.notifier).now();

  bool get _isMine => _session != null && _player.state.session == _session;

  bool get _showVideo =>
      _mode != _Mode.external &&
      !_ended &&
      !(_isMine && _player.state.status == ExternalPlayerStatus.failed);

  bool get _playing => _isMine && !_ended;

  Episode? get _nextEpisode => switch (_request) {
    EpisodePlayback(:final info, :final episode) => episodeAfter(info, episode),
    _ => null,
  };

  void _onChange() {
    if (!_isMine || !mounted) return;
    final state = _player.state;
    _trackPosition(state);
    _pickTracks(state);
    _rememberVolume(state);
    _updateCountdown(state);
    _checkEndOfArchive(state);
    switch (state.status) {
      case ExternalPlayerStatus.exited
          when ModalRoute.of(context)?.isCurrent ?? false:
        _saveProgress();
        if (state.endedAtEof && _nextEpisode != null) {
          if (_appSettings.playNextSeconds != null && !_nextCancelled) {
            scheduleMicrotask(_playNext);
            return;
          }
          _setFullscreen(false);
          unawaited(_embed?.hide());
          setState(() {
            _ended = true;
            _countdown = null;
          });
        } else {
          Navigator.of(context).pop();
        }
      case ExternalPlayerStatus.failed:
        // Show the error where the video was.
        _setFullscreen(false);
        unawaited(_embed?.hide());
      default:
    }
  }

  void _trackPosition(ExternalPlaybackState state) {
    if (_request.watchKey == null) return;
    if (state.duration case final d? when d > Duration.zero) _duration = d;
    if (state.endedAtEof) {
      _position = _duration ?? _position;
    } else if (state.position case final p?) {
      _position = p;
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

  /// Saves the volume once it has stayed put for a moment, whatever
  /// changed it (slider, wheel, keys).
  void _rememberVolume(ExternalPlaybackState state) {
    final volume = state.volume;
    if (volume == null || volume == _savedVolume) return;
    _volumeSave?.cancel();
    _volumeSave = Timer(_volumeSaveDelay, () => _saveVolume(volume));
  }

  void _saveVolume(double volume) {
    _volumeSave = null;
    _savedVolume = volume;
    _settings.remember((s) => s.copyWith(playerVolume: volume.round()));
  }

  /// Shows, counts down or hides the next-episode card, and starts the
  /// next episode at 0.
  void _updateCountdown(ExternalPlaybackState state) {
    final lead = _appSettings.playNextSeconds;
    final position = state.position;
    final countdown = lead == null || position == null || _nextEpisode == null
        ? null
        : playNextCountdown(
            position: position,
            duration: state.duration,
            leadSeconds: lead,
          );
    // Seeking back out of the countdown brings it back after a cancel.
    if (countdown == null) _nextCancelled = false;
    final shown = _nextCancelled ? null : countdown;
    if (shown == _countdown) return;
    final appeared = _countdown == null;
    setState(() => _countdown = shown);
    if (shown == 0) {
      scheduleMicrotask(_playNext);
    } else if (appeared && shown != null) {
      _controls.activity();
      // Focus "Play now" unless the user is busy in a panel or control.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focus = FocusManager.instance.primaryFocus;
        if (mounted && (focus == null || focus == _shortcutsFocus)) {
          _playNowFocus.requestFocus();
        }
      });
    }
  }

  void _cancelNext() {
    setState(() {
      _nextCancelled = true;
      _countdown = null;
    });
    _shortcutsFocus.requestFocus();
  }

  /// Chooses audio and subtitles once the tracks are known.
  void _pickTracks(ExternalPlaybackState state) {
    if (!state.fileLoaded || state.tracks.isEmpty || _manualTracks) return;
    final signature = [
      for (final t in state.tracks)
        if (t.type != TrackType.video) '${t.type.name}${t.id}',
    ].join(',');
    if (signature == _pickedFor) return;
    _pickedFor = signature;
    final pick = pickTracks(
      state.tracks,
      _appSettings.trackPreferences,
      memory: switch (_request) {
        EpisodePlayback(:final info) =>
          ref.read(watchProvider).seriesTracks[info.series.seriesId]?.memory,
        _ => null,
      },
    );
    if (pick.audioId case final id? when id != state.audioId) {
      unawaited(_player.setAudioTrack(id));
    }
    if (pick.subtitleId != state.subtitleId) {
      unawaited(_player.setSubtitleTrack(pick.subtitleId));
    }
  }

  void _selectSubtitle(int? id) {
    _manualTracks = true;
    unawaited(_player.setSubtitleTrack(id));
    _rememberTracks(audioId: _player.state.audioId, subtitleId: id);
  }

  void _selectAudio(int id) {
    _manualTracks = true;
    unawaited(_player.setAudioTrack(id));
    _rememberTracks(audioId: id, subtitleId: _player.state.subtitleId);
  }

  void _cycleSubtitles() {
    final state = _player.state;
    if (state.subtitleTracks.isEmpty) return;
    _selectSubtitle(nextSubtitleId(state.tracks, state.subtitleId));
  }

  /// A manual choice holds for the rest of the series.
  void _rememberTracks({required int? audioId, required int? subtitleId}) {
    if (_request case EpisodePlayback(:final info)) {
      MediaTrack? find(List<MediaTrack> tracks, int? id) =>
          tracks.where((t) => t.id == id).firstOrNull;
      final state = _player.state;
      _watch?.rememberTracks(
        info.series.seriesId,
        TrackMemory.fromSelection(
          audio: find(state.audioTracks, audioId),
          subtitle: find(state.subtitleTracks, subtitleId),
        ),
      );
    }
  }

  /// Plays the next episode here, marking this one watched.
  void _playNext() {
    if (!mounted) return;
    final next = _nextEpisode;
    if (next == null) return;
    final info = (_request as EpisodePlayback).info;
    if ((_request.watchKey, _duration ?? _position) case (
      final key?,
      final end?,
    )) {
      _watch?.recordProgress(key, position: end, duration: end, info: info);
    }
    final view = ref.read(episodeViewProvider(info.series.seriesId));
    final start = resumePosition(view.progress(next));
    _switchTo(EpisodePlayback(info, next, start: start), save: false);
  }

  /// Switches to [channel] without leaving the player: live, also from a
  /// replay.
  void _zapTo(LiveStream channel) {
    setState(() => _panel = _Panel.none);
    _shortcutsFocus.requestFocus();
    if (_request case LivePlayback(channel: final c) when c.id == channel.id) {
      return;
    }
    ref.read(watchProvider.notifier).recordChannel(channel);
    _switchTo(LivePlayback(channel), reuse: _channel?.id == channel.id);
  }

  /// The live channel of live TV or a replay.
  LiveStream? get _channel => switch (_request) {
    LivePlayback(:final channel) || ReplayPlayback(:final channel) => channel,
    _ => null,
  };

  /// Plays [request] in a new mpv session in the same video area. With
  /// [reuse] (the same channel live or from its archive) the running mpv
  /// loads it in place of what it plays.
  void _switchTo(
    PlaybackRequest request, {
    bool save = true,
    bool reuse = false,
  }) {
    final url = playbackUrl(ref, request);
    if (url == null) return;
    if (save && _playing) _saveProgress();
    _needListing(request);
    setState(() {
      _request = request;
      _url = url;
      _watch = request.watchKey == null
          ? null
          : ref.read(watchProvider.notifier);
      _ended = false;
      _countdown = null;
      _nextCancelled = false;
      _position = null;
      _duration = null;
      _pickedFor = null;
      // mpv keeps a chosen track for the next file of the same channel.
      if (!reuse) _manualTracks = false;
      _lastSave = DateTime.now();
      _loadedAt = _now();
      if (_panel == _Panel.zap) _panel = _Panel.none;
      final title = request.title(ref.read(providerTagsProvider));
      final keepOpen = request is ReplayPlayback;
      _session = reuse
          ? _player.reload(
              url,
              title: title,
              wid: _wid,
              start: request.start,
              keepOpen: keepOpen,
            )
          : _player.open(
              url,
              title: title,
              wid: _wid,
              start: request.start,
              volume:
                  _player.state.volume?.round() ?? _appSettings.playerVolume,
              keepOpen: keepOpen,
            );
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

  /// When the current media was loaded; a replay that ends right after
  /// loading has nothing more to give.
  DateTime? _loadedAt;

  /// The session whose end of archive was handled.
  int? _endHandled;

  /// The moment a replay shows at [state]'s position.
  DateTime? _replayPosition(ExternalPlaybackState state) {
    final request = _request;
    if (request is! ReplayPlayback) return null;
    return ReplayTimeline(request.timeshift.floored)
        .clockAt(state.position ?? request.start ?? Duration.zero);
  }

  /// Plays the channel live in the running mpv.
  void _goLive() {
    final channel = _channel;
    if (channel == null || _request is LivePlayback) return;
    ref.read(watchProvider.notifier).recordChannel(channel);
    _switchTo(LivePlayback(channel), reuse: true);
  }

  /// Plays the channel's archive from the real moment [from] in the
  /// running mpv.
  void _replayFrom(DateTime from) {
    final channel = _channel;
    if (channel == null) return;
    final zone = switch (_request) {
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
    final state = _player.state;
    final timeline = ReplayTimeline(request.timeshift.floored);
    if (state.seekable != false && timeline.contains(to, state.duration)) {
      unawaited(_player.seek(timeline.positionOf(to)));
    } else {
      _replayFrom(to);
    }
  }

  void _seekReplayBy(Duration offset) {
    final position = _replayPosition(_player.state);
    if (position != null) _seekReplayTo(position.add(offset));
  }

  /// At the end of the loaded archive: live when close to it (or when
  /// loading again gave nothing more), else the archive again from there,
  /// without an error.
  void _checkEndOfArchive(ExternalPlaybackState state) {
    if (!state.eofReached || _endHandled == state.session) return;
    final position = _replayPosition(state);
    if (position == null) return;
    _endHandled = state.session;
    final step = atEndOfArchive(
      position: position,
      now: _now(),
      loadedAt: _loadedAt,
    );
    scheduleMicrotask(() {
      if (!mounted || !_isMine) return;
      switch (step) {
        case EndOfArchive.goLive:
          _goLive();
        case EndOfArchive.reload:
          _replayFrom(position);
      }
    });
  }

  void _onVideoClick() {
    // Live TV can't pause; a click only brings the controls.
    if (_request.fixedLength && _playing) {
      unawaited(_player.togglePause());
    }
    _controls.activity();
  }

  /// Pointer input on the video area (mpv's window). In fullscreen,
  /// input over the controls, panel or card goes to them.
  void _onPointer(VideoPointerEvent event) {
    if (!mounted || !_showVideo) return;
    if (event is! VideoPointerUp) _controls.activity();
    if (_fullscreen) {
      final forwarder = _forwarder ??= PointerForwarder(
        viewId: View.of(context).viewId,
      );
      final onOverlay = _overlayAt(event.position);
      switch (event) {
        case VideoPointerMove():
          forwarder.move(event.position);
          return;
        case VideoPointerDown() when onOverlay || forwarder.pressed:
          forwarder.down(event.position, event.button);
          return;
        case VideoPointerUp() when forwarder.pressed:
          forwarder.up(event.position);
          return;
        case VideoDoubleClick() when onOverlay:
          return;
        case VideoScroll() when onOverlay:
          forwarder.scroll(event.position, event.dy);
          return;
        default:
      }
    }
    _gestures.handle(event);
  }

  /// Whether [position] is on a part of the fullscreen overlay.
  bool _overlayAt(Offset position) {
    for (final key in [_barKey, _cardKey, _panelKey]) {
      final box = key.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.contains(position)) return true;
      }
    }
    return false;
  }

  void _onControlsChange() {
    if (!mounted) return;
    if (!_controls.visible) _hints.clear();
    if (!_controls.visible && _barFocus.hasFocus) {
      _shortcutsFocus.requestFocus();
    }
    setState(() {});
    _updateCursor();
  }

  /// Keyboard focus in the controls keeps them up.
  void _onBarFocus() => _controls.hold(
    _barFocus,
    _barFocus.hasFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
  );

  void _updateCursor() =>
      unawaited(_embed?.setCursorVisible(!_fullscreen || _controls.visible));

  void _setPanel(_Panel panel) {
    setState(() => _panel = _panel == panel ? _Panel.none : panel);
    _controls.hold(#panel, _panel != _Panel.none);
    if (_panel == _Panel.none) _shortcutsFocus.requestFocus();
  }

  void _setFullscreen(bool value) {
    if (value == _fullscreen || _mode != _Mode.embedded) return;
    setState(() => _fullscreen = value);
    unawaited(_embed?.setFullscreen(value));
    _fullscreenChanged();
  }

  void _fullscreenChanged() {
    _hints.clear();
    _controls.autoHide = _fullscreen;
    if (!_fullscreen) _forwarder?.remove();
    _updateCursor();
  }

  void _onVideoRect(Rect rect) {
    if (mounted && _showVideo) unawaited(_embed?.setRect(rect));
  }

  /// Esc: cancels the countdown, else closes the panel, else leaves
  /// fullscreen.
  VoidCallback? get _onEscape {
    if (_countdown != null) return _cancelNext;
    if (_panel != _Panel.none) return () => _setPanel(_Panel.none);
    if (_fullscreen) return () => _setFullscreen(false);
    return null;
  }

  @override
  void dispose() {
    _player.removeListener(_onChange);
    for (final s in _subscriptions) {
      s.cancel();
    }
    _gestures.dispose();
    _controls.dispose();
    _hints.dispose();
    _forwarder?.remove();
    if (_volumeSave != null) {
      _volumeSave!.cancel();
      final volume = _player.state.volume;
      if (volume != null) {
        final settings = _settings;
        scheduleMicrotask(() {
          try {
            settings.remember((s) => s.copyWith(playerVolume: volume.round()));
          } on StateError {
            // The app is closing; the volume from before stays.
          }
        });
      }
    }
    _shortcutsFocus.dispose();
    _barFocus.dispose();
    _playNowFocus.dispose();
    // When something else took over the player, the video area is
    // already its.
    if (_embed case final embed? when _session == null || _isMine) {
      unawaited(embed.hide());
      unawaited(embed.setCursorVisible(true));
      if (_fullscreen) unawaited(embed.setFullscreen(false));
    }
    if (_session case final session?) {
      if (_isMine && !_ended) _saveProgress(later: true);
      unawaited(_player.stop(session: session));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showStats =
        ref.watch(appSettingsProvider).value?.showPlaybackStats ?? false;
    final Widget body;
    if (_url == null) {
      body = const Center(child: Text('No provider configured'));
    } else {
      body = ListenableBuilder(
        listenable: _player,
        builder: (context, _) {
          final state = _isMine ? _player.state : const ExternalPlaybackState();
          if (_ended) return _buildEnded(context);
          return _showVideo
              ? _buildEmbedded(context, state, showStats)
              : _buildStatus(context, state, showStats);
        },
      );
    }
    final playing = _playing;
    final live = _request is LivePlayback;
    final replay = _request is ReplayPlayback;
    return PlayerShortcuts(
      focusNode: _shortcutsFocus,
      onTogglePause: playing && !live ? _player.togglePause : null,
      onSeek: !playing || !_request.fixedLength
          ? null
          : replay
          ? _seekReplayBy
          : _player.seekBy,
      onVolume: playing ? _player.changeVolume : null,
      onToggleMute: playing ? _player.toggleMute : null,
      onToggleFullscreen: _mode == _Mode.embedded && _showVideo
          ? () => _setFullscreen(!_fullscreen)
          : null,
      onEscape: _onEscape,
      onCycleSubtitles: playing ? _cycleSubtitles : null,
      onZap: _channel != null && _showVideo
          ? () => _setPanel(_Panel.zap)
          : null,
      onNextEpisode: _nextEpisode != null ? _playNext : null,
      onGoLive: replay && _showVideo ? _goLive : null,
      onActivity: _controls.activity,
      child: PlayerHintScope(
        controller: _hintsShown ? _hints : null,
        panelsInLine: _fullscreen,
        panelWidth: _panelWidth,
        child: Scaffold(
          backgroundColor: _showVideo ? AppColors.scrim : null,
          appBar: _fullscreen
              ? null
              : AppBar(
                  // Its own tooltip would open below, behind the video.
                  leading: _showVideo
                      ? PlayerTooltip(
                          message: 'Back (stops playback)',
                          child: IconButton(
                            key: const Key('player.back'),
                            icon: const BackButtonIcon(),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        )
                      : null,
                  title: _buildTitle(),
                ),
          body: body,
        ),
      ),
    );
  }

  static const _stopTooltip = 'Stop and go back';
  static const _nextTooltip = 'Play the next episode (n)';

  /// Whether player tooltips go to the hint line: the video is embedded
  /// (Flutter can't draw over it) and the line shows.
  bool get _hintsShown =>
      _mode == _Mode.embedded &&
      _showVideo &&
      !_ended &&
      (!_fullscreen || _fullscreenHints);

  Widget _buildEmbedded(
    BuildContext context,
    ExternalPlaybackState state,
    bool showStats,
  ) {
    // The native area covers the placeholder; Flutter can't draw over it,
    // so windowed the controls go below and the panels beside it.
    final video = _RectReporter(
      onRect: _onVideoRect,
      child: const ColoredBox(
        key: Key('mpv.video'),
        color: AppColors.scrim,
        child: SizedBox.expand(),
      ),
    );
    if (_fullscreen) return _buildFullscreen(context, state, showStats, video);
    final panel = _buildPanel(state);
    final card = _buildNextCard();
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: video),
              if (panel != null || card != null)
                SizedBox(
                  width: _panelWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (panel != null)
                        Expanded(child: panel)
                      else
                        const Spacer(),
                      if (card != null)
                        Padding(padding: const EdgeInsets.all(8), child: card),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _buildControls(context, state, showStats),
        ColoredBox(
          color: AppColors.scrim,
          child: PlayerHintLine(controller: _hints),
        ),
        ?_buildNowNext(state),
      ],
    );
  }

  /// Now/next of live TV, or at the playing position of a replay.
  Widget? _buildNowNext(
    ExternalPlaybackState state, {
    Color color = AppColors.surface,
  }) => switch (_request) {
    LivePlayback(:final channel) => NowNextBar(channel: channel, color: color),
    ReplayPlayback(:final channel) => NowNextBar(
      channel: channel,
      at: _replayPosition(state),
      color: color,
    ),
    _ => null,
  };

  /// The video fills the screen; the controls (with now/next on live TV),
  /// the panel and the next-episode card are laid out over it and shown
  /// by mpv.
  Widget _buildFullscreen(
    BuildContext context,
    ExternalPlaybackState state,
    bool showStats,
    Widget video,
  ) {
    final panel = _buildPanel(state);
    final card = _buildNextCard();
    final controls = _controls.visible;
    final right = panel == null ? 0.0 : _panelWidth;
    return Stack(
      children: [
        Positioned.fill(child: video),
        if (controls || card != null)
          Positioned(
            left: 0,
            right: right,
            bottom: 0,
            child: OsdMirror(
              id: _Overlay.bottom,
              player: _player,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (card != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: KeyedSubtree(key: _cardKey, child: card),
                    ),
                  if (controls)
                    Material(
                      key: _barKey,
                      color: AppColors.scrim.withValues(alpha: 0.85),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ?_buildNowNext(state, color: Colors.transparent),
                          _buildControls(context, state, showStats),
                          if (_fullscreenHints)
                            PlayerHintLine(controller: _hints),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (panel != null)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: _panelWidth,
            child: OsdMirror(
              id: _Overlay.panel,
              player: _player,
              child: KeyedSubtree(key: _panelKey, child: panel),
            ),
          ),
      ],
    );
  }

  double get _panelWidth => switch (_panel) {
    _Panel.zap => ZapPanel.width,
    _Panel.none when _countdown != null => NextEpisodeCard.width + 16,
    _ => 300,
  };

  Widget? _buildPanel(ExternalPlaybackState state) => switch (_panel) {
    _Panel.none => null,
    _Panel.tracks => PlayerPanelScope(
      child: TrackPanel(
        tracks: state.tracks,
        audioId: state.audioId,
        subtitleId: state.subtitleId,
        onSubtitle: _selectSubtitle,
        onAudio: _selectAudio,
        onClose: () => _setPanel(_Panel.none),
      ),
    ),
    _Panel.favourites => switch (_channel) {
      final channel? => PlayerPanelScope(
        child: FavouritePanel(
          item: liveItemRef(channel),
          name: channel.name,
          onClose: () => _setPanel(_Panel.none),
        ),
      ),
      _ => null,
    },
    _Panel.zap => switch (_channel) {
      final channel? => ZapPanel(
        current: channel,
        onSelect: _zapTo,
        onClose: () => _setPanel(_Panel.none),
      ),
      _ => null,
    },
  };

  /// The app bar title: the provider's label and the clean title, the
  /// full name in the hint line.
  Widget _buildTitle() {
    final tags = ref.watch(providerTagsProvider);
    return switch (_request) {
      LivePlayback(:final channel) => Text(channelDisplayName(channel)),
      ReplayPlayback(:final channel) => ListenableBuilder(
        listenable: _player,
        builder: (context, _) => _ReplayTitle(
          channel: channel,
          position: _isMine ? _replayPosition(_player.state) : null,
        ),
      ),
      MoviePlayback(:final movie) => ProviderTitle(movie.name, player: true),
      EpisodePlayback(:final info, :final episode) => ProviderTitle(
        info.series.name,
        title: _request.title(tags),
        fullName: episodeFullName(info.series, episode),
        player: true,
      ),
    };
  }

  /// [next]'s own name, without the series name and code.
  String _nextTitle(Episode next) => switch (_request) {
    EpisodePlayback(:final info) => episodeDisplayTitle(
      info.series,
      next,
      ref.watch(providerTagsProvider),
    ),
    _ => next.title,
  };

  Widget? _buildNextCard() {
    final seconds = _countdown;
    final next = _nextEpisode;
    if (seconds == null || next == null) return null;
    return NextEpisodeCard(
      next: next,
      title: _nextTitle(next),
      seconds: seconds,
      playNowFocus: _playNowFocus,
      onPlayNow: _playNext,
      onCancel: _cancelNext,
    );
  }

  Widget _buildTracksButton(bool enabled) => PlayerPillButton(
    tooltip: 'Subtitles and audio (s: next subtitles)',
    selected: _panel == _Panel.tracks,
    icon: Icons.subtitles_outlined,
    selectedIcon: Icons.subtitles,
    onPressed: enabled ? () => _setPanel(_Panel.tracks) : null,
  );

  /// The star of the live channel; opens the favourites panel.
  Widget _buildFavouriteButton(LiveStream channel) {
    final favourite = ref.watch(
      favouritesProvider.select((d) => d.isFavourite(liveItemRef(channel))),
    );
    return PlayerPillButton(
      key: const Key('player.favourite'),
      tooltip: favourite
          ? 'Favourite: change my categories'
          : 'Add to favourites',
      selected: favourite,
      icon: Icons.star_border,
      selectedIcon: Icons.star,
      onPressed: () => _setPanel(_Panel.favourites),
    );
  }

  /// The actions at the start of the bar: play/pause for movies and
  /// episodes, then the next episode when there is one. Live TV can't
  /// pause; its slot is kept for a record button.
  List<Widget> _leadingActions(ExternalPlaybackState state, bool starting) => [
    if (_request.fixedLength)
      PlayerTooltip(
        message: state.paused
            ? 'Resume (Space or click the video)'
            : 'Pause (Space or click the video)',
        child: IconButton(
          key: const Key('player.pause'),
          icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
          onPressed: starting ? null : _player.togglePause,
        ),
      ),
    if (_nextEpisode != null)
      PlayerTooltip(
        message: _nextTooltip,
        child: IconButton(
          key: const Key('player.nextEpisodeButton'),
          icon: const Icon(Icons.skip_next),
          onPressed: starting ? null : _playNext,
        ),
      ),
  ];

  Widget _buildControls(
    BuildContext context,
    ExternalPlaybackState state,
    bool showStats,
  ) {
    final starting =
        _mode == _Mode.embedding ||
        state.status == ExternalPlayerStatus.starting;
    // Live TV or a replay: the channel pills.
    final live = _channel;
    final replay = _request is ReplayPlayback;
    final showRemaining = ref.watch(
      appSettingsProvider.select((s) => s.value?.showRemainingTime ?? false),
    );
    return Focus(
      focusNode: _barFocus,
      child: Material(
        color: _fullscreen ? Colors.transparent : AppColors.scrim,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              ..._leadingActions(state, starting),
              const SizedBox(width: 4),
              Expanded(
                child: replay
                    ? _buildReplaySeekBar(state, loading: starting)
                    : starting
                    ? const LinearProgressIndicator(minHeight: 4)
                    : _request.fixedLength
                    ? PlayerSeekBar(
                        position: state.position ?? Duration.zero,
                        duration: state.duration,
                        showRemaining: showRemaining,
                        onToggleRemaining: () => _settings.remember(
                          (s) => s.copyWith(
                            showRemainingTime: !s.showRemainingTime,
                          ),
                        ),
                        onSeek: (p) => unawaited(_player.seek(p)),
                        onDragging: (v) => _controls.hold(#seek, v),
                      )
                    : const SizedBox.shrink(),
              ),
              if (replay) ...[
                const SizedBox(width: 8),
                PlayerTooltip(
                  message:
                      'Go live: watch ${channelDisplayName(live!)} live (l)',
                  child: OutlinedButton.icon(
                    key: const Key('player.goLive'),
                    onPressed: _goLive,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('LIVE'),
                  ),
                ),
              ],
              if (showStats) ...[
                const SizedBox(width: 16),
                _DropReadout(state),
              ],
              if (state.volume case final volume?) ...[
                const SizedBox(width: 8),
                VolumeControl(
                  volume: volume,
                  muted: state.muted,
                  onChanged: (v) => unawaited(_player.setVolume(v)),
                  onToggleMute: () => unawaited(_player.toggleMute()),
                  onDragging: (v) => _controls.hold(#volume, v),
                ),
              ],
              const SizedBox(width: 8),
              if (live != null) ...[
                PlayerPillButton(
                  key: const Key('player.zap'),
                  tooltip: 'Channels: switch channel (c)',
                  selected: _panel == _Panel.zap,
                  icon: Icons.list_alt,
                  onPressed: starting ? null : () => _setPanel(_Panel.zap),
                ),
                const SizedBox(width: 4),
                _buildFavouriteButton(live),
                const SizedBox(width: 4),
              ],
              _buildTracksButton(!starting),
              PlayerTooltip(
                message: _fullscreen
                    ? 'Leave fullscreen (f, Esc or double-click)'
                    : 'Fullscreen (f or double-click, Esc to leave)',
                child: IconButton(
                  key: const Key('player.fullscreen'),
                  icon: Icon(
                    _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                  onPressed: starting
                      ? null
                      : () => _setFullscreen(!_fullscreen),
                ),
              ),
              PlayerTooltip(
                message: _stopTooltip,
                child: IconButton(
                  key: const Key('player.stop'),
                  icon: const Icon(Icons.stop),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              const PlayerClock(),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// The replay's seek bar in clock time, over the programme at the
  /// playing position or, behind live, up to now. While a new stretch of
  /// the archive loads ([loading]) it shows where it will start.
  Widget _buildReplaySeekBar(
    ExternalPlaybackState state, {
    required bool loading,
  }) {
    final request = _request as ReplayPlayback;
    final channel = request.channel;
    final position = loading
        ? request.from
        : _replayPosition(state) ?? request.from;
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
    final toNow = range.to == now;
    return ReplaySeekBar(
      position: position,
      from: range.from,
      to: range.to,
      time: time,
      behind: toNow ? behindLive(position, now) : null,
      loading: loading,
      onSeek: _seekReplayTo,
      onDragging: (v) => _controls.hold(#seek, v),
    );
  }

  Widget _buildStatus(
    BuildContext context,
    ExternalPlaybackState state,
    bool showStats,
  ) {
    final theme = Theme.of(context);
    final failed = state.status == ExternalPlayerStatus.failed;
    final (icon, title) = switch (state.status) {
      ExternalPlayerStatus.failed => (Icons.error_outline, 'Playback failed'),
      ExternalPlayerStatus.playing when state.paused => (
        Icons.pause_circle_outline,
        'Paused in mpv',
      ),
      ExternalPlayerStatus.playing => (
        Icons.open_in_new,
        'Playing in the mpv window',
      ),
      ExternalPlayerStatus.exited => (Icons.stop_circle_outlined, 'mpv closed'),
      _ => (Icons.hourglass_empty, 'Starting mpv…'),
    };
    final position = _request.fixedLength ? state.position : null;
    final duration = state.duration;
    final playing = state.status == ExternalPlayerStatus.playing;
    final live = switch (_request) {
      LivePlayback(:final channel) => channel,
      _ => null,
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: failed ? theme.colorScheme.error : null,
              ),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleLarge),
              if (state.error case final error?) ...[
                const SizedBox(height: 8),
                SelectableText(error, textAlign: TextAlign.center),
              ],
              if (position != null) ...[
                const SizedBox(height: 8),
                Text(
                  duration == null || duration == Duration.zero
                      ? formatDuration(position)
                      : '${formatDuration(position)} / '
                            '${formatDuration(duration)}',
                  key: const Key('mpv.position'),
                ),
              ],
              if (showStats && playing) ...[
                const SizedBox(height: 8),
                _DropReadout(state),
              ],
              if (live != null) ...[
                const SizedBox(height: 16),
                NowNextBar(channel: live),
                const SizedBox(height: 8),
                FavouriteButton(
                  item: liveItemRef(live),
                  name: live.name,
                  labelled: true,
                ),
              ],
              if (playing) ...[
                const SizedBox(height: 8),
                _buildTracksButton(true),
                if (_panel == _Panel.tracks)
                  SizedBox(height: 260, child: _buildPanel(state)),
              ],
              const SizedBox(height: 16),
              failed
                  ? PlayerTooltip(
                      message: live != null ? 'Back to channels' : 'Go back',
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(live != null ? 'Back to channels' : 'Back'),
                      ),
                    )
                  : PlayerTooltip(
                      message: _stopTooltip,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  /// End of an episode without automatic play: offer the next one.
  Widget _buildEnded(BuildContext context) {
    final theme = Theme.of(context);
    final next = _nextEpisode!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text('Episode finished', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(
              '${formatEpisodeCode(next.season, next.episodeNumber)} · '
              '${_nextTitle(next)}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            PlayerTooltip(
              message: _nextTooltip,
              child: FilledButton.icon(
                key: const Key('player.nextEpisode'),
                autofocus: true,
                onPressed: _playNext,
                icon: const Icon(Icons.skip_next),
                label: const Text('Play next episode'),
              ),
            ),
            const SizedBox(height: 8),
            PlayerTooltip(
              message: 'Back to the series',
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to series'),
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// mpv's dropped-frame counters; mpv's own stats overlay isn't reachable
/// when embedded (its key bindings are off).
class _DropReadout extends StatelessWidget {
  const _DropReadout(this.state);

  final ExternalPlaybackState state;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatDrops(state.voDrops, state.decoderDrops),
      key: const Key('mpv.drops'),
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(fontFamily: 'monospace'),
    );
  }
}

/// Reports its child's rectangle in logical pixels of the app view whenever
/// it changes (window resize, fullscreen, route transitions).
class _RectReporter extends SingleChildRenderObjectWidget {
  const _RectReporter({required this.onRect, super.child});

  final ValueChanged<Rect> onRect;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRectReporter(onRect);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRectReporter renderObject,
  ) => renderObject.onRect = onRect;
}

class _RenderRectReporter extends RenderProxyBox {
  _RenderRectReporter(this.onRect);

  ValueChanged<Rect> onRect;
  Rect? _last;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final rect = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    if (rect == _last) return;
    _last = rect;
    SchedulerBinding.instance.addPostFrameCallback((_) => onRect(rect));
  }
}
