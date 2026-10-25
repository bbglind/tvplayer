import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/mpv/mpv_launcher.dart';

import 'fake_mpv.dart';

void main() {
  const config = MpvLaunchConfig(
    title: 'News HD',
    ipcPath: '/run/user/1000/tvplayer-mpv-x/mpv.sock',
  );

  test('builds the external window command line', () {
    expect(config.arguments, [
      '--hwdec=vaapi',
      '--force-window=immediate',
      '--volume-max=100',
      '--title=News HD',
      '--input-ipc-server=/run/user/1000/tvplayer-mpv-x/mpv.sock',
      '--idle=once',
      '--terminal=no',
    ]);
  });

  test('adds --wid for embedding', () {
    const embedded = MpvLaunchConfig(title: 't', ipcPath: '/s', wid: 12345);
    expect(
      embedded.arguments,
      containsAll([
        '--wid=12345',
        '--input-cursor=no',
        '--input-vo-keyboard=no',
        '--cursor-autohide=no',
      ]),
    );
    expect(config.arguments.where((a) => a.startsWith('--wid')), isEmpty);
  });

  test('starts at the saved volume, never above 100', () {
    const c = MpvLaunchConfig(title: 't', ipcPath: '/s', volume: 40);
    expect(c.arguments, contains('--volume=40'));
    const loud = MpvLaunchConfig(title: 't', ipcPath: '/s', volume: 130);
    expect(loud.arguments, contains('--volume=100'));
    expect(config.arguments.where((a) => a.startsWith('--volume=')), isEmpty);
  });

  test('escapes property expansion in the title', () {
    const c = MpvLaunchConfig(title: r'Cost ${path} $5', ipcPath: '/s');
    expect(c.arguments, contains(r'--title=Cost $${path} $$5'));
  });

  test('reports a missing mpv without echoing arguments', () async {
    final error = await launchMpv(
      config,
      start: (exe, args) =>
          throw ProcessException(exe, args, 'No such file or directory', 2),
    ).then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<MpvLaunchException>());
    final e = error! as MpvLaunchException;
    expect(e.notInstalled, isTrue);
    expect(e.message, contains('mpv is not installed'));
    expect(e.message, isNot(contains('--')));
  });

  test('other start failures are not reported as missing', () async {
    final error = await launchMpv(
      config,
      start: (exe, args) =>
          throw ProcessException(exe, args, 'Permission denied', 13),
    ).then<Object?>((_) => null, onError: (Object e) => e);
    expect((error! as MpvLaunchException).notInstalled, isFalse);
  });

  test('passes the config to the starter', () async {
    late String exe;
    late List<String> args;
    final process = FakeProcess();
    final started = await launchMpv(
      config,
      start: (e, a) async {
        exe = e;
        args = a;
        return process;
      },
    );
    expect(started, same(process));
    expect(exe, 'mpv');
    expect(args, config.arguments);
  });
}
