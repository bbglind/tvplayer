import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/device_time_zone.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/epg/guide_screen.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'fake_player.dart';
import 'helpers.dart';

// 02:45 CEST on 2026-10-25, during the hour before Sweden's clocks go back
// from 03:00 CEST to 02:00 CET (01:00 UTC).
final _now = DateTime.utc(2026, 10, 25, 0, 45);

DateTime _utc(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);

EpgProgram _p(String channel, String title, DateTime start, DateTime stop) =>
    EpgProgram(
      channelId: channel,
      title: title,
      start: start,
      stop: stop,
      description: '$title description',
    );

EpgGuide _guide({DateTime? fetchedAt, String suffix = ''}) => EpgGuide(
  programs: {
    'kanal1.example': [
      _p(
        'kanal1.example',
        'Before The Switch$suffix',
        _utc(24, 23, 30),
        _utc(25, 0, 30),
      ),
      _p(
        'kanal1.example',
        'Across The Switch$suffix',
        _utc(25, 0, 30),
        _utc(25, 1, 30),
      ),
      _p(
        'kanal1.example',
        'After The Switch$suffix',
        _utc(25, 1, 30),
        _utc(25, 2, 30),
      ),
    ],
    'kanal2.example': [
      _p('kanal2.example', 'Night Film$suffix', _utc(24, 22), _utc(25, 5)),
    ],
  },
  displayNames: {
    'kanal1.example': ['Kanal 1'],
    'kanal2.example': ['Kanal 2'],
  },
  fetchedAt: fetchedAt ?? _now.subtract(const Duration(hours: 1)),
);

LiveCatalog _catalog({int fillers = 0, bool separator = false}) => LiveCatalog(
  categories: const [Category(id: 'c', name: 'Sweden')],
  channels: [
    if (separator)
      const LiveStream(
        id: 's',
        name: '####### SWEDEN HD #######',
        categoryIds: ['c'],
        number: 99,
        epgChannelId: 'kanal1.example',
      ),
    // No EPG id: matched by name ("SE:" and "HD" ignored).
    const LiveStream(id: '1', name: 'SE: Kanal 1 HD', categoryIds: ['c']),
    const LiveStream(
      id: '2',
      name: 'Kanal 2',
      categoryIds: ['c'],
      epgChannelId: 'kanal2.example',
    ),
    const LiveStream(
      id: '3',
      name: 'No Guide',
      categoryIds: ['c'],
      epgChannelId: 'none.example',
    ),
    for (var i = 0; i < fillers; i++)
      LiveStream(id: 'f$i', name: 'Filler $i', categoryIds: const ['c']),
  ],
);

int _seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Finder _program(String channelId, DateTime start) =>
    find.byKey(Key('guide.program.$channelId.${_seconds(start)}'));

