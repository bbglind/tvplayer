import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/external_mpv_player.dart';

import 'fake_mpv.dart';

final _url = Uri.parse('http://192.0.2.1/live/user/pass/101.ts');

void main() {
  late List<FakeMpv> started;
  late ExternalMpvPlayer player;

  setUp(() {
    started = [];
    player = ExternalMpvPlayer(
      start: (exe, args) async {
        final mpv = FakeMpv(args);
        started.add(mpv);
        await mpv.listen();
        return mpv.process;
      },
      quitTimeout: const Duration(milliseconds: 200),
      // Polling has its own test; keep it out of the command logs here.
      statsInterval: const Duration(hours: 1),
    );
  });

  tearDown(() => player.dispose());

  Future<ExternalPlaybackState> waitFor(
    bool Function(ExternalPlaybackState s) test,
  ) async {
    final done = Completer<void>();
    void check() {
      if (test(player.state) && !done.isCompleted) done.complete();
    }

    player.addListener(check);
    check();
    await done.future.timeout(const Duration(seconds: 5));
    player.removeListener(check);
    return player.state;
  }

  test('starts mpv, loads the URL over IPC and reports progress', () async {
    final session = player.open(_url, title: 'News');
    expect(player.state.status, ExternalPlayerStatus.starting);
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);

    final mpv = started.single;
    expect(mpv.arguments, contains('--title=News'));
    expect(mpv.arguments, contains('--hwdec=vaapi'));
    expect(mpv.arguments.join(' '), isNot(contains('192.0.2.1')));
    expect(mpv.arguments.join(' '), isNot(contains('pass')));
    expect(mpv.commands, [
      ['observe_property', 1, 'time-pos'],
      ['observe_property', 2, 'duration'],
      ['observe_property', 3, 'pause'],
      ['observe_property', 4, 'track-list'],
      ['observe_property', 5, 'aid'],
      ['observe_property', 6, 'sid'],
      ['observe_property', 7, 'volume'],
      ['observe_property', 8, 'mute'],
      ['observe_property', 9, 'eof-reached'],
      ['observe_property', 10, 'seekable'],
      ['loadfile', _url.toString()],
    ]);

    mpv.send({
      'event': 'property-change',
      'id': 1,
      'name': 'time-pos',
      'data': 12.5,
    });
    mpv.send({
      'event': 'property-change',
      'id': 2,
      'name': 'duration',
      'data': 600,
    });
    mpv.send({
      'event': 'property-change',
      'id': 3,
      'name': 'pause',
      'data': true,
    });
    final s = await waitFor((s) => s.paused);
    expect(s.session, session);
    expect(s.position, const Duration(milliseconds: 12500));
    expect(s.duration, const Duration(minutes: 10));
  });

  test('embeds into the given window; pause and seek go over IPC', () async {
    player.open(_url, title: 'News', wid: 4242);
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    final mpv = started.single;
    expect(mpv.arguments, contains('--wid=4242'));
    await player.togglePause();
    await player.seek(const Duration(seconds: 90, milliseconds: 500));
    expect(mpv.commands.skip(11), [
      ['cycle', 'pause'],
      ['seek', 90.5, 'absolute'],
    ]);
  });

  test('starts at a resume position, set before the file loads', () async {
    player.open(_url, title: 'Film', start: const Duration(minutes: 42));
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    final commands = started.single.commands;
    final set = commands.indexWhere((c) => c.first == 'set_property');
    expect(commands[set], ['set_property', 'start', '2520.000']);
    expect(commands[set + 1].first, 'loadfile');
  });

  test('reports tracks, selection, volume, loading and the end', () async {
    player.open(_url, title: 'News');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    final mpv = started.single;
    expect(player.state.fileLoaded, isFalse);
    mpv.send({
      'event': 'property-change',
      'id': 4,
      'name': 'track-list',
      'data': [
        {'id': 1, 'type': 'audio', 'lang': 'swe', 'selected': true},
        {'id': 1, 'type': 'sub', 'lang': 'swe', 'codec': 'dvb_teletext'},
        {'id': 2, 'type': 'sub', 'lang': 'eng'},
      ],
    });
    mpv.send({'event': 'property-change', 'id': 5, 'name': 'aid', 'data': 1});
    mpv.send({'event': 'property-change', 'id': 6, 'name': 'sid', 'data': 2});
    mpv.send({
      'event': 'property-change',
      'id': 7,
      'name': 'volume',
      'data': 85.0,
    });
    mpv.send({
      'event': 'property-change',
      'id': 8,
      'name': 'mute',
      'data': true,
    });
    mpv.send({'event': 'file-loaded'});
    var s = await waitFor((s) => s.fileLoaded && s.volume != null);
    expect(s.muted, isTrue);
    expect(s.audioTracks.single.language?.code, 'sv');
    expect(s.subtitleTracks.map((t) => t.id), [1, 2]);
    expect(s.audioId, 1);
    expect(s.subtitleId, 2);
    expect(s.volume, 85);
    expect(s.endedAtEof, isFalse);

    // Subtitles off: mpv sends false.
    mpv.send({
      'event': 'property-change',
      'id': 6,
      'name': 'sid',
      'data': false,
    });
    s = await waitFor((s) => s.subtitleId == null);

    mpv.send({'event': 'end-file', 'reason': 'eof'});
    s = await waitFor((s) => s.endedAtEof);
    expect(s.error, isNull);
  });

  test('track, volume and relative seek commands go over IPC', () async {
    player.open(_url, title: 'News');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    final mpv = started.single;
    final before = mpv.commands.length;
    await player.setAudioTrack(2);
    await player.setSubtitleTrack(3);
    await player.setSubtitleTrack(null);
    await player.changeVolume(-5);
    await player.setVolume(42.5);
    await player.setVolume(130);
    await player.toggleMute();
    await player.seekBy(const Duration(seconds: -10));
    expect(await player.addSubtitleFile('/tmp/subs.srt'), isTrue);
    expect(
      await player.addSubtitleFile(
        '/tmp/subs.sv.srt',
        title: 'Svenska',
        lang: 'sv',
      ),
      isTrue,
    );
    expect(mpv.commands.skip(before), [
      ['set_property', 'aid', 2],
      ['set_property', 'sid', 3],
      ['set_property', 'sid', 'no'],
      ['add', 'volume', -5],
      ['set_property', 'volume', 42.5],
      ['set_property', 'volume', 100.0],
      ['cycle', 'mute'],
      ['seek', -10.0, 'relative'],
      ['sub-add', '/tmp/subs.srt', 'select'],
      ['sub-add', '/tmp/subs.sv.srt', 'select', 'Svenska', 'sv'],
    ]);
  });

  test('starts at the given volume', () async {
    player.open(_url, title: 'News', volume: 35);
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    expect(started.single.arguments, contains('--volume=35'));
  });

  test('overlays: written to a file in the socket directory, kept for the '
      'next mpv, removed on hide', () async {
    final bgra = Uint8List.fromList(List.filled(2 * 3 * 4, 7));
    // Before mpv runs: kept, sent once it has started.
    player.showOverlay(1, x: 10, y: 20, width: 2, height: 3, bgra: bgra);
    player.open(_url, title: 'News');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    final mpv = started.single;
    Future<List<Object?>> overlayAdd(FakeMpv m) async {
      for (var i = 0; i < 100; i++) {
        final add = m.commands.where((c) => c.first == 'overlay-add');
        if (add.isNotEmpty) return add.last;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('no overlay-add');
    }

    final add = await overlayAdd(mpv);
    final path = add[4]! as String;
    expect(add, [
      'overlay-add', 1, 10, 20, path, 0, 'bgra', 2, 3, 8, //
    ]);
    final dir = mpv.ipcPath.substring(0, mpv.ipcPath.lastIndexOf('/'));
    expect(path, startsWith(dir));
    expect(File(path).readAsBytesSync(), bgra);

    // A new mpv gets the overlay again.
    player.open(_url, title: 'Other');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    await overlayAdd(started.last);

    player.hideOverlay(1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(started.last.commands.last, ['overlay-remove', 1]);
  });

  test('adding a subtitle file without mpv running fails quietly', () async {
    expect(await player.addSubtitleFile('/tmp/subs.srt'), isFalse);
  });

  test('polls the dropped-frame counters', () async {
    final p = ExternalMpvPlayer(
      start: (exe, args) async {
        final mpv = FakeMpv(args);
        started.add(mpv);
        await mpv.listen();
        return mpv.process;
      },
      statsInterval: const Duration(milliseconds: 20),
    );
    addTearDown(p.dispose);
    p.open(_url, title: 'News');
    final mpv = await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return started.isEmpty;
    }).then((_) => started.single);

    // Unavailable before the first video frame: unknown, not zero.
    await mpv.loaded;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(p.state.voDrops, isNull);
    expect(p.state.decoderDrops, isNull);

    mpv.properties['frame-drop-count'] = 0;
    mpv.properties['decoder-frame-drop-count'] = 0;
    while (p.state.voDrops == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect((p.state.voDrops, p.state.decoderDrops), (0, 0));

    mpv.properties['frame-drop-count'] = 7;
    mpv.properties['decoder-frame-drop-count'] = 2;
    while (p.state.voDrops != 7) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(p.state.decoderDrops, 2);
    expect(
      mpv.commands,
      contains(equals(['get_property', 'frame-drop-count'])),
    );
    expect(
      mpv.commands,
      contains(equals(['get_property', 'decoder-frame-drop-count'])),
    );

    // Polling stops with mpv.
    await p.stop();
    final count = mpv.commands.length;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(mpv.commands.length, count);
  });

  test('reports mpv exiting', () async {
    player.open(_url, title: 'News');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    started.single.process.exit();
    await waitFor((s) => s.status == ExternalPlayerStatus.exited);
    expect(player.state.error, isNull);
  });

  test('opening another channel quits the previous mpv first', () async {
    final first = player.open(_url, title: 'One');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    final second = player.open(_url, title: 'Two');
    expect(second, greaterThan(first));
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);

    expect(started, hasLength(2));
    expect(started[0].commands.last, ['quit']);
    expect(await started[0].process.exitCode, 0);
    // The old mpv exiting doesn't end the new session.
    expect(player.state.session, second);
    expect(player.state.status, ExternalPlayerStatus.playing);
  });

  test('stop quits mpv; a stale session id is ignored', () async {
    final session = player.open(_url, title: 'News');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    await player.stop(session: session - 1);
    expect(started.single.commands.last, isNot(['quit']));
    await player.stop(session: session);
    expect(started.single.commands.last, ['quit']);
    await waitFor((s) => s.status == ExternalPlayerStatus.exited);
  });

  test('kills mpv when it ignores quit', () async {
    final hung = FakeProcess();
    final p = ExternalMpvPlayer(
      start: (exe, args) async {
        final mpv = FakeMpv(args);
        await mpv.listen();
        // Answers IPC but never exits on its own.
        unawaited(hung.exitCode.then((_) => mpv.process.exit()));
        return hung;
      },
      quitTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(p.dispose);
    p.open(_url, title: 'News');
    while (p.state.status != ExternalPlayerStatus.playing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await p.stop();
    expect(hung.killSignals, isNotEmpty);
  });

  test('a playback error is kept when mpv exits', () async {
    player.open(_url, title: 'News');
    await waitFor((s) => s.status == ExternalPlayerStatus.playing);
    final mpv = started.single;
    mpv.send({
      'event': 'end-file',
      'reason': 'error',
      'file_error': 'loading failed for $_url',
    });
    mpv.process.exit();
    final s = await waitFor((s) => s.status == ExternalPlayerStatus.failed);
    expect(s.error, contains('mpv could not play the stream'));
    expect(s.error, isNot(contains('192.0.2.1')));
    expect(s.error, isNot(contains('pass')));
  });

  test('missing mpv fails with a clear message', () async {
    final p = ExternalMpvPlayer(
      start: (exe, args) async =>
          throw ProcessException(exe, args, 'No such file or directory', 2),
    );
    addTearDown(p.dispose);
    p.open(_url, title: 'News');
    while (p.state.status != ExternalPlayerStatus.failed) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(p.state.error, contains('mpv is not installed'));
  });

  group('reload', () {
    final timeshift = Uri.parse(
      'http://192.0.2.1/timeshift/user/pass/46/2026-10-26:18-15/101.ts',
    );

    test('replaces the media in the running mpv: the old stream closes '
        'first, no second mpv', () async {
      final first = player.open(_url, title: 'News', volume: 70);
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      final mpv = started.single;
      final before = mpv.commands.length;

      final second = player.reload(
        timeshift,
        title: r'News $1',
        start: const Duration(seconds: 37),
        keepOpen: true,
      );
      expect(second, first + 1);
      expect(player.state.session, second);
      expect(player.state.status, ExternalPlayerStatus.starting);
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      expect(started, hasLength(1));
      expect(mpv.commands.skip(before), [
        ['set_property', 'start', '37.000'],
        ['set_property', 'keep-open', 'yes'],
        ['set_property', 'title', r'News $$1'],
        ['loadfile', timeshift.toString(), 'replace'],
      ]);

      // Back to live: no start, no keep-open.
      player.reload(_url, title: 'News');
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      expect(mpv.commands.skip(before + 4).take(2), [
        ['set_property', 'start', 'none'],
        ['set_property', 'keep-open', 'no'],
      ]);
    });

    test('a new file forgets the old position; eof-reached and seekable '
        'are reported', () async {
      player.open(timeshift, title: 'News', keepOpen: true);
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      final mpv = started.single;
      expect(mpv.commands.where((c) => c.first == 'set_property'), [
        ['set_property', 'keep-open', 'yes'],
      ]);
      mpv.send({
        'event': 'property-change',
        'id': 1,
        'name': 'time-pos',
        'data': 30,
      });
      mpv.send({
        'event': 'property-change',
        'id': 10,
        'name': 'seekable',
        'data': true,
      });
      mpv.send({
        'event': 'property-change',
        'id': 9,
        'name': 'eof-reached',
        'data': true,
      });
      var s = await waitFor((s) => s.eofReached);
      expect(s.seekable, isTrue);
      expect(s.position, const Duration(seconds: 30));

      mpv.send({'event': 'start-file'});
      s = await waitFor((s) => !s.eofReached);
      expect(s.position, isNull);
      expect(s.seekable, isNull);
    });

    test('without a running mpv it opens one', () async {
      player.reload(_url, title: 'News');
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      expect(started, hasLength(1));
      expect(started.single.commands.last, ['loadfile', _url.toString()]);
    });

    test('mpv errors are redacted for the reloaded URL', () async {
      player.open(_url, title: 'News');
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      player.reload(timeshift, title: 'News');
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      started.single.send({
        'event': 'end-file',
        'reason': 'error',
        'file_error': 'loading failed for $timeshift',
      });
      final s = await waitFor((s) => s.error != null);
      expect(s.error, isNot(contains('192.0.2.1')));
      expect(s.error, isNot(contains('pass')));
    });
  });

  group('freezeFrame', () {
    test('saves the frame and shows it in place of the stream', () async {
      final first = player.open(_url, title: 'News');
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      final mpv = started.single;
      final before = mpv.commands.length;
      final session = player.freezeFrame();
      expect(session, first + 1);
      await waitFor((s) => s.status == ExternalPlayerStatus.playing);
      final commands = mpv.commands.skip(before).toList();
      final shot = commands.first;
      expect(shot.first, 'screenshot-to-file');
      final path = shot[1]! as String;
      expect(path, endsWith('/paused.jpg'));
      expect(shot[2], 'video');
      expect(commands.skip(1), [
        ['set_property', 'start', 'none'],
        ['set_property', 'keep-open', 'yes'],
        ['set_property', 'image-display-duration', 'inf'],
        ['loadfile', path, 'replace'],
      ]);
      expect(started, hasLength(1));
    });

    test('nothing to freeze without mpv', () {
      expect(player.freezeFrame(), isNull);
    });
  });
}
