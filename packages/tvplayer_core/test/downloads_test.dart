import 'dart:convert';

import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  group('file names', () {
    test('drop unsafe characters, dots and extra spaces', () {
      expect(safeFileName('A/B: C?  "D" <E>|F*'), 'A B C D E F');
      expect(safeFileName('..hidden. '), 'hidden');
      expect(safeFileName('tab\there\nnew'), 'tab here new');
      expect(safeFileName(' / ? '), 'Untitled');
    });

    test('are cut to a byte length without splitting characters', () {
      final name = safeFileName('å' * 100, maxBytes: 11);
      expect(name, 'å' * 5);
      expect(utf8.encode(name).length, lessThanOrEqualTo(11));
    });

    test('keep a plausible provider extension', () {
      expect(safeExtension('MKV', fallback: 'mp4'), 'mkv');
      expect(safeExtension('.mp4', fallback: 'ts'), 'mp4');
      expect(safeExtension('../x', fallback: 'mp4'), 'mp4');
      expect(safeExtension(null, fallback: 'mp4'), 'mp4');
      expect(safeExtension('toolong', fallback: 'ts'), 'ts');
    });

    test('use sensible folders', () {
      expect(
        moviePath('Title: Part 2', 2020, 'mkv'),
        'Movies/Title Part 2 (2020).mkv',
      );
      expect(moviePath('Title', null, 'mp4'), 'Movies/Title.mp4');
      expect(
        episodePath('Show', 1, 2, 'Pilot', 'mkv'),
        'Series/Show/Season 01/Show - S01E02 - Pilot.mkv',
      );
      expect(
        episodePath('Show', 10, 3, null, 'mp4'),
        'Series/Show/Season 10/Show - S10E03.mp4',
      );
      expect(
        recordingPath(
          'News 24',
          'Evening news',
          DateTime(2026, 10, 27, 20, 5),
          'ts',
        ),
        'Recordings/News 24 - Evening news - 2026-10-27 20-05.ts',
      );
    });

    test('get a number when taken', () {
      final taken = {'/d/Movies/A.mkv', '/d/Movies/A (2).mkv'};
      expect(
        uniquePath('/d/Movies/A.mkv', taken.contains),
        '/d/Movies/A (3).mkv',
      );
      expect(uniquePath('/d/Movies/B.mkv', taken.contains), '/d/Movies/B.mkv');
      expect(
        uniquePath('/d.x/Movies/C', {'/d.x/Movies/C'}.contains),
        '/d.x/Movies/C (2)',
      );
    });
  });

  group('ReplayClip', () {
    final now = DateTime.utc(2026, 10, 27, 22);
    final start = DateTime.utc(2026, 10, 27, 19);
    final stop = DateTime.utc(2026, 10, 27, 20);

    ReplayClip clip({
      int days = 3,
      Duration adjust = Duration.zero,
      DateTime? at,
      DateTime? from,
    }) => ReplayClip.forProgramme(
      start: from ?? start,
      stop: stop,
      startMargin: const Duration(minutes: 2),
      endMargin: const Duration(minutes: 15),
      window: ReplayWindow(days),
      now: at ?? now,
      adjust: adjust,
    );

    test('adds the margins', () {
      final c = clip();
      expect(c.from, DateTime.utc(2026, 10, 27, 18, 58));
      expect(c.to, DateTime.utc(2026, 10, 27, 20, 15));
      expect(c.length, const Duration(minutes: 77));
      expect(c.isReady(now), isTrue);
    });

    test('moves by an adjustment', () {
      final c = clip(adjust: const Duration(hours: -1));
      expect(c.from, DateTime.utc(2026, 10, 27, 17, 58));
      expect(c.to, DateTime.utc(2026, 10, 27, 19, 15));
    });

    test('stays inside the archive', () {
      final c = clip(at: DateTime.utc(2026, 10, 28, 19, 1), days: 1);
      expect(c.from, DateTime.utc(2026, 10, 27, 19, 1));
    });

    test("isn't ready before its end margin has passed", () {
      final c = clip(at: DateTime.utc(2026, 10, 27, 20, 5));
      expect(c.isReady(DateTime.utc(2026, 10, 27, 20, 5)), isFalse);
      expect(c.isReady(DateTime.utc(2026, 10, 27, 20, 15)), isTrue);
    });

    test('becomes whole minutes in an item', () {
      final c = clip();
      final item = DownloadItem(
        id: 'r',
        kind: DownloadKind.replay,
        title: 'News',
        sourceId: '7',
        extension: 'ts',
        path: '/r.ts',
        addedAt: now,
        from: c.from,
        to: c.to.add(const Duration(seconds: 20)),
      );
      expect(item.minutes, 78);
      expect(item.watchKey, isNull);
    });
  });

  group('recordingEnd', () {
    final start = DateTime.utc(2026, 10, 27, 20, 30);
    DateTime end(DateTime? programmeEnd, {int maxHours = 4}) => recordingEnd(
      start: start,
      programmeEnd: programmeEnd,
      endMargin: const Duration(minutes: 15),
      maxLength: Duration(hours: maxHours),
    );

    test('is the programme end plus the margin', () {
      expect(
        end(DateTime.utc(2026, 10, 27, 21)),
        DateTime.utc(2026, 10, 27, 21, 15),
      );
    });

    test('is capped at the maximum length', () {
      expect(
        end(DateTime.utc(2026, 10, 28, 3), maxHours: 2),
        DateTime.utc(2026, 10, 27, 22, 30),
      );
    });

    test('is the maximum length without a guide', () {
      expect(end(null), DateTime.utc(2026, 10, 28, 0, 30));
      expect(
        end(DateTime.utc(2026, 10, 27, 20)),
        DateTime.utc(2026, 10, 28, 0, 30),
      );
    });
  });

  group('SpacePolicy', () {
    const policy = SpacePolicy(5 * bytesPerGb);

    test('warns a gigabyte before the minimum and stops at it', () {
      expect(policy.check(10 * bytesPerGb), SpaceStatus.ok);
      expect(policy.check(6 * bytesPerGb), SpaceStatus.ok);
      expect(policy.check(6 * bytesPerGb - 1), SpaceStatus.low);
      expect(policy.check(5 * bytesPerGb), SpaceStatus.low);
      expect(policy.check(5 * bytesPerGb - 1), SpaceStatus.full);
    });

    test('counts what is still to be written', () {
      expect(
        policy.check(10 * bytesPerGb, needed: 4 * bytesPerGb + 1),
        SpaceStatus.low,
      );
      expect(
        policy.check(10 * bytesPerGb, needed: 6 * bytesPerGb),
        SpaceStatus.full,
      );
    });
  });

  test('TransferRate averages over its window', () {
    final rate = TransferRate();
    final t = DateTime.utc(2026);
    expect(rate.bytesPerSecond, isNull);
    rate.add(t, 0);
    rate.add(t.add(const Duration(seconds: 2)), 2000);
    expect(rate.bytesPerSecond, 1000);
    expect(rate.timeLeft(5000), const Duration(seconds: 5));
    for (var s = 3; s <= 20; s++) {
      rate.add(t.add(Duration(seconds: s)), 2000 + (s - 2) * 4000);
    }
    expect(rate.bytesPerSecond, closeTo(4000, 1));
  });

  test('DownloadItem survives JSON without URLs', () {
    final item = DownloadItem(
      id: 'e1',
      kind: DownloadKind.episode,
      title: 'Show',
      sourceId: '501',
      extension: 'mkv',
      path: '/v/Series/Show/Season 01/Show - S01E02.mkv',
      addedAt: DateTime.utc(2026, 10, 27, 8),
      label: 'NF',
      seriesId: 9,
      season: 1,
      episode: 2,
      status: DownloadStatus.paused,
      pauseReason: PauseReason.user,
      bytes: 100,
      totalBytes: 1000,
    );
    final back = DownloadItem.fromJson(jsonDecode(jsonEncode(item.toJson())))!;
    expect(back.toJson(), item.toJson());
    expect(back.watchKey, episodeKey('501'));
    expect(back.fraction, 0.1);
    expect(DownloadItem.fromJson({'id': 'x'}), isNull);
    expect(DownloadItem.fromJson('nope'), isNull);
  });
}
