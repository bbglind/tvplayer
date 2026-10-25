import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';
import 'package:tvplayer/player/playback_request.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/player/mpv_player_screen.dart';
import 'package:tvplayer/ui/player/open_channel.dart';
import 'package:tvplayer/ui/player/player_shortcuts.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

const _movie = Movie(
  streamId: 7,
  name: 'Test Movie',
  containerExtension: 'mkv',
);

Episode _ep(int season, int number) => Episode(
  id: '${season * 100 + number}',
  season: season,
  episodeNumber: number,
  title: 'Episode $season-$number',
  duration: const Duration(minutes: 40),
);

final _info = SeriesInfo(
  series: const Series(seriesId: 5, name: 'Test Show'),
  seasons: const [],
  episodes: [_ep(1, 1), _ep(1, 2), _ep(2, 1)],
);

const _tracks = [
  MediaTrack(id: 1, type: TrackType.video),
  MediaTrack(id: 1, type: TrackType.audio, lang: 'eng', selected: true),
  MediaTrack(id: 1, type: TrackType.subtitle, lang: 'eng'),
  MediaTrack(id: 2, type: TrackType.subtitle, lang: 'swe'),
];

/// Opens [request] from a button, like the app's screens do.
class _Launcher extends ConsumerWidget {
  const _Launcher(this.request);

  final PlaybackRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      onPressed: () => openPlayback(context, ref, request),
      child: const Text('open'),
    ),
  );
}

