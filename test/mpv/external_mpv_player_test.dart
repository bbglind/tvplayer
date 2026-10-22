import 'dart:io';
import 'dart:async';

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
    expect(mpv.commands.skip(4), [
      ['cycle', 'pause'],
      ['seek', 90.5, 'absolute'],
    ]);
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
}