void main() {
  late FakeEpgRepository epg;
  late FakeSettingsStorage settings;
  late FakeLiveSource source;
  late FakeExternalPlayer player;

  setUp(() {
    epg = FakeEpgRepository(cached: _guide());
    settings = FakeSettingsStorage();
    source = FakeLiveSource(_catalog(), hasGuide: true);
    player = FakeExternalPlayer();
  });

  tearDown(() => player.dispose());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(source),
          providerStorageProvider.overrideWithValue(FakeProviderStorage()),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(false),
        ],
        settings: settings,
        epg: epg,
        now: _now,
        child: Scaffold(body: screen),
      ),
    );
  }

  group('Live TV list', () {
    testWidgets('shows what is on now, matched by EPG id and by name', (
      tester,
    ) async {
      await pump(tester, const LiveTvScreen());
      await tester.pumpAndSettle();

      // Across the switch: 02:30 CEST to 02:30 CET.
      expect(find.text('Across The Switch · until 02:30'), findsOneWidget);
      expect(find.text('Night Film · until 06:00'), findsOneWidget);
      expect(find.byKey(const Key('nowNext.3')), findsNothing);
      expect(epg.refreshes, 0, reason: 'the cached guide is fresh');
    });

    testWidgets('uses the chosen time zone and shift', (tester) async {
      settings.saved = const AppSettings(guideTimeZone: 'UTC');
      await pump(tester, const LiveTvScreen());
      await tester.pumpAndSettle();
      expect(find.text('Across The Switch · until 01:30'), findsOneWidget);
    });

    testWidgets('a shift moves which programme is on now', (tester) async {
      // +1 h: what the guide lists at 23:30 UTC really starts at 00:30.
      settings.saved = const AppSettings(
        guideTimeZone: 'UTC',
        guideShiftHours: 1,
      );
      await pump(tester, const LiveTvScreen());
      await tester.pumpAndSettle();
      expect(find.text('Before The Switch · until 01:30'), findsOneWidget);
    });
  });

  group('loading and refreshing', () {
    testWidgets('a stale cache is shown, then refreshed in the background', (
      tester,
    ) async {
      epg
        ..cached = _guide(
          fetchedAt: _now.subtract(const Duration(hours: 13)),
          suffix: ' (old)',
        )
        ..next = _guide(fetchedAt: _now, suffix: ' (new)')
        ..gate = Completer();
      await pump(tester, const GuideScreen());
      await tester.pump();
      await tester.pump();
      expect(find.text('Across The Switch (old)'), findsOneWidget);
      expect(epg.refreshes, 1);
      expect(epg.lastChannels, hasLength(3));

      epg.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Across The Switch (new)'), findsOneWidget);
      expect(find.text('Across The Switch (old)'), findsNothing);
    });

    testWidgets('without a cache the guide is downloaded', (tester) async {
      epg
        ..cached = null
        ..next = _guide(fetchedAt: _now)
        ..gate = Completer();
      await pump(tester, const GuideScreen());
      await tester.pump();
      expect(find.text('Loading the TV guide…'), findsOneWidget);

      epg.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Across The Switch'), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the old guide and warns', (
      tester,
    ) async {
      epg
        ..cached = _guide(fetchedAt: _now.subtract(const Duration(days: 1)))
        ..failure = const XtreamException('Request timed out (xmltv)');
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      expect(find.text('Across The Switch'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('a failed first download offers retry', (tester) async {
      epg
        ..cached = null
        ..failure = const XtreamException('Request timed out (xmltv)');
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      expect(find.text('Request timed out (xmltv)'), findsOneWidget);

      epg
        ..failure = null
        ..next = _guide(fetchedAt: _now);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Across The Switch'), findsOneWidget);
    });

    testWidgets('refresh button downloads again', (tester) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      expect(epg.refreshes, 0);
      epg.next = _guide(fetchedAt: _now, suffix: ' (new)');
      await tester.tap(find.byTooltip('Refresh TV guide'));
      await tester.pumpAndSettle();
      expect(epg.refreshes, 1);
      expect(find.text('Across The Switch (new)'), findsOneWidget);
    });

    testWidgets('providers without a guide say so', (tester) async {
      source.hasGuide = false;
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      expect(find.text('No TV guide'), findsOneWidget);
      expect(epg.refreshes, 0);
    });
  });

  group('guide grid', () {
    testWidgets('header shows the repeated hour of the DST change', (
      tester,
    ) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('guide.header'));
      Finder label(String text) =>
          find.descendant(of: header, matching: find.text(text));
      // 02:00 and 02:30 happen twice (CEST, then CET); 03:00 CEST never.
      expect(label('02:00'), findsNWidgets(2));
      expect(label('02:30'), findsNWidgets(2));
      expect(label('03:00'), findsOneWidget);
      expect(find.text('Sun 25 Oct'), findsOneWidget); // Corner date.
      expect(find.text('No guide information'), findsOneWidget);
    });

    testWidgets('the time line is at the current time', (tester) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      final line = tester.getRect(find.byKey(const Key('guide.nowLine')));
      final across = tester.getRect(_program('1', _utc(25, 0, 30)));
      // 15 minutes into the programme that started at 00:30 UTC.
      expect(
        line.center.dx - across.left,
        closeTo(15 * GuideGrid.pixelsPerMinute, 0.5),
      );
    });

    testWidgets('channel names stay put when scrolling sideways', (
      tester,
    ) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      final channel = find.text('Kanal 2');
      final header = find.descendant(
        of: find.byKey(const Key('guide.header')),
        matching: find.text('03:00'),
      );
      final cell = _program('1', _utc(25, 1, 30));
      final channelBefore = tester.getTopLeft(channel);
      final headerBefore = tester.getTopLeft(header);
      final cellBefore = tester.getTopLeft(cell);

      await tester.drag(_program('2', _utc(24, 22)), const Offset(-200, 0));
      await tester.pumpAndSettle();

      final dx = tester.getTopLeft(cell).dx - cellBefore.dx;
      expect(dx, lessThan(-100));
      expect(tester.getTopLeft(channel), channelBefore);
      expect(tester.getTopLeft(header).dx - headerBefore.dx, closeTo(dx, 0.5));
    });

    testWidgets('the time row stays put when scrolling up and down', (
      tester,
    ) async {
      source = FakeLiveSource(_catalog(fillers: 40), hasGuide: true);
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      final header = find.descendant(
        of: find.byKey(const Key('guide.header')),
        matching: find.text('03:00'),
      );
      final channel = find.text('Filler 5');
      final cell = _program('2', _utc(24, 22));
      final headerBefore = tester.getTopLeft(header);
      final channelBefore = tester.getTopLeft(channel);
      final cellBefore = tester.getTopLeft(cell);

      await tester.drag(_program('2', _utc(24, 22)), const Offset(0, -100));
      await tester.pumpAndSettle();

      final dy = tester.getTopLeft(channel).dy - channelBefore.dy;
      expect(dy, lessThan(-50));
      expect(tester.getTopLeft(header), headerBefore);
      expect(tester.getTopLeft(cell).dy - cellBefore.dy, closeTo(dy, 0.5));
    });

    testWidgets('scrolling the channel column scrolls the rows', (
      tester,
    ) async {
      source = FakeLiveSource(_catalog(fillers: 40), hasGuide: true);
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      final channel = find.text('Kanal 2');
      final cell = _program('2', _utc(24, 22));
      final channelBefore = tester.getTopLeft(channel);
      final cellBefore = tester.getTopLeft(cell);
      await tester.drag(find.text('Filler 3'), const Offset(0, -100));
      await tester.pumpAndSettle();

      final dy = tester.getTopLeft(channel).dy - channelBefore.dy;
      expect(dy, lessThan(-50));
      expect(tester.getTopLeft(cell).dy - cellBefore.dy, closeTo(dy, 0.5));
    });

    testWidgets('tapping a programme on now plays its channel', (tester) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      await tester.tap(_program('1', _utc(25, 0, 30)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(player.opened.single.title, 'SE: Kanal 1 HD');
      expect(player.opened.single.url.path, '/live/user/pass/1.ts');
      // The player shows now/next too.
      expect(find.byKey(const Key('player.nowNext')), findsOneWidget);
      expect(find.text('Across The Switch'), findsWidgets);
    });

    testWidgets('tapping a later programme shows its details', (tester) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      await tester.tap(_program('1', _utc(25, 1, 30)));
      await tester.pumpAndSettle();
      expect(player.opened, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('After The Switch description'), findsOneWidget);
      expect(
        find.text('SE: Kanal 1 HD · Sun 25 Oct 02:30–03:30'),
        findsOneWidget,
      );
    });

    testWidgets('a programme that started off-screen keeps its title in '
        'view', (tester) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      // Night Film runs from the grid's start, left of the initial view.
      final body = tester.getRect(find.byKey(const Key('guide.body')));
      final block = _program('2', _utc(24, 22));
      final title = find.descendant(
        of: block,
        matching: find.text('Night Film'),
      );
      final label = find.descendant(
        of: block,
        matching: find.text('00:00–06:00'),
      );
      expect(tester.getRect(block).left, lessThan(body.left - 100));
      expect(tester.getTopLeft(title).dx, closeTo(body.left + 8, 1));
      expect(tester.getTopLeft(label).dx, closeTo(body.left + 8, 1));

      // Still pinned after scrolling further.
      await tester.drag(block, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dx, closeTo(body.left + 8, 1));

      // Back at the start of the block the text sits at its own left edge.
      await tester.drag(block, const Offset(2000, 0));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(title).dx,
        closeTo(tester.getRect(block).left + 8, 1),
      );
    });

    testWidgets('separator entries are headings without a guide row', (
      tester,
    ) async {
      source = FakeLiveSource(_catalog(separator: true), hasGuide: true);
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('separator.s'));
      expect(
        find.descendant(of: header, matching: find.text('SWEDEN HD')),
        findsOneWidget,
      );
      expect(find.textContaining('#'), findsNothing);
      expect(find.text('99'), findsNothing);
      // Its EPG id matches Kanal 1's guide, but it gets no programmes.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('guide.program.s.'),
        ),
        findsNothing,
      );
      expect(find.text('No guide information'), findsOneWidget);
      // The header lines up with the first row.
      expect(
        tester.getRect(header).top,
        tester.getRect(find.byKey(const Key('guide.rows'))).top,
      );

      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(player.opened, isEmpty);
    });

    testWidgets('category filter limits the rows', (tester) async {
      source = FakeLiveSource(
        LiveCatalog(
          categories: const [
            Category(id: 'a', name: 'A'),
            Category(id: 'b', name: 'B'),
          ],
          channels: const [
            LiveStream(id: '1', name: 'Kanal 1', categoryIds: ['a']),
            LiveStream(id: '2', name: 'Kanal 2', categoryIds: ['b']),
          ],
        ),
        hasGuide: true,
      );
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      expect(find.text('Kanal 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide.category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A').last);
      await tester.pumpAndSettle();
      expect(find.text('Kanal 1'), findsOneWidget);
      expect(find.text('Kanal 2'), findsNothing);
    });
  });

  group('separators in the Live TV list', () {
    testWidgets('show as a heading that is not counted or playable', (
      tester,
    ) async {
      source = FakeLiveSource(_catalog(separator: true), hasGuide: true);
      await pump(tester, const LiveTvScreen());
      await tester.pumpAndSettle();

      final header = find.byKey(const Key('separator.s'));
      expect(
        find.descendant(of: header, matching: find.text('SWEDEN HD')),
        findsOneWidget,
      );
      expect(find.textContaining('#'), findsNothing);
      expect(find.text('99'), findsNothing);
      expect(find.byKey(const Key('nowNext.s')), findsNothing);
      // 'All channels' and 'Sweden' count the three real channels.
      expect(find.text('3'), findsNWidgets(2));

      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(player.opened, isEmpty);

      // Searching shows only channels.
      await tester.enterText(find.byKey(const Key('live.search')), 'sweden');
      await tester.pumpAndSettle();
      expect(header, findsNothing);
      expect(find.text('No channels'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('playback statistics are off by default and can be turned '
        'on', (tester) async {
      await pump(tester, const SettingsScreen());
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('settings.playbackStats'));
      await tester.scrollUntilVisible(toggle, 100);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(settings.saved.showPlaybackStats, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    });

    testWidgets('shows the device zone by default and saves a picked zone', (
      tester,
    ) async {
      await pump(tester, const SettingsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Device time zone (Europe/Stockholm)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings.timeZone')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('timeZone.search')),
        'new york',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('America/New York'));
      await tester.pumpAndSettle();
      expect(settings.saved.guideTimeZone, 'America/New_York');
      expect(find.text('America/New_York'), findsOneWidget);

      // Back to the device zone.
      await tester.tap(find.byKey(const Key('settings.timeZone')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device time zone'));
      await tester.pumpAndSettle();
      expect(settings.saved.guideTimeZone, isNull);
    });

    testWidgets('saves the time shift', (tester) async {
      await pump(tester, const SettingsScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.shift')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+2 h').last);
      await tester.pumpAndSettle();
      expect(settings.saved.guideShiftHours, 2);
    });
  });

  test('changing or removing the provider clears the guide cache', () async {
    final repo = FakeEpgRepository();
    final container = ProviderContainer(
      overrides: [
        providerStorageProvider.overrideWithValue(FakeProviderStorage()),
        epgRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(savedProviderProvider.notifier);
    await container.read(savedProviderProvider.future);
    const config = ProviderConfig.xtream(
      host: 'http://example.com',
      username: 'user',
      password: 'pass',
    );

    await notifier.save(config);
    expect(repo.clears, 1);
    await notifier.save(config);
    expect(repo.clears, 1, reason: 'same provider: keep the cache');
    await notifier.save(
      const ProviderConfig.xtream(
        host: 'http://example.com',
        username: 'other',
        password: 'pass',
      ),
    );
    expect(repo.clears, 2);
    await notifier.remove();
    expect(repo.clears, 3);
  });

  group('device time zone', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('tz_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    String detect({Map<String, String> env = const {}}) => deviceTimeZone(
      environment: env,
      localtimePath: '${dir.path}/localtime',
      timezonePath: '${dir.path}/timezone',
    );

    test('from TZ', () {
      expect(detect(env: {'TZ': 'Europe/Stockholm'}), 'Europe/Stockholm');
      expect(detect(env: {'TZ': ':Europe/Stockholm'}), 'Europe/Stockholm');
      expect(
        detect(env: {'TZ': '/usr/share/zoneinfo/Asia/Tokyo'}),
        'Asia/Tokyo',
      );
    });

    test('from the /etc/localtime symlink', () {
      Link('${dir.path}/localtime')
          .createSync('/usr/share/zoneinfo/Europe/Stockholm');
      expect(detect(env: {'TZ': 'Not/AZone'}), 'Europe/Stockholm');
    });

    test('from /etc/timezone, else UTC', () {
      expect(detect(), 'UTC');
      File('${dir.path}/timezone').writeAsStringSync('Europe/Oslo\n');
      expect(detect(), 'Europe/Oslo');
    });
  });
}
