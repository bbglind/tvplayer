import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

EpgProgram _p(String title, int startHour, int stopHour, {bool? archived}) =>
    EpgProgram(
      channelId: 'kanal1.example',
      title: title,
      start: DateTime.utc(2026, 10, 25, startHour),
      stop: DateTime.utc(2026, 10, 25, stopHour),
      archived: archived,
    );

void main() {
  group('mergeArchive', () {
    test('adds archive programmes before the guide', () {
      final guide = [_p('G1', 10, 11), _p('G2', 11, 12)];
      final archive = [_p('A1', 8, 9), _p('A2', 9, 10), _p('A3', 10, 11)];
      expect(mergeArchive(guide, archive).map((p) => p.title), [
        'A1',
        'A2',
        'G1',
        'G2',
      ]);
    });

    test('the guide wins where both have something', () {
      // A3 overlaps G1 by a little: dropped, never cut.
      final guide = [_p('G1', 10, 12)];
      final archive = [_p('A2', 9, 10), _p('A3', 9, 11)];
      final merged = mergeArchive(guide, archive);
      expect(merged.map((p) => p.title), ['A2', 'G1']);
      expect(merged.last.stop, DateTime.utc(2026, 10, 25, 12));
    });

    test('fills gaps in the guide', () {
      final guide = [_p('G1', 8, 9), _p('G3', 11, 12)];
      final archive = [_p('A2', 9, 11), _p('A3', 11, 12)];
      expect(mergeArchive(guide, archive).map((p) => p.title), [
        'G1',
        'A2',
        'G3',
      ]);
    });

    test('unsorted, duplicate and empty archive entries', () {
      final archive = [
        _p('A2', 9, 10),
        _p('A1', 8, 9),
        _p('A1 again', 8, 9),
        _p('Empty', 7, 7),
      ];
      expect(mergeArchive(const [], archive).map((p) => p.title), ['A1', 'A2']);
    });

    test('keeps the archive flag', () {
      final merged = mergeArchive(const [], [_p('A', 8, 9, archived: false)]);
      expect(merged.single.archived, isFalse);
    });
  });

  group('GuideLookup', () {
    final channel = const LiveStream(
      id: '101',
      name: 'Kanal 1',
      epgChannelId: 'kanal1.example',
      archiveDays: 3,
    );
    final guide = EpgGuide(
      programs: {
        'kanal1.example': [_p('G1', 10, 11), _p('G2', 11, 12)],
      },
      fetchedAt: DateTime.utc(2026, 10, 25, 12),
    );

    test('without archive listings it is the guide', () {
      final lookup = GuideLookup(guide);
      expect(lookup.programsFor(channel).map((p) => p.title), ['G1', 'G2']);
      expect(lookup.guideStart(channel), DateTime.utc(2026, 10, 25, 10));
    });

    test('between and now/next see the archive too', () {
      final lookup = GuideLookup(guide, {
        '101': [_p('A1', 8, 9), _p('A2', 9, 10)],
      });
      expect(
        lookup
            .between(
              channel,
              DateTime.utc(2026, 10, 25, 8, 30),
              DateTime.utc(2026, 10, 25, 10, 30),
            )
            .map((p) => p.title),
        ['A1', 'A2', 'G1'],
      );
      final nowNext = lookup.nowAndNext(
        channel,
        DateTime.utc(2026, 10, 25, 9, 30),
      );
      expect(nowNext.now?.title, 'A2');
      expect(nowNext.next?.title, 'G1');
      // The guide's own start is unchanged.
      expect(lookup.guideStart(channel), DateTime.utc(2026, 10, 25, 10));
    });

    test('a channel without guide data uses its archive listing', () {
      const other = LiveStream(id: '102', name: 'Kanal 2', archiveDays: 3);
      final lookup = GuideLookup(guide, {
        '102': [_p('B1', 8, 9)],
      });
      expect(lookup.programsFor(other).single.title, 'B1');
      expect(lookup.guideStart(other), isNull);
    });
  });
}
