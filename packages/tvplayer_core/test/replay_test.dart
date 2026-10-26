import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  final stockholm = GuideTime.findZone('Europe/Stockholm')!;
  final newYork = GuideTime.findZone('America/New_York')!;
  final utc = GuideTime.findZone('UTC')!;

  group('ReplayWindow', () {
    final now = DateTime.utc(2026, 10, 26, 18);
    const window = ReplayWindow(3);

    test('reaches back the given days', () {
      expect(window.earliest(now), DateTime.utc(2026, 10, 23, 18));
      expect(window.contains(DateTime.utc(2026, 10, 23, 18), now), isTrue);
      expect(window.contains(DateTime.utc(2026, 10, 23, 17, 59), now), isFalse);
      expect(window.contains(now, now), isFalse);
    });

    test('says why a programme cannot be replayed', () {
      ReplayBlock? check(DateTime start, {bool? archived, int days = 3}) =>
          ReplayWindow(days).check(start: start, now: now, archived: archived);
      expect(check(DateTime.utc(2026, 10, 26, 17)), isNull);
      // Still running: replayable from its start.
      expect(check(now.subtract(const Duration(minutes: 1))), isNull);
      expect(
        check(DateTime.utc(2026, 10, 25, 20), days: 0),
        ReplayBlock.noArchive,
      );
      expect(check(now), ReplayBlock.future);
      expect(check(DateTime.utc(2026, 10, 27)), ReplayBlock.future);
      expect(check(DateTime.utc(2026, 10, 23, 17)), ReplayBlock.tooOld);
      expect(
        check(DateTime.utc(2026, 10, 26, 17), archived: false),
        ReplayBlock.notArchived,
      );
      expect(check(DateTime.utc(2026, 10, 26, 17), archived: true), isNull);
    });

    test('guide shift: the real start counts', () {
      // A guide that is an hour early: shift +1 h.
      final time = GuideTime(utc, shiftHours: 1);
      final listed = DateTime.utc(2026, 10, 23, 17, 30); // airs 18:30
      expect(window.check(start: listed, now: now), ReplayBlock.tooOld);
      expect(window.check(start: time.adjust(listed), now: now), isNull);
    });
  });

  group('TimeshiftStart', () {
    test('floors to the minute and keeps the rest as an offset', () {
      final start = TimeshiftStart.at(
        DateTime.utc(2026, 10, 26, 17, 42, 37, 250),
        utc,
      );
      expect(start.floored, DateTime.utc(2026, 10, 26, 17, 42));
      expect(start.offset, const Duration(seconds: 37, milliseconds: 250));
      expect(start.text, '2026-10-26:17-42');
    });

    test('is written in the server zone', () {
      final at = DateTime.utc(2026, 10, 26, 17, 42);
      expect(TimeshiftStart.at(at, stockholm).text, '2026-10-26:18-42');
      expect(TimeshiftStart.at(at, newYork).text, '2026-10-26:13-42');
    });

    test('server zone other than the display zone', () {
      // Shown in Stockholm, the provider reads New York time: the URL
      // carries the same instant in its own zone.
      final display = GuideTime(stockholm);
      final at = DateTime.utc(2026, 10, 26, 19);
      expect(display.formatLocalHm(at), '20:00');
      expect(TimeshiftStart.at(at, newYork).text, '2026-10-26:15-00');
    });

    test('end of summer time: the repeated hour stays apart', () {
      // 02:30 CEST and 02:30 CET on 2026-10-25 read the same; the instants
      // are an hour apart and so are the streams.
      final first = TimeshiftStart.at(
        DateTime.utc(2026, 10, 25, 0, 30),
        stockholm,
      );
      final second = TimeshiftStart.at(
        DateTime.utc(2026, 10, 25, 1, 30),
        stockholm,
      );
      expect(first.text, '2026-10-25:02-30');
      expect(second.text, '2026-10-25:02-30');
      expect(
        second.floored.difference(first.floored),
        const Duration(hours: 1),
      );
      // Around the switch the offset changes.
      expect(
        TimeshiftStart.at(DateTime.utc(2026, 10, 24, 23, 59), stockholm).text,
        '2026-10-25:01-59',
      );
      expect(
        TimeshiftStart.at(DateTime.utc(2026, 10, 25, 2), stockholm).text,
        '2026-10-25:03-00',
      );
    });

    test('start of summer time: 02:00 is skipped', () {
      // 2026-03-29 at 01:00 UTC Stockholm goes from 02:00 CET to 03:00 CEST.
      expect(
        TimeshiftStart.at(DateTime.utc(2026, 3, 29, 0, 59), stockholm).text,
        '2026-03-29:01-59',
      );
      expect(
        TimeshiftStart.at(DateTime.utc(2026, 3, 29, 1), stockholm).text,
        '2026-03-29:03-00',
      );
    });

    test('a local time is turned into UTC first', () {
      final local = DateTime(2026, 10, 26, 12);
      expect(TimeshiftStart.at(local, utc).floored, local.toUtc());
    });
  });

  group('timeshiftMinutes', () {
    final now = DateTime.utc(2026, 10, 26, 18);

    test('everything recorded so far plus a minute', () {
      expect(timeshiftMinutes(DateTime.utc(2026, 10, 26, 17, 30), now), 31);
      expect(timeshiftMinutes(DateTime.utc(2026, 10, 26, 17, 58, 30), now), 3);
      expect(timeshiftMinutes(now, now), 1);
      expect(timeshiftMinutes(now.add(const Duration(minutes: 5)), now), 1);
    });

    test('at most six hours', () {
      expect(timeshiftMinutes(DateTime.utc(2026, 10, 25, 18), now), 360);
    });
  });

  group('ReplayTimeline', () {
    final timeline = ReplayTimeline(DateTime.utc(2026, 10, 26, 17));

    test('maps stream positions to clock time and back', () {
      const position = Duration(minutes: 12, seconds: 5);
      expect(timeline.clockAt(position), DateTime.utc(2026, 10, 26, 17, 12, 5));
      expect(
        timeline.positionOf(DateTime.utc(2026, 10, 26, 17, 12, 5)),
        position,
      );
    });

    test('knows whether a seek stays in the loaded stream', () {
      const length = Duration(minutes: 30);
      expect(
        timeline.contains(DateTime.utc(2026, 10, 26, 17, 10), length),
        isTrue,
      );
      expect(
        timeline.contains(DateTime.utc(2026, 10, 26, 17, 30), length),
        isFalse,
      );
      expect(
        timeline.contains(DateTime.utc(2026, 10, 26, 16, 59), length),
        isFalse,
      );
      expect(
        timeline.contains(DateTime.utc(2026, 10, 26, 17, 10), null),
        isFalse,
      );
    });
  });

  group('end of a loaded archive stream', () {
    final now = DateTime.utc(2026, 10, 26, 18);

    test('near live: go live', () {
      expect(
        atEndOfArchive(
          position: now.subtract(const Duration(seconds: 8)),
          now: now,
        ),
        EndOfArchive.goLive,
      );
      expect(
        behindLive(now.add(const Duration(seconds: 3)), now),
        Duration.zero,
      );
    });

    test('further behind: load again from the position', () {
      expect(
        atEndOfArchive(
          position: now.subtract(const Duration(minutes: 2)),
          now: now,
          loadedAt: now.subtract(const Duration(minutes: 2)),
        ),
        EndOfArchive.reload,
      );
    });

    test('the end again right after loading: go live, no loop', () {
      expect(
        atEndOfArchive(
          position: now.subtract(const Duration(minutes: 2)),
          now: now,
          loadedAt: now.subtract(const Duration(seconds: 1)),
        ),
        EndOfArchive.goLive,
      );
    });
  });

  group('replaySeekRange', () {
    final now = DateTime.utc(2026, 10, 26, 18);
    final earliest = DateTime.utc(2026, 10, 23, 18);

    test('an ended programme covers itself', () {
      final range = replaySeekRange(
        position: DateTime.utc(2026, 10, 25, 20, 10),
        now: now,
        earliest: earliest,
        programStart: DateTime.utc(2026, 10, 25, 20),
        programStop: DateTime.utc(2026, 10, 25, 21),
      );
      expect(range.from, DateTime.utc(2026, 10, 25, 20));
      expect(range.to, DateTime.utc(2026, 10, 25, 21));
    });

    test('behind live: at least two hours up to now', () {
      final range = replaySeekRange(
        position: DateTime.utc(2026, 10, 26, 17, 50),
        now: now,
        earliest: earliest,
        programStart: DateTime.utc(2026, 10, 26, 17, 30),
        programStop: DateTime.utc(2026, 10, 26, 18, 30),
      );
      expect(range.from, DateTime.utc(2026, 10, 26, 16));
      expect(range.to, now);
    });

    test('behind live in a long programme: from its start', () {
      final range = replaySeekRange(
        position: DateTime.utc(2026, 10, 26, 17, 50),
        now: now,
        earliest: earliest,
        programStart: DateTime.utc(2026, 10, 26, 13),
        programStop: DateTime.utc(2026, 10, 26, 19),
      );
      expect(range.from, DateTime.utc(2026, 10, 26, 13));
    });

    test('without a programme; never before the archive', () {
      expect(
        replaySeekRange(
          position: DateTime.utc(2026, 10, 26, 15),
          now: now,
          earliest: earliest,
        ).from,
        DateTime.utc(2026, 10, 26, 15),
      );
      expect(
        replaySeekRange(
          position: DateTime.utc(2026, 10, 26, 17),
          now: now,
          earliest: DateTime.utc(2026, 10, 26, 16, 30),
        ).from,
        DateTime.utc(2026, 10, 26, 16, 30),
      );
    });
  });

  group('withoutReplayMark', () {
    test('drops a trailing mark', () {
      expect(withoutReplayMark('SE: Kanal 1 HD ◉'), 'SE: Kanal 1 HD');
      expect(withoutReplayMark('Channel [*]'), 'Channel');
    });

    test('drops a standalone ◉ anywhere', () {
      expect(withoutReplayMark('SE: ◉ Kanal 1 HD'), 'SE: Kanal 1 HD');
      expect(withoutReplayMark('SE: Kanal 1 ◉ HD+'), 'SE: Kanal 1 HD+');
    });

    test('keeps words with letters or digits', () {
      expect(withoutReplayMark('Kanal 5 +1'), 'Kanal 5 +1');
      expect(withoutReplayMark('Kanal HD+'), 'Kanal HD+');
      expect(withoutReplayMark('Kanal◉'), 'Kanal◉');
    });

    test('never empties a name', () {
      expect(withoutReplayMark('◉'), '◉');
    });
  });
}
