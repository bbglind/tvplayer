import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/epg_repository.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

const _xml = '''
<tv>
  <channel id="kanal1.example"><display-name>Kanal 1</display-name></channel>
  <channel id="other.example"><display-name>Other</display-name></channel>
  <programme start="20261025023000 +0200" stop="20261025023000 +0100" channel="kanal1.example">
    <title>Across The Switch</title>
  </programme>
  <programme start="20261024120000 +0200" stop="20261024130000 +0200" channel="kanal1.example">
    <title>Long Gone</title>
  </programme>
  <programme start="20261025023000 +0200" stop="20261025023000 +0100" channel="other.example">
    <title>Not In Playlist</title>
  </programme>
</tv>
''';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('epg_repo_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('downloads, parses in an isolate, caches and clears', () async {
    final repo = FileEpgRepository(() async => dir);
    expect(await repo.loadCache(), isNull);

    const channel = LiveStream(id: '1', name: 'SE: Kanal 1 HD');
    final now = DateTime.utc(2026, 10, 25, 0, 45);
    final guide = await repo.refresh(
      FakeLiveSource(
        LiveCatalog(categories: const [], channels: const [channel]),
      )..guideXml = _xml,
      const [channel],
      now: now,
      keepFrom: now.subtract(const Duration(hours: 6)),
    );
    expect(guide.channelIds, ['kanal1.example']);
    expect(guide.programsFor(channel).single.title, 'Across The Switch');
    expect(guide.fetchedAt, now);
    // The downloaded XML is removed; only the cache remains.
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), [
      'epg_cache.json',
    ]);

    final cached = await repo.loadCache();
    expect(cached?.fetchedAt, now);
    final p = cached!.programsFor(channel).single;
    expect(p.start, DateTime.utc(2026, 10, 25, 0, 30));
    expect(p.stop, DateTime.utc(2026, 10, 25, 1, 30));

    await repo.clear();
    expect(await repo.loadCache(), isNull);
  });

  test('an unreadable cache is ignored', () async {
    File('${dir.path}/epg_cache.json').writeAsStringSync('{broken');
    expect(await FileEpgRepository(() async => dir).loadCache(), isNull);
  });

  test('settings round-trip through the settings file', () async {
    final storage = FileSettingsStorage(() async => dir);
    expect((await storage.load()).guideTimeZone, isNull);
    expect((await storage.load()).showPlaybackStats, isFalse);
    await storage.save(
      const AppSettings(
        guideTimeZone: 'Europe/Stockholm',
        guideShiftHours: -1,
        showPlaybackStats: true,
      ),
    );
    final loaded = await storage.load();
    expect(loaded.guideTimeZone, 'Europe/Stockholm');
    expect(loaded.guideShiftHours, -1);
    expect(loaded.showPlaybackStats, isTrue);

    File('${dir.path}/settings.json')
        .writeAsStringSync('{"guideShiftHours": 99}');
    expect((await storage.load()).guideShiftHours, 0);
  });
}
