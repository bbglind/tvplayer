import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/data/app_settings.dart';
import 'package:tvplayer/data/device_time_zone.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/epg/guide_screen.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer/ui/settings/settings_screen.dart';
import 'package:tvplayer/ui/theme/app_colors.dart';
import 'package:tvplayer/ui/theme/widgets.dart';
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

  Future<void> pump(WidgetTester tester, Widget screen, {DateTime? now}) async {
    await tester.pumpWidget(
      testApp(
        overrides: [
          liveSourceProvider.overrideWithValue(source),
          useExternalMpvProvider.overrideWithValue(true),
          externalMpvProvider.overrideWithValue(player),
          embedMpvProvider.overrideWithValue(false),
        ],
        settings: settings,
        epg: epg,
        now: now ?? _now,
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

    testWidgets('rows grow with the text size, so the progress bar stays '
        'inside the row', (tester) async {
      // Fixed-height rows pushed the bar under the row's clipped bottom
      // edge at large desktop text sizes, leaving a 1 px sliver.
      await pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: const LiveTvScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.ancestor(
        of: find.text('Night Film · until 06:00'),
        matching: find.byType(AppTile),
      );
      final bar = find.descendant(
        of: row,
        matching: find.byType(ProgressStrip),
      );
      expect(bar, findsOneWidget);
      expect(
        tester.getRect(bar).bottom,
        lessThanOrEqualTo(tester.getRect(row).bottom - 10),
      );
    });
  });

  testWidgets('channel numbers up to 5 digits stay on one line at text '
      'scale 1.0 to 1.4', (tester) async {
    source = FakeLiveSource(
      LiveCatalog(
        categories: const [Category(id: 'c', name: 'Sweden')],
        channels: const [
          LiveStream(id: '1', name: 'One', categoryIds: ['c'], number: 7),
          LiveStream(id: '2', name: 'Two', categoryIds: ['c'], number: 3786),
          LiveStream(id: '3', name: 'Three', categoryIds: ['c'], number: 37861),
        ],
      ),
      hasGuide: true,
    );
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final scale in [1.0, 1.4]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final screen in const [LiveTvScreen(), GuideScreen()]) {
        await pump(tester, screen);
        await tester.pumpAndSettle();
        final line = tester.getSize(find.text('7')).height;
        for (final number in ['3786', '37861']) {
          expect(
            tester.getSize(find.text(number)).height,
            line,
            reason: '$number in ${screen.runtimeType} at $scale',
          );
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  group('loading and refreshing', () {
    testWidgets('a stale cache is shown, then refreshed by automatic '
        'refresh', (tester) async {
      epg
        ..cached = _guide(
          fetchedAt: _now.subtract(const Duration(hours: 25)),
          suffix: ' (old)',
        )
        ..next = _guide(fetchedAt: _now, suffix: ' (new)')
        ..gate = Completer();
      await pump(tester, const AutoRefreshHost(child: GuideScreen()));
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
        ..cached = _guide(fetchedAt: _now.subtract(const Duration(days: 2)))
        ..failure = const XtreamException(
          'Request timed out (xmltv)',
          kind: ProviderFailure.timeout,
        );
      await pump(tester, const AutoRefreshHost(child: GuideScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Across The Switch'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('a failed first download offers retry', (tester) async {
      epg
        ..cached = null
        ..failure = const XtreamException(
          'Request timed out (xmltv)',
          kind: ProviderFailure.timeout,
        );
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      expect(find.text("The provider didn't respond in time."), findsOneWidget);
      expect(find.textContaining('xmltv'), findsNothing);

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
      expect(
        tester.widget<Text>(find.byKey(const Key('guide.date'))).data,
        'Sun 25 Oct',
      );
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

    ScrollPosition timeScroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('guide.body')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    ScrollPosition rowScroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('guide.rows')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    Future<void> wheel(
      WidgetTester tester,
      Offset at,
      Offset delta, {
      bool shift = false,
    }) async {
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(at));
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(mouse.scroll(delta));
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Shift + wheel moves through time, also when the platform '
        'already sent it sideways', (tester) async {
      source = FakeLiveSource(_catalog(fillers: 40), hasGuide: true);
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      final body = tester.getCenter(_program('2', _utc(24, 22)));
      final channels = tester.getCenter(find.text('Kanal 2'));

      for (final at in [body, channels]) {
        for (final delta in [const Offset(0, 80), const Offset(80, 0)]) {
          final x = timeScroll(tester).pixels;
          await wheel(tester, at, delta, shift: true);
          expect(timeScroll(tester).pixels, x + 80, reason: '$at $delta');
          expect(rowScroll(tester).pixels, 0, reason: '$at $delta');
        }
      }

      // Without Shift the wheel still scrolls the channels.
      final x = timeScroll(tester).pixels;
      await wheel(tester, body, const Offset(0, 80));
      expect(rowScroll(tester).pixels, 80);
      expect(timeScroll(tester).pixels, x);
    });

    testWidgets('a sideways touchpad scroll moves through time anywhere on '
        'the grid', (tester) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      final header = tester.getCenter(
        find.descendant(
          of: find.byKey(const Key('guide.header')),
          matching: find.text('03:00'),
        ),
      );
      for (final at in [
        tester.getCenter(_program('2', _utc(24, 22))),
        tester.getCenter(find.text('Kanal 2')),
        header,
      ]) {
        // As scroll signals (some touchpads, horizontal wheels) ...
        var x = timeScroll(tester).pixels;
        await wheel(tester, at, const Offset(60, 5));
        expect(timeScroll(tester).pixels, x + 60, reason: 'signal at $at');

        // ... and as pan gestures.
        x = timeScroll(tester).pixels;
        final pad = TestPointer(2, PointerDeviceKind.trackpad);
        await tester.sendEventToBinding(pad.panZoomStart(at));
        for (var i = 1; i <= 10; i++) {
          await tester.sendEventToBinding(
            pad.panZoomUpdate(at, pan: Offset(-10.0 * i, 0)),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.sendEventToBinding(pad.panZoomEnd());
        await tester.pumpAndSettle();
        expect(
          timeScroll(tester).pixels,
          greaterThan(x + 50),
          reason: 'pan at $at',
        );
      }
    });

    testWidgets('the scrollbar under the programmes can be dragged', (
      tester,
    ) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      final body = tester.getRect(find.byKey(const Key('guide.body')));
      final p = timeScroll(tester);
      final thumbLength = math.max(
        18.0,
        body.width * body.width / (p.maxScrollExtent + body.width),
      );
      final thumbLeft =
          body.left + p.pixels / p.maxScrollExtent * (body.width - thumbLength);
      final thumb = Offset(thumbLeft + thumbLength / 2, body.bottom - 5);
      final x = p.pixels;

      final mouse = await tester.startGesture(
        thumb,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(20, 0));
      await mouse.moveBy(const Offset(20, 0));
      await mouse.up();
      await tester.pumpAndSettle();
      // 40 px of thumb is far more than 40 px of grid.
      expect(timeScroll(tester).pixels, greaterThan(x + 200));
      expect(rowScroll(tester).pixels, 0);
    });

    testWidgets('the scrollbar thumb is drawn in the accent colour on a '
        'subtle track at large text sizes', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: const GuideScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollbar = find.byKey(const Key('guide.scrollbar'));
      final screen = tester.getRect(find.byType(GuideScreen));
      expect(
        tester.getRect(scrollbar).bottom,
        lessThanOrEqualTo(screen.bottom),
      );
      ScrollbarPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: scrollbar,
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .foregroundPainter!
              as ScrollbarPainter;
      expect(painter().color, AppColors.accent);
      expect(painter().trackColor, AppColors.surface);

      // Hovering the thumb lightens it.
      final body = tester.getRect(find.byKey(const Key('guide.body')));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final p = timeScroll(tester);
      final thumbLength = math.max(
        18.0,
        body.width * body.width / (p.maxScrollExtent + body.width),
      );
      final thumbLeft =
          body.left + p.pixels / p.maxScrollExtent * (body.width - thumbLength);
      await mouse.addPointer(location: body.bottomLeft - const Offset(0, 40));
      await mouse.moveTo(Offset(thumbLeft + thumbLength / 2, body.bottom - 5));
      await tester.pumpAndSettle();
      expect(painter().color, AppColors.accentHover);
      await mouse.removePointer();
    });

    testWidgets('the last row is not under the scrollbar', (tester) async {
      source = FakeLiveSource(_catalog(fillers: 40), hasGuide: true);
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      final rows = find.byKey(const Key('guide.rows'));
      await tester.drag(find.text('Filler 3'), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Filler 39')).bottom,
        lessThan(tester.getRect(rows).bottom - GuideGrid.scrollbarSpace + 1),
      );
    });

    testWidgets('dragging the channel column edge resizes it, remembered', (
      tester,
    ) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      final channels = find.byKey(const Key('guide.channels'));
      final resize = find.byKey(const Key('guide.channels.resize'));
      final header = find.descendant(
        of: find.byKey(const Key('guide.header')),
        matching: find.text('03:00'),
      );
      expect(
        tester.getSize(channels).width,
        AppSettings.defaultGuideChannelWidth,
      );
      final headerX = tester.getTopLeft(header).dx;
      final cellX = tester.getTopLeft(_program('1', _utc(25, 1, 30))).dx;

      await tester.drag(resize, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(channels).width, 260);
      expect(settings.saved.guideChannelWidth, 260);
      // The time row and the programmes move along together.
      expect(tester.getTopLeft(header).dx, headerX + 60);
      expect(tester.getTopLeft(_program('1', _utc(25, 1, 30))).dx, cellX + 60);

      await tester.drag(resize, const Offset(-1000, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(channels).width, AppSettings.minGuideChannelWidth);
    });

    testWidgets('a cut-off channel name shows in full in a tooltip', (
      tester,
    ) async {
      const long = 'SE: A Channel With A Really Long Name ◉';
      source = FakeLiveSource(
        LiveCatalog(
          categories: const [Category(id: 'c', name: 'Sweden')],
          channels: const [
            LiveStream(id: '1', name: long, categoryIds: ['c']),
            LiveStream(id: '2', name: 'Kanal 2', categoryIds: ['c']),
          ],
        ),
        hasGuide: true,
      );
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('SE: A Channel With A Really Long Name ◉'),
        findsOneWidget,
      );
      expect(find.byTooltip('Kanal 2'), findsNothing);
    });

    testWidgets('rows grow with the text size, so nothing is clipped', (
      tester,
    ) async {
      source = FakeLiveSource(
        LiveCatalog(
          categories: const [Category(id: 'c', name: 'Sweden')],
          channels: const [
            LiveStream(id: '1', name: 'SE: Kanal 1 HD ◉', categoryIds: ['c']),
            LiveStream(
              id: '2',
              name: 'Kanal 2',
              categoryIds: ['c'],
              epgChannelId: 'kanal2.example',
            ),
          ],
        ),
        hasGuide: true,
      );
      await pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: const GuideScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_program('1', _utc(25, 0, 30)), findsOneWidget);

      var checked = 0;
      for (final key in ['guide.rows', 'guide.channels', 'guide.header']) {
        for (final element
            in find
                .descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(RichText),
                )
                .evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(
            paragraph.size.height,
            greaterThanOrEqualTo(paragraph.textSize.height - 0.01),
            reason: '"${paragraph.text.toPlainText()}" in $key is clipped',
          );
          checked++;
        }
      }
      expect(checked, greaterThan(10));
      // The two-line channel name fits too.
      final name = find.text('SE: Kanal 1 HD ◉');
      expect(
        tester.getSize(name).height,
        greaterThan(tester.getSize(find.text('Kanal 2')).height),
      );
    });

    testWidgets('arrow keys move between programmes and scroll the grid', (
      tester,
    ) async {
      await pump(tester, const GuideScreen());
      await tester.pumpAndSettle();
      bool focused(Finder cell) {
        final node = FocusManager.instance.primaryFocus;
        return node?.context != null &&
            find
                .descendant(
                  of: cell,
                  matching: find.byElementPredicate((e) => e == node!.context),
                )
                .evaluate()
                .isNotEmpty;
      }

      final across = _program('1', _utc(25, 0, 30));
      final title = find.descendant(
        of: across,
        matching: find.text('Across The Switch'),
      );
      Focus.of(tester.element(title)).requestFocus();
      await tester.pumpAndSettle();
      expect(focused(across), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focused(_program('1', _utc(25, 1, 30))), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focused(_program('2', _utc(24, 22))), isTrue);

      // Left of the view: the grid follows the focus.
      final x = timeScroll(tester).pixels;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
      }
      expect(focused(_program('1', _utc(24, 23, 30))), isTrue);
      expect(timeScroll(tester).pixels, lessThan(x));
    });

    test('a trailing mark stays with the word before it', () {
      expect(keepLastWordAttached('SE: Kanal 1 HD ◉'), 'SE: Kanal 1 HD ◉');
      expect(keepLastWordAttached('Kanal 2 ◉ '), 'Kanal 2 ◉');
      // Words are left alone.
      expect(keepLastWordAttached('Kanal 2'), 'Kanal 2');
      expect(keepLastWordAttached('SE: Kanal 1 HD'), 'SE: Kanal 1 HD');
      expect(keepLastWordAttached('◉'), '◉');
    });
  });

  group('quick jumps', () {
    // Stockholm local time in late October 2026, after the switch to CET
    // (+01:00).
    DateTime local(int day, int hour, [int minute = 0]) =>
        DateTime.utc(2026, 10, day, hour - 1, minute);

    // Half-hour programmes from 06:00 on the 27th until [until] (local), for
    // [extra] guide channels without a playlist channel ending at [extraUntil].
    EpgGuide guide({
      required DateTime until,
      int extra = 0,
      DateTime? extraUntil,
    }) {
      List<EpgProgram> programs(String id, DateTime end) => [
        for (
          var t = local(27, 6);
          t.isBefore(end);
          t = t.add(const Duration(minutes: 30))
        )
          _p(
            id,
            'Show ${t.toIso8601String()}',
            t,
            t.add(const Duration(minutes: 30)),
          ),
      ];
      return EpgGuide(
        programs: {
          'kanal1.example': programs('kanal1.example', until),
          'kanal2.example': programs('kanal2.example', until),
          for (var i = 0; i < extra; i++)
            'extra$i.example': programs('extra$i.example', extraUntil!),
        },
        displayNames: {
          'kanal1.example': ['Kanal 1'],
          'kanal2.example': ['Kanal 2'],
        },
        fetchedAt: local(27, 6),
      );
    }

    final body = find.byKey(const Key('guide.body'));
    final now = find.byKey(const Key('guide.now'));
    final tonight = find.byKey(const Key('guide.tonight'));

    ScrollPosition timeScroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(of: body, matching: find.byType(Scrollable)).first,
        )
        .position;

    /// How far [moment]'s programme on Kanal 2 starts from the grid's left
    /// edge.
    double fromLeft(WidgetTester tester, DateTime moment) =>
        tester.getRect(_program('2', moment)).left - tester.getRect(body).left;

    bool enabled(WidgetTester tester, Finder chip) =>
        tester
            .widget<FilterChip>(
              find.descendant(of: chip, matching: find.byType(FilterChip)),
            )
            .onSelected !=
        null;

    Future<void> open(WidgetTester tester, DateTime at, EpgGuide g) async {
      epg = FakeEpgRepository(cached: g);
      await pump(tester, const GuideScreen(), now: at);
      await tester.pumpAndSettle();
    }

    const lead = 30 * GuideGrid.pixelsPerMinute;

    testWidgets('Now and Tonight are in the toolbar with hover texts', (
      tester,
    ) async {
      await open(tester, local(27, 14), guide(until: local(29, 0)));
      expect(find.byTooltip('Go to the current time'), findsOneWidget);
      expect(find.byTooltip('Go to this evening, 20:00'), findsOneWidget);
      // The corner no longer has a Now button of its own.
      expect(find.text('Now'), findsOneWidget);
      expect(find.descendant(of: now, matching: find.text('Now')), findsOne);
      expect(enabled(tester, tonight), isTrue);
    });

    testWidgets('Now goes back to the current time', (tester) async {
      await open(tester, local(27, 14), guide(until: local(29, 0)));
      final opened = timeScroll(tester).pixels;
      await tester.drag(body, const Offset(-1500, 0));
      await tester.pumpAndSettle();
      expect(timeScroll(tester).pixels, isNot(opened));

      await tester.tap(now);
      await tester.pumpAndSettle();
      expect(timeScroll(tester).pixels, opened);
      final line = tester.getRect(find.byKey(const Key('guide.nowLine')));
      expect(line.center.dx - tester.getRect(body).left, closeTo(lead, 0.5));
    });

    testWidgets('Tonight goes to 20:00 with 19:30 in view', (tester) async {
      await open(tester, local(27, 14), guide(until: local(29, 0)));
      await tester.tap(tonight);
      await tester.pumpAndSettle();
      expect(fromLeft(tester, local(27, 20)), closeTo(lead, 0.5));
      final label = find.descendant(
        of: find.byKey(const Key('guide.header')),
        matching: find.text('19:30'),
      );
      expect(
        tester.getRect(label).left,
        greaterThanOrEqualTo(tester.getRect(body).left),
      );
    });

    testWidgets('after 23:00 Tonight goes to tomorrow evening', (tester) async {
      // The guide only just reaches it; the grid still has room to put it
      // at the left edge.
      await open(tester, local(27, 23, 15), guide(until: local(28, 21)));
      expect(find.byTooltip('Go to tomorrow evening, 20:00'), findsOneWidget);
      await tester.tap(tonight);
      await tester.pumpAndSettle();
      expect(fromLeft(tester, local(28, 20)), closeTo(lead, 0.5));
    });

    testWidgets('after 23:00 Tonight is off while the guide ends sooner', (
      tester,
    ) async {
      await open(tester, local(27, 23, 15), guide(until: local(28, 15)));
      expect(
        find.byTooltip('No TV guide for tomorrow evening yet'),
        findsOneWidget,
      );
      expect(enabled(tester, tonight), isFalse);
      final x = timeScroll(tester).pixels;
      await tester.tap(tonight);
      await tester.pumpAndSettle();
      expect(timeScroll(tester).pixels, x);
    });

    testWidgets('one channel reaching the evening is not enough', (
      tester,
    ) async {
      await open(
        tester,
        local(27, 23, 15),
        // Kanal 1 and 2 reach it, three others don't.
        guide(until: local(29, 6), extra: 3, extraUntil: local(28, 15)),
      );
      expect(enabled(tester, tonight), isFalse);
    });

    testWidgets('a guide ending before this evening turns Tonight off', (
      tester,
    ) async {
      await open(tester, local(27, 14), guide(until: local(27, 18)));
      expect(find.byTooltip('No TV guide for this evening yet'), findsOne);
      expect(enabled(tester, tonight), isFalse);
    });

    testWidgets('Tonight follows the clock past 23:00', (tester) async {
      await open(tester, local(27, 22, 50), guide(until: local(28, 15)));
      expect(find.byTooltip('Go to this evening, 20:00'), findsOneWidget);
      expect(enabled(tester, tonight), isTrue);

      final container = ProviderScope.containerOf(tester.element(body));
      (container.read(clockProvider.notifier) as FixedClock).set(
        local(27, 23, 5),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('No TV guide for tomorrow evening yet'),
        findsOneWidget,
      );
      expect(enabled(tester, tonight), isFalse);
    });

    testWidgets('opened late in the evening, 19:30 is still in reach', (
      tester,
    ) async {
      await open(tester, local(27, 22, 30), guide(until: local(29, 0)));
      await tester.tap(tonight);
      await tester.pumpAndSettle();
      expect(fromLeft(tester, local(27, 20)), closeTo(lead, 0.5));
    });

    testWidgets('uses the guide time zone setting', (tester) async {
      settings.saved = const AppSettings(guideTimeZone: 'America/New_York');
      await open(tester, local(27, 14), guide(until: local(29, 0)));
      await tester.tap(tonight);
      await tester.pumpAndSettle();
      // 20:00 EDT (-04:00) on the 27th.
      expect(fromLeft(tester, DateTime.utc(2026, 10, 28)), closeTo(lead, 0.5));
    });

    testWidgets('both work from another day', (tester) async {
      await open(tester, local(27, 14), guide(until: local(29, 0)));
      final opened = timeScroll(tester).pixels;
      // A day later.
      timeScroll(tester).jumpTo(opened + 24 * 60 * GuideGrid.pixelsPerMinute);
      await tester.pumpAndSettle();
      expect(find.text('Wed 28 Oct'), findsWidgets);

      await tester.tap(tonight);
      await tester.pumpAndSettle();
      expect(fromLeft(tester, local(27, 20)), closeTo(lead, 0.5));

      timeScroll(tester).jumpTo(opened + 24 * 60 * GuideGrid.pixelsPerMinute);
      await tester.pumpAndSettle();
      await tester.tap(now);
      await tester.pumpAndSettle();
      expect(timeScroll(tester).pixels, opened);
    });

    testWidgets('the toolbar fits at text size 1.4 in a narrow window', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      epg = FakeEpgRepository(cached: guide(until: local(29, 0)));
      await pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: const GuideScreen(),
          ),
        ),
        now: local(27, 14),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final (chip, label) in [(now, 'Now'), (tonight, 'Tonight')]) {
        final text = tester.renderObject<RenderParagraph>(
          find.descendant(of: chip, matching: find.text(label)),
        );
        expect(text.didExceedMaxLines, isFalse, reason: label);
        expect(
          text.size.width,
          greaterThanOrEqualTo(text.getMaxIntrinsicWidth(double.infinity)),
          reason: label,
        );
      }
      // The update time gives way instead.
      final updated = tester.renderObject<RenderParagraph>(
        find.textContaining('Updated'),
      );
      expect(updated.didExceedMaxLines, isTrue);
      expect(
        tester.getRect(tonight).right,
        lessThan(tester.getRect(find.textContaining('Updated')).left),
      );
    });

    testWidgets('Now and Tonight show their icons', (tester) async {
      await open(tester, local(27, 14), guide(until: local(29, 0)));
      for (final (chip, icon) in [
        (now, Icons.schedule_outlined),
        (tonight, Icons.bedtime_outlined),
      ]) {
        final found = find.descendant(of: chip, matching: find.byIcon(icon));
        expect(found, findsOneWidget, reason: '$icon');
        expect(tester.getSize(found).width, greaterThan(0));
        final glyph = tester.widget<RichText>(
          find.descendant(of: found, matching: find.byType(RichText)),
        );
        expect(glyph.text.style?.color?.a, greaterThan(0));
      }
    });

    for (final scale in [1.0, 1.4]) {
      testWidgets('time labels around midnight never overlap at text size '
          '$scale', (tester) async {
        // Wide enough that labels after midnight are built too.
        tester.view.physicalSize = const Size(1800, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        epg = FakeEpgRepository(cached: guide(until: local(29, 0)));
        await pump(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const GuideScreen(),
            ),
          ),
          now: local(27, 14),
        );
        await tester.pumpAndSettle();
        await tester.tap(tonight);
        await tester.pumpAndSettle();
        final header = find.byKey(const Key('guide.header'));
        final rects =
            tester
                .widgetList<Text>(
                  find.descendant(of: header, matching: find.byType(Text)),
                )
                .map((t) => tester.getRect(find.byWidget(t)))
                .toList()
              ..sort((a, b) => a.left.compareTo(b.left));
        expect(rects.length, greaterThan(4));
        for (var i = 1; i < rects.length; i++) {
          expect(
            rects[i].left,
            greaterThanOrEqualTo(rects[i - 1].right),
            reason: 'label $i overlaps the one before it',
          );
        }
        // The day change shows the date.
        expect(
          find.descendant(of: header, matching: find.text('Wed 28 Oct')),
          findsOneWidget,
        );
      });
    }
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
      expect(find.text('No channels found'), findsOneWidget);
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
      final zone = find.byKey(const Key('settings.timeZone'));
      await tester.scrollUntilVisible(zone, 100);
      await tester.pumpAndSettle();
      expect(find.text('Device time zone (Europe/Stockholm)'), findsOneWidget);

      await tester.tap(zone);
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
      final shift = find.byKey(const Key('settings.shift'));
      await tester.scrollUntilVisible(shift, 100);
      await tester.pumpAndSettle();
      await tester.tap(shift);
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
