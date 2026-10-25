import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

Future<void> _pump(WidgetTester tester, FakeLiveSource source) async {
  await tester.pumpWidget(
    testApp(
      overrides: [liveSourceProvider.overrideWithValue(source)],
      child: const Scaffold(body: LiveTvScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows categories and lazily builds thousands of channels', (
    tester,
  ) async {
    await _pump(tester, FakeLiveSource(syntheticCatalog()));

    expect(find.text('All channels'), findsOneWidget);
    expect(find.text('5000'), findsOneWidget); // All-channels count.
    expect(find.text('Category 3'), findsOneWidget);
    expect(find.text('Channel 0000'), findsOneWidget);
    // Lazy list: off-screen rows aren't built.
    expect(find.text('Channel 4999'), findsNothing);
    expect(tester.widgetList(find.byType(ChannelRow)).length, lessThan(100));
  });

  testWidgets('selecting a category filters channels', (tester) async {
    await _pump(tester, FakeLiveSource(syntheticCatalog()));

    await tester.tap(find.text('Category 3'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 0003'), findsOneWidget);
    expect(find.text('Channel 0000'), findsNothing);
    expect(find.text('Channel 0013'), findsOneWidget);
  });

  testWidgets('search filters by name, case-insensitively', (tester) async {
    await _pump(tester, FakeLiveSource(syntheticCatalog()));

    await tester.enterText(find.byKey(const Key('live.search')), 'channel 42');
    await tester.pumpAndSettle();
    // Names containing "channel" and "42" match, in provider order.
    expect(find.text('Channel 0042'), findsOneWidget);
    expect(find.text('Channel 0142'), findsOneWidget);
    expect(find.text('Channel 0000'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('live.search')),
      'CHANNEL 1234',
    );
    await tester.pumpAndSettle();
    expect(find.text('Channel 1234'), findsOneWidget);
    // The category list ignores the search.
    expect(find.text('All channels'), findsOneWidget);
    expect(find.text('Category 3'), findsOneWidget);
    expect(find.byType(ChannelRow), findsOneWidget);

    await tester.enterText(find.byKey(const Key('live.search')), 'nothing');
    await tester.pumpAndSettle();
    expect(find.text('No channels found'), findsOneWidget);
    expect(find.text('0 channels'), findsOneWidget);
  });

  testWidgets('search ignores spaces, case and accents', (tester) async {
    await _pump(
      tester,
      FakeLiveSource(
        LiveCatalog(
          categories: const [Category(id: 'a', name: 'A')],
          channels: const [
            LiveStream(id: '1', name: 'SVT 1 HD', categoryIds: ['a']),
            LiveStream(id: '2', name: 'Kanal Ö', categoryIds: ['a']),
            LiveStream(id: '3', name: 'Other', categoryIds: ['a']),
          ],
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('live.search')), 'svt1');
    await tester.pumpAndSettle();
    expect(find.text('SVT 1 HD'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
    expect(find.text('1 channel'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('live.search')), 'kanal o');
    await tester.pumpAndSettle();
    expect(find.text('Kanal Ö'), findsOneWidget);
  });

  testWidgets('search covers all channels; "Only in" limits it to the '
      'selected category', (tester) async {
    await _pump(tester, FakeLiveSource(syntheticCatalog()));
    final onlyIn = find.byKey(const Key('live.onlyIn'));

    // Under All channels there is nothing to limit.
    await tester.enterText(
      find.byKey(const Key('live.search')),
      'channel 1234',
    );
    await tester.pumpAndSettle();
    expect(onlyIn, findsNothing);

    // Channel 1234 is in Category 4, but the search still finds it.
    await tester.tap(find.text('Category 2'));
    await tester.pumpAndSettle();
    expect(find.text('Channel 1234'), findsOneWidget);
    expect(find.text('Only in Category 2'), findsOneWidget);

    await tester.tap(onlyIn);
    await tester.pumpAndSettle();
    expect(find.text('Channel 1234'), findsNothing);
    expect(find.text('No channels found'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('live.search')),
      'channel 1232',
    );
    await tester.pumpAndSettle();
    expect(find.text('Channel 1232'), findsOneWidget);

    // Off again: the whole section.
    await tester.tap(onlyIn);
    await tester.enterText(
      find.byKey(const Key('live.search')),
      'channel 1234',
    );
    await tester.pumpAndSettle();
    expect(find.text('Channel 1234'), findsOneWidget);

    // Without a search the category shows as before, and the chip goes.
    await tester.enterText(find.byKey(const Key('live.search')), '');
    await tester.pumpAndSettle();
    expect(onlyIn, findsNothing);
    expect(find.text('Channel 0002'), findsOneWidget);
    expect(find.text('Channel 0000'), findsNothing);
  });

  testWidgets('shows loading, then the list', (tester) async {
    final source = FakeLiveSource(syntheticCatalog(count: 3))
      ..gate = Completer<void>();
    await tester.pumpWidget(
      testApp(
        overrides: [liveSourceProvider.overrideWithValue(source)],
        child: const Scaffold(body: LiveTvScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    source.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Channel 0002'), findsOneWidget);
  });

  testWidgets('shows the error and retries', (tester) async {
    final source = FakeLiveSource(syntheticCatalog(count: 3), failTimes: 1);
    await _pump(tester, source);

    expect(find.text('Could not load channels'), findsOneWidget);
    expect(find.textContaining('Request timed out'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(source.loads, 2);
    expect(find.text('Channel 0001'), findsOneWidget);
  });

  testWidgets('catalog is cached for the session', (tester) async {
    final source = FakeLiveSource(syntheticCatalog(count: 3));
    await _pump(tester, source);
    // Rebuilding the screen (e.g. after navigating away and back) must not
    // refetch.
    await tester.pumpWidget(
      testApp(
        overrides: [liveSourceProvider.overrideWithValue(source)],
        child: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpWidget(
      testApp(
        overrides: [liveSourceProvider.overrideWithValue(source)],
        child: const Scaffold(body: LiveTvScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.loads, 1);

    await tester.tap(find.byTooltip('Reload channels'));
    await tester.pumpAndSettle();
    expect(source.loads, 2);
  });
}
