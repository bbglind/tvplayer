import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import '../../data/app_settings.dart';
import '../../format.dart';
import '../../player/mpv/external_mpv_player.dart';
import '../../player/mpv/video_embed.dart';
import '../../player/playback_request.dart';
import '../../state/providers.dart';
import '../../state/watch_controller.dart';
import '../epg/now_next.dart';
import '../favourites/favourite_menu.dart';
import '../favourites/favourite_panel.dart';
import '../theme/app_colors.dart';
import 'open_channel.dart';
import 'player_shortcuts.dart';
import 'track_panel.dart';

enum _Mode {
  /// Asking the native side for an X11 window.
  embedding,

  /// mpv draws into the native video area of this screen.
  embedded,

  /// mpv has its own window; this screen only shows its status.
  external,
}

/// Plays a live channel, movie or episode with mpv: embedded in the app
/// window on X11, in a separate mpv window otherwise. Leaving the screen
/// closes mpv; mpv exiting leaves the screen, except at the end of an
/// episode that has a next one, which is then offered.
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

  late final ExternalMpvPlayer _player = ref.read(externalMpvProvider);
  late final VideoEmbed? _embed = ref.read(embedMpvProvider)
      ? ref.read(videoEmbedProvider)
      : null;

  /// For movies and episodes. Read up front: positions are also saved from
  /// [dispose], where [ref] can't be used.
  WatchController? _watch;
  late _Mode _mode = _embed == null ? _Mode.external : _Mode.embedding;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Uri? _url;
  int? _session;
  bool _fullscreen = false;
  double? _seekDragValue;
  bool _showTracks = false;

  /// Whether the favourites panel is open (live channels only). A panel
  /// rather than a menu: nothing can be drawn over the embedded video.
  bool _showFavourites = false;

  /// The episode played to its end and the next one is offered.
  bool _ended = false;

  /// Last known position and duration, kept when mpv stops reporting them.
  Duration? _position;
  Duration? _duration;
  DateTime? _lastSave;

  /// Track ids the automatic choice was made for; it runs again when new
  /// tracks appear (e.g. teletext found later on live TV).
  String? _pickedFor;

  /// The user chose a track; no more automatic choices.
  bool _manualTracks = false;

  PlaybackRequest get _request => widget.request;

  @override
  void initState() {
    super.initState();
    if (_request.watchKey != null) _watch = ref.read(watchProvider.notifier);
    _url = playbackUrl(ref, _request);
    if (_url == null) return;
    _player.addListener(_onChange);
    if (_embed case final embed?) {
      _subscriptions.addAll([
        embed.doubleClicks.listen((_) => _setFullscreen(!_fullscreen)),
        embed.fullscreenChanges.listen((v) {
          if (mounted) setState(() => _fullscreen = v);
        }),
      ]);
    }
    unawaited(_start(_url!));
  }

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
    setState(() {
      _mode = wid == null ? _Mode.external : _Mode.embedded;
      _lastSave = DateTime.now();
      _session = _player.open(
        url,
        title: _request.title,
        wid: wid,
        start: _request.start,
      );
    });
    if (wid == null) unawaited(_embed?.hide());
  }

  bool get _isMine => _session != null && _player.state.session == _session;

  bool get _showVideo =>
      _mode != _Mode.external &&
      !_ended &&
      !(_isMine && _player.state.status == ExternalPlayerStatus.failed);

  Episode? get _nextEpisode => switch (_request) {
    EpisodePlayback(:final info, :final episode) => episodeAfter(info, episode),
    _ => null,
  };

  void _onChange() {
    if (!_isMine || !mounted) return;
    final state = _player.state;
    _trackPosition(state);
    _pickTracks(state);
    switch (state.status) {
      case ExternalPlayerStatus.exited
          when ModalRoute.of(context)?.isCurrent ?? false:
        _saveProgress();
        if (state.endedAtEof && _nextEpisode != null) {
          _setFullscreen(false);
          unawaited(_embed?.hide());
          setState(() => _ended = true);
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

  /// Chooses audio and subtitles once the tracks are known.
  void _pickTracks(ExternalPlaybackState state) {
    if (!state.fileLoaded || state.tracks.isEmpty || _manualTracks) return;
    final signature = [
      for (final t in state.tracks)
        if (t.type != TrackType.video) '${t.type.name}${t.id}',
    ].join(',');
    if (signature == _pickedFor) return;
    _pickedFor = signature;
    final settings = ref.read(appSettingsProvider).value ?? const AppSettings();
    final pick = pickTracks(
      state.tracks,
      settings.trackPreferences,
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

  void _playNext() {
    final next = _nextEpisode;
    if (next == null) return;
    final info = (_request as EpisodePlayback).info;
    final start = resumePosition(ref.read(watchProvider).episode(next.id));
    Navigator.of(context).pushReplacement(
      playbackRoute(ref, EpisodePlayback(info, next, start: start)),
    );
  }

  void _setFullscreen(bool value) {
    if (value == _fullscreen || _mode != _Mode.embedded) return;
    setState(() => _fullscreen = value);
    unawaited(_embed?.setFullscreen(value));
  }

  void _onVideoRect(Rect rect) {
    if (mounted && _showVideo) unawaited(_embed?.setRect(rect));
  }

  @override
  void dispose() {
    _player.removeListener(_onChange);
    for (final s in _subscriptions) {
      s.cancel();
    }
    // When the next episode replaced this screen, the video area is
    // already its.
    if (_embed case final embed? when _session == null || _isMine) {
      unawaited(embed.hide());
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
    final playing = _isMine && !_ended;
    return PlayerShortcuts(
      onTogglePause: playing ? _player.togglePause : null,
      onSeek: playing && _request.fixedLength ? _player.seekBy : null,
      onVolume: playing ? _player.changeVolume : null,
      onToggleFullscreen: _mode == _Mode.embedded && _showVideo
          ? () => _setFullscreen(!_fullscreen)
          : null,
      onExitFullscreen: _fullscreen ? () => _setFullscreen(false) : null,
      onCycleSubtitles: playing ? _cycleSubtitles : null,
      child: Scaffold(
        backgroundColor: _showVideo ? AppColors.scrim : null,
        appBar: _fullscreen ? null : AppBar(title: Text(_request.title)),
        body: body,
      ),
    );
  }

  Widget _buildEmbedded(
    BuildContext context,
    ExternalPlaybackState state,
    bool showStats,
  ) {
    // The native area covers the placeholder; Flutter can't draw over it,
    // so controls go below and the track panel beside it.
    final video = _RectReporter(
      onRect: _onVideoRect,
      child: const ColoredBox(
        key: Key('mpv.video'),
        color: AppColors.scrim,
        child: SizedBox.expand(),
      ),
    );
    if (_fullscreen) return video;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: video),
              if (_showTracks)
                SizedBox(width: 300, child: _buildTrackPanel(state))
              else if (_showFavourites)
                if (_request case LivePlayback(:final channel))
                  SizedBox(
                    width: 300,
                    child: FavouritePanel(
                      item: liveItemRef(channel),
                      name: channel.name,
                      onClose: () => setState(() => _showFavourites = false),
                    ),
                  ),
            ],
          ),
        ),
        _buildControls(context, state, showStats),
        if (_request case LivePlayback(:final channel))
          NowNextBar(channel: channel),
      ],
    );
  }

  Widget _buildTrackPanel(ExternalPlaybackState state) => TrackPanel(
    tracks: state.tracks,
    audioId: state.audioId,
    subtitleId: state.subtitleId,
    onSubtitle: _selectSubtitle,
    onAudio: _selectAudio,
    onClose: () => setState(() => _showTracks = false),
  );

  Widget _buildTracksButton(bool enabled) => IconButton(
    tooltip: 'Subtitles and audio (s: next subtitles)',
    // A secondary pill, as for the other player choices.
    style: IconButton.styleFrom(
      backgroundColor: AppColors.hover,
      disabledBackgroundColor: AppColors.surface,
      shape: const StadiumBorder(),
    ),
    isSelected: _showTracks,
    icon: const Icon(Icons.subtitles_outlined),
    selectedIcon: const Icon(Icons.subtitles),
    onPressed: enabled
        ? () => setState(() {
            _showTracks = !_showTracks;
            _showFavourites = false;
          })
        : null,
  );

  /// The star of the live channel; opens the favourites panel.
  Widget _buildFavouriteButton() {
    final channel = (_request as LivePlayback).channel;
    final favourite = ref.watch(
      favouritesProvider.select((d) => d.isFavourite(liveItemRef(channel))),
    );
    return IconButton(
      key: const Key('player.favourite'),
      tooltip: favourite ? 'Favourite' : 'Add to favourites',
      style: IconButton.styleFrom(
        backgroundColor: AppColors.hover,
        shape: const StadiumBorder(),
      ),
      isSelected: favourite,
      icon: const Icon(Icons.star_border),
      selectedIcon: const Icon(Icons.star),
      onPressed: () => setState(() {
        _showFavourites = !_showFavourites;
        _showTracks = false;
      }),
    );
  }

  Widget _buildControls(
    BuildContext context,
    ExternalPlaybackState state,
    bool showStats,
  ) {
    final starting =
        _mode == _Mode.embedding ||
        state.status == ExternalPlayerStatus.starting;
    return Material(
      color: AppColors.scrim,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: state.paused ? 'Resume' : 'Pause',
              icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
              onPressed: starting ? null : _player.togglePause,
            ),
            Expanded(
              child: starting
                  ? const LinearProgressIndicator(minHeight: 4)
                  : _request.fixedLength
                  ? _buildSeekBar(context, state)
                  : const SizedBox.shrink(),
            ),
            if (showStats) ...[const SizedBox(width: 16), _DropReadout(state)],
            if (state.volume case final volume?) ...[
              const SizedBox(width: 8),
              Icon(
                volume == 0 ? Icons.volume_off : Icons.volume_up,
                size: 18,
                color: AppColors.textSecondary,
              ),
              Text(
                ' ${volume.round()}%',
                key: const Key('mpv.volume'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(width: 8),
            if (_request is LivePlayback) ...[
              _buildFavouriteButton(),
              const SizedBox(width: 4),
            ],
            _buildTracksButton(!starting),
            IconButton(
              tooltip: 'Fullscreen (f or double-click, Esc to leave)',
              icon: const Icon(Icons.fullscreen),
              onPressed: starting ? null : () => _setFullscreen(true),
            ),
            IconButton(
              tooltip: 'Stop',
              icon: const Icon(Icons.stop),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekBar(BuildContext context, ExternalPlaybackState state) {
    final position = state.position ?? Duration.zero;
    final duration = state.duration;
    if (duration == null || duration <= Duration.zero) {
      return Text(
        formatDuration(position),
        key: const Key('mpv.position'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final max = duration.inMilliseconds.toDouble();
    final value = (_seekDragValue ?? position.inMilliseconds.toDouble()).clamp(
      0.0,
      max,
    );
    return Row(
      children: [
        Text(
          formatDuration(Duration(milliseconds: value.round())),
          key: const Key('mpv.position'),
        ),
        Expanded(
          child: Slider(
            value: value,
            max: max,
            onChanged: (v) => setState(() => _seekDragValue = v),
            onChangeEnd: (v) async {
              await _player.seek(Duration(milliseconds: v.round()));
              if (mounted) setState(() => _seekDragValue = null);
            },
          ),
        ),
        Text(formatDuration(duration)),
      ],
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
                if (_showTracks)
                  SizedBox(height: 260, child: _buildTrackPanel(state)),
              ],
              const SizedBox(height: 16),
              failed
                  ? FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: Text(live != null ? 'Back to channels' : 'Back'),
                    )
                  : FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  /// End of an episode: offer the next one.
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
              '${next.title}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('player.nextEpisode'),
              autofocus: true,
              onPressed: _playNext,
              icon: const Icon(Icons.skip_next),
              label: const Text('Play next episode'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to series'),
            ),
          ],
        ),
      ),
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
