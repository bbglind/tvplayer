import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/free_space.dart';
import 'package:tvplayer/data/videos_directory.dart';
import 'package:tvplayer/format.dart';

void main() {
  group('defaultDownloadFolder', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('user_dirs'));
    tearDown(() => dir.deleteSync(recursive: true));

    String folder(Map<String, String> env, [String? userDirs]) {
      final path = '${dir.path}/user-dirs.dirs';
      if (userDirs != null) File(path).writeAsStringSync(userDirs);
      return defaultDownloadFolder(environment: env, userDirsPath: path);
    }

    test('uses XDG_VIDEOS_DIR when set', () {
      expect(
        folder({'HOME': '/home/user', 'XDG_VIDEOS_DIR': r'$HOME/Films/'}),
        '/home/user/Films/tvplayer',
      );
    });

    test('reads user-dirs.dirs', () {
      expect(
        folder({
          'HOME': '/home/user',
        }, '# comment\nXDG_VIDEOS_DIR="\$HOME/Videor"\n'),
        '/home/user/Videor/tvplayer',
      );
    });

    test('falls back to ~/Videos, also when it points at home', () {
      expect(folder({'HOME': '/home/user'}), '/home/user/Videos/tvplayer');
      expect(
        folder({'HOME': '/home/user'}, 'XDG_VIDEOS_DIR="\$HOME/"\n'),
        '/home/user/Videos/tvplayer',
      );
    });
  });

  test('parseDfAvailable reads the available column', () {
    expect(
      parseDfAvailable(
        'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
        '/dev/sda3        244504892 100859684 131152256      44% /\n',
      ),
      131152256 * 1024,
    );
    expect(parseDfAvailable('nonsense'), isNull);
  });

  test('byte sizes read like a file manager', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(640000), '640 KB');
    expect(formatBytes(4200000), '4.2 MB');
    expect(formatBytes(2100000000), '2.1 GB');
    expect(formatBytes(12000000000), '12 GB');
    expect(formatSpeed(4200000), '4.2 MB/s');
    expect(formatElapsed(const Duration(minutes: 72, seconds: 34)), '1:12:34');
  });
}