void main() {
  late FakeExternalPlayer player;
  late FakeVideoEmbed embed;
  late MemoryWatchStore watch;

  Future<void> open(
    WidgetTester tester,
    PlaybackRequest request, {
    AppSettings settings = const AppSettings(),
    WatchData data = WatchData.empty,
  }) async {
    player = FakeExternalPlayer();
    embed = FakeVideoEmbed();
    watch = MemoryWatchStore(data);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(
            FakeLiveSource(syntheticCatalog(count: 1)),
          ),
          vodSourceProvider.overrideWithValue(FakeVodSource()),
          providerKeyProvider.overrideWithValue('test'),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(true),
          videoEmbedProvider.overrideWithValue(embed),
        ],
        settings: FakeSettingsStorage(settings),
        watch: watch,
        child: _Launcher(request),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the progress bar animates while mpv starts.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  void emit({
    Duration position = const Duration(minutes: 1),
    Duration? duration = const Duration(minutes: 40),
    List<MediaTrack> tracks = const [],
    int? subtitleId,
    ExternalPlayerStatus status = ExternalPlayerStatus.playing,
    bool endedAtEof = false,
  }) => player.emit(
    player.state.copyWith(
      status: status,
      position: () => position,
      duration: () => duration,
      tracks: tracks,
      audioId: () => tracks.isEmpty ? null : 1,
      subtitleId: () => subtitleId,
      fileLoaded: tracks.isNotEmpty,
      endedAtEof: endedAtEof,
    ),
  );

  group('keyboard shortcuts', () {
    testWidgets('control a movie', (tester) async {
      await open(tester, const MoviePlayback(_movie));
      emit(tracks: _tracks, subtitleId: 2);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(player.pauseToggles, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(player.seeks, [
        const Duration(seconds: 10),
        const Duration(seconds: -10),
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(player.volumeChanges, [5, -5]);

      // s: next subtitle track, then off, then the first again.
      player.subtitleSelections.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      expect(player.subtitleSelections, [null, 1, 2]);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(embed.fullscreenCalls, [true]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(embed.fullscreenCalls, [true, false]);
    });

    testWidgets('live TV: no seeking, the rest works', (tester) async {
      await open(tester, const LivePlayback(LiveStream(id: '0', name: 'News')));
      emit(duration: const Duration(seconds: 30));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(player.seeks, isEmpty);
      // Live TV can't pause.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(player.pauseToggles, 0);
      expect(player.volumeChanges, [5]);
    });

    testWidgets('keys typed into a text field are not shortcuts', (
      tester,
    ) async {
      var pauses = 0;
      final seeks = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerShortcuts(
            onTogglePause: () => pauses++,
            onSeek: seeks.add,
            child: const Scaffold(
              body: Column(
                children: [
                  TextField(key: Key('field')),
                  Text('video'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(pauses, 1);

      await tester.tap(find.byKey(const Key('field')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(pauses, 1);
      expect(seeks, isEmpty);
    });
  });

  group('tracks', () {
    testWidgets('are picked from the settings when the file loads', (
      tester,
    ) async {
      await open(tester, const MoviePlayback(_movie));
      emit(tracks: _tracks);
      await tester.pump();
      // Default: Swedish first.
      expect(player.subtitleSelections, [2]);
      // Once only, unless new tracks appear.
      emit(tracks: _tracks, subtitleId: 2);
      await tester.pump();
      expect(player.subtitleSelections, [2]);
    });

    testWidgets('subtitles off by default', (tester) async {
      await open(
        tester,
        const MoviePlayback(_movie),
        settings: const AppSettings(subtitlesOn: false),
      );
      // mpv selected a default subtitle track by itself.
      emit(tracks: _tracks, subtitleId: 1);
      await tester.pump();
      expect(player.subtitleSelections, [null]);
    });

    testWidgets('the menu lists tracks by language; a choice is remembered '
        'for the series', (tester) async {
      await open(tester, EpisodePlayback(_info, _info.episodes.first));
      emit(
        tracks: [
          ..._tracks,
          const MediaTrack(
            id: 3,
            type: TrackType.subtitle,
            lang: 'eng',
            title: 'English (SDH)',
          ),
        ],
        subtitleId: 2,
      );
      await tester.pump();
      await tester.tap(
        find.byTooltip('Subtitles and audio (s: next subtitles)'),
      );
      await tester.pump();
      expect(find.byKey(const Key('player.tracks')), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Svenska'), findsOneWidget);
      expect(find.text('English'), findsNWidgets(2)); // Subtitle and audio.
      expect(find.text('English (SDH)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('player.sub.3')));
      await tester.pump();
      expect(player.subtitleSelections.last, 3);
      await tester.pump();
      final memory = watch.data.seriesTracks[5]!.memory;
      expect(memory.subtitleLanguage, 'en');
      expect(memory.subtitleSdh, isTrue);
    });

    testWidgets('a remembered choice is used for the next episode', (
      tester,
    ) async {
      await open(
        tester,
        EpisodePlayback(_info, _info.episodes[1]),
        data: WatchData.empty.withTracks(
          5,
          SeriesTracks(
            const TrackMemory(subtitlesOff: true),
            DateTime.utc(2026),
          ),
        ),
      );
      await tester.pump();
      emit(tracks: _tracks, subtitleId: 1);
      await tester.pump();
      expect(player.subtitleSelections, [null]);
    });
  });

  group('resume and watched', () {
    testWidgets('movies start at the resume point and save where they '
        'stopped', (tester) async {
      await open(
        tester,
        const MoviePlayback(_movie, start: Duration(minutes: 42)),
      );
      expect(player.opened.single.start, const Duration(minutes: 42));
      expect(player.opened.single.url.path, endsWith('/7.mkv'));
      emit(
        position: const Duration(minutes: 50),
        duration: const Duration(minutes: 90),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Stop'));
      await tester.pumpAndSettle();
      final progress = watch.data.movie(7)!;
      expect(progress.position, const Duration(minutes: 50));
      expect(progress.duration, const Duration(minutes: 90));
      expect(progress.watched, isFalse);
    });

    testWidgets('the end of an episode marks it watched and offers the next '
        'when Play next is off', (tester) async {
      await open(
        tester,
        EpisodePlayback(_info, _info.episodes[1]),
        settings: const AppSettings().copyWith(playNextSeconds: () => null),
      );
      emit(position: const Duration(minutes: 39, seconds: 50));
      await tester.pump();
      emit(
        position: const Duration(minutes: 39, seconds: 50),
        endedAtEof: true,
        status: ExternalPlayerStatus.exited,
      );
      await tester.pumpAndSettle();

      expect(find.byType(MpvPlayerScreen), findsOneWidget);
      expect(find.text('Episode finished'), findsOneWidget);
      expect(find.text('S02E01 · Episode 2-1'), findsOneWidget);
      expect(watch.data.episode('102')!.watched, isTrue);
      expect(watch.data.series[5]!.nextEpisodeId, '201');

      await tester.tap(find.byKey(const Key('player.nextEpisode')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(player.opened, hasLength(2));
      expect(player.opened.last.url.path, endsWith('/201.mkv'));
      expect(player.opened.last.title, 'Test Show · S02E01 · Episode 2-1');
    });

    testWidgets('the end of the last episode leaves the player', (
      tester,
    ) async {
      await open(tester, EpisodePlayback(_info, _info.episodes.last));
      emit(position: const Duration(minutes: 40));
      await tester.pump();
      emit(endedAtEof: true, status: ExternalPlayerStatus.exited);
      await tester.pumpAndSettle();
      expect(find.byType(MpvPlayerScreen), findsNothing);
      expect(watch.data.episode('201')!.watched, isTrue);
    });
  });
}
