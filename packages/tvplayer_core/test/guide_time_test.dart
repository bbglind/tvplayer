import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fixtures.dart';

void main() {
  // Sweden leaves summer time on 2026-10-25: 03:00 CEST (+02:00) becomes
  // 02:00 CET (+01:00) at 01:00 UTC, so 02:00-03:00 local happens twice.
  final stockholm = GuideTime.named('Europe/Stockholm');

  group('XMLTV offsets are read, not assumed', () {
    test('summer time (+0200) and winter time (+0100)', () {
      expect(
        XmltvParser.parseTime('20261025020000 +0200'),
        DateTime.utc(2026, 10, 25, 0),
      );
      expect(
        XmltvParser.parseTime('20261025020000 +0100'),
        DateTime.utc(2026, 10, 25, 1),
      );
    });
  });

  group('Europe/Stockholm around the end of summer time', () {
    test('uses CEST before and CET after the switch', () {
      expect(stockholm.offsetAt(DateTime.utc(2026, 10, 25, 0, 59)), '+02:00');
      expect(stockholm.offsetAt(DateTime.utc(2026, 10, 25, 1)), '+01:00');
    });

    test('programme before the switch', () {
      final start = XmltvParser.parseTime('20261025013000 +0200')!;
      expect(start, DateTime.utc(2026, 10, 24, 23, 30));
      expect(stockholm.formatHm(start), '01:30');
    });

    test('the repeated hour shows the same clock time twice', () {
      final first = DateTime.utc(2026, 10, 25, 0, 30); // 02:30 CEST
      final second = DateTime.utc(2026, 10, 25, 1, 30); // 02:30 CET
      expect(stockholm.formatHm(first), '02:30');
      expect(stockholm.formatHm(second), '02:30');
      expect(second.difference(first), const Duration(hours: 1));
    });

    test('programme after the switch', () {
      final start = XmltvParser.parseTime('20261025023000 +0100')!;
      expect(start, DateTime.utc(2026, 10, 25, 1, 30));
      expect(stockholm.formatHm(start), '02:30');
      expect(stockholm.toDisplay(start).timeZoneName, 'CET');
    });

    test('programme running across the switch', () {
      final start = XmltvParser.parseTime('20261025023000 +0200')!;
      final stop = XmltvParser.parseTime('20261025023000 +0100')!;
      final program = EpgProgram(
        channelId: 'kanal1.example',
        title: 'Across',
        start: start,
        stop: stop,
      );
      // Same clock time at both ends, yet it really lasts an hour.
      expect(stockholm.formatRange(start, stop), '02:30–02:30');
      expect(program.duration, const Duration(hours: 1));
      expect(program.isAiringAt(DateTime.utc(2026, 10, 25, 1)), isTrue);
      expect(stockholm.toDisplay(start).timeZoneName, 'CEST');
      expect(stockholm.toDisplay(stop).timeZoneName, 'CET');
    });

    test('a night across the switch lasts 7 hours, not 6', () {
      final start = XmltvParser.parseTime('20261025000000 +0200')!;
      final stop = XmltvParser.parseTime('20261025060000 +0100')!;
      expect(stockholm.formatRange(start, stop), '00:00–06:00');
      expect(stop.difference(start), const Duration(hours: 7));
    });

    test('the day of the switch has 25 hours', () {
      final day = stockholm.startOfDay(DateTime.utc(2026, 10, 25, 12));
      final next = stockholm.startOfDay(DateTime.utc(2026, 10, 26, 12));
      expect(day, DateTime.utc(2026, 10, 24, 22));
      expect(next, DateTime.utc(2026, 10, 25, 23));
      expect(next.difference(day), const Duration(hours: 25));
    });

    test('start of hour in both copies of 02:00-03:00', () {
      expect(
        stockholm.startOfHour(DateTime.utc(2026, 10, 25, 0, 15)),
        DateTime.utc(2026, 10, 25, 0),
      );
      expect(
        stockholm.startOfHour(DateTime.utc(2026, 10, 25, 1, 15)),
        DateTime.utc(2026, 10, 25, 1),
      );
    });

    test('summer and winter evenings both show 20:00', () {
      expect(stockholm.formatHm(DateTime.utc(2026, 7, 15, 18)), '20:00');
      expect(stockholm.formatHm(DateTime.utc(2026, 12, 15, 19)), '20:00');
    });

    test('guide from XMLTV: now and next during the repeated hour', () async {
      final guide = await buildGuideFromXmltv(
        fixtureBytes('epg_dst.xml'),
        fetchedAt: DateTime.utc(2026, 10, 24),
      );
      const channel = LiveStream(
        id: '1',
        name: 'Kanal 1',
        epgChannelId: 'kanal1.example',
      );
      // 02:45 CEST: the programme across the switch is on.
      final (:now, :next) = guide.nowAndNext(
        channel,
        DateTime.utc(2026, 10, 25, 0, 45),
      );
      expect(now?.title, 'Across The Switch');
      expect(stockholm.formatRange(now!.start, now.stop), '02:30–02:30');
      expect(next?.title, 'After The Switch');
      expect(stockholm.formatRange(next!.start, next.stop), '02:30–03:30');
    });
  });

  group('other zones', () {
    test('America/New_York leaves summer time on 1 November 2026', () {
      final newYork = GuideTime.named('America/New_York');
      expect(newYork.formatHm(DateTime.utc(2026, 11, 1, 5, 30)), '01:30');
      expect(newYork.formatHm(DateTime.utc(2026, 11, 1, 6, 30)), '01:30');
      expect(newYork.offsetAt(DateTime.utc(2026, 11, 1, 5, 30)), '-04:00');
      expect(newYork.offsetAt(DateTime.utc(2026, 11, 1, 6, 30)), '-05:00');
    });

    test('UTC and unknown zones', () {
      expect(
        GuideTime.named('UTC').formatHm(DateTime.utc(2026, 1, 1, 7)),
        '07:00',
      );
      final unknown = GuideTime.named('Nowhere/Invalid');
      expect(unknown.zoneName, 'UTC');
      expect(GuideTime.findZone('Nowhere/Invalid'), isNull);
    });

    test('zone list contains IANA names', () {
      expect(GuideTime.zoneNames(), containsAll(['Europe/Stockholm', 'UTC']));
    });
  });

  group('shift', () {
    test('moves programme times by whole hours', () {
      final shifted = GuideTime.named('Europe/Stockholm', shiftHours: 1);
      final start = DateTime.utc(2026, 7, 15, 18); // 20:00 CEST.
      expect(shifted.formatHm(start), '21:00');
      expect(shifted.adjust(start), DateTime.utc(2026, 7, 15, 19));
      expect(shifted.unadjust(DateTime.utc(2026, 7, 15, 19)), start);

      final back = GuideTime.named('Europe/Stockholm', shiftHours: -2);
      expect(back.formatHm(start), '18:00');
    });

    test('shift is applied before the zone, across the switch', () {
      final shifted = GuideTime.named('Europe/Stockholm', shiftHours: 1);
      // 00:30 UTC + 1 h = 01:30 UTC, which is 02:30 CET.
      final display = shifted.toDisplay(DateTime.utc(2026, 10, 25, 0, 30));
      expect(display.hour, 2);
      expect(display.timeZoneName, 'CET');
    });

    test('real moments are not shifted', () {
      final shifted = GuideTime.named('Europe/Stockholm', shiftHours: 3);
      expect(shifted.formatLocalHm(DateTime.utc(2026, 7, 15, 18)), '20:00');
    });
  });
  group('tonight', () {
    // Stockholm local time on 2026-10-26 (CET, +01:00).
    DateTime local(int day, int hour, [int minute = 0]) =>
        DateTime.utc(2026, 10, day, hour - 1, minute);

    test('20:00 the same day until 23:00', () {
      for (final now in [local(26, 14), local(26, 22, 59), local(27, 0, 30)]) {
        final t = stockholm.tonight(now);
        expect(stockholm.local(t.at).hour, 20);
        expect(stockholm.local(t.at).day, stockholm.local(now).day);
        expect(t.tomorrow, isFalse);
      }
    });

    test('tomorrow evening from 23:00', () {
      for (final now in [local(26, 23), local(26, 23, 30)]) {
        final t = stockholm.tonight(now);
        expect(t.at, DateTime.utc(2026, 10, 27, 19));
        expect(t.tomorrow, isTrue);
      }
    });

    test('on the day summer time ends', () {
      // 02:45 CEST: tonight's 20:00 is already CET.
      final t = stockholm.tonight(DateTime.utc(2026, 10, 25, 0, 45));
      expect(t.at, DateTime.utc(2026, 10, 25, 19));
    });

    test('in another zone', () {
      final newYork = GuideTime.named('America/New_York');
      // 14:00 EDT (-04:00).
      final t = newYork.tonight(DateTime.utc(2026, 10, 26, 18));
      expect(t.at, DateTime.utc(2026, 10, 27, 0));
      expect(t.tomorrow, isFalse);
    });

    test('the shift does not move it', () {
      final shifted = GuideTime.named('Europe/Stockholm', shiftHours: 2);
      expect(
        shifted.tonight(local(26, 14)).at,
        stockholm.tonight(local(26, 14)).at,
      );
    });
  });
}
