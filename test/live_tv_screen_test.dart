import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer/ui/live/live_tv_screen.dart';

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
    expect(tester.widgetList(find.byType(ListTile)).length, lessThan(100));
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
    // Only names containing "channel 42" match, i.e. 4200-4299.
    expect(find.text('Channel 4200'), findsOneWidget);
    expect(find.text('Channel 0000'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('live.search')),
      'CHANNEL 1234',
    );
    await tester.pumpAndSettle();
    expect(find.text('Channel 1234'), findsOneWidget);
    expect(
      find.byType(ListTile),
      findsNWidgets(11 + 1),
    ); // 10 categories + All + 1 channel.

    await tester.enterText(find.byKey(const Key('live.search')), 'nothing');
    await tester.pumpAndSettle();
    expect(find.text('No channels'), findsOneWidget);
  });

  testWidgets('search applies within the selected category', (tester) async {
    await _pump(tester, FakeLiveSource(syntheticCatalog()));

    await tester.tap(find.text('Category 2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('live.search')), 'channel 123');
    await tester.pumpAndSettle();
    expect(find.text('Channel 1232'), findsOneWidget);
    expect(find.text('Channel 1234'), findsNothing);
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
