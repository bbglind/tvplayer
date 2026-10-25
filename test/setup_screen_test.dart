import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tvplayer/app.dart';
import 'package:tvplayer/data/provider_storage.dart';
import 'package:tvplayer/state/providers.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

import 'helpers.dart';

const _host = 'example.com:8080';
const _user = 'testuser';
const _pass = 's3cret-pass';

/// Fake Xtream panel: login checks the credentials; live actions return
/// one category and one channel.
MockClient _panel({int? loginStatus}) => MockClient((request) async {
  final q = request.url.queryParameters;
  if (loginStatus != null) return http.Response('', loginStatus);
  return switch (q['action']) {
    null when q['username'] == _user && q['password'] == _pass => jsonResponse(
      activeAccountJson,
    ),
    null => jsonResponse({
      'user_info': {'auth': 0},
    }),
    'get_live_categories' => jsonResponse([
      {'category_id': '1', 'category_name': 'Test News'},
    ]),
    'get_live_streams' => jsonResponse([
      {'stream_id': 101, 'name': 'Test Channel 1', 'category_id': '1'},
    ]),
    _ => http.Response('', 404),
  };
});

Future<void> _pumpGate(
  WidgetTester tester, {
  required FakeProviderStorage storage,
  http.Client? client,
}) async {
  // Wide enough for the sidebar to show its labels.
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      providerStorage: storage,
      overrides: [httpClientProvider.overrideWithValue(client ?? _panel())],
      child: const RootGate(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillXtream(WidgetTester tester, {String pass = _pass}) async {
  await tester.enterText(find.byKey(const Key('setup.host')), _host);
  await tester.enterText(find.byKey(const Key('setup.username')), _user);
  await tester.enterText(find.byKey(const Key('setup.password')), pass);
  await tester.pump();
}

/// All text currently rendered, for leak checks.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  testWidgets('first launch without a provider shows setup', (tester) async {
    await _pumpGate(tester, storage: FakeProviderStorage());
    expect(find.text('Add a provider'), findsOneWidget);
    expect(find.byKey(const Key('setup.host')), findsOneWidget);
  });

  testWidgets('with a saved provider, opens straight to Live TV', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      storage: FakeProviderStorage(
        const ProviderConfig.xtream(
          host: _host,
          username: _user,
          password: _pass,
        ),
      ),
    );
    expect(find.text('Add a provider'), findsNothing);
    expect(find.text('Live TV'), findsOneWidget);
    expect(find.text('Test Channel 1'), findsOneWidget);
  });

  testWidgets('password is obscured until revealed', (tester) async {
    await _pumpGate(tester, storage: FakeProviderStorage());
    TextField password() =>
        tester.widget<TextField>(find.byKey(const Key('setup.password')));
    expect(password().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(password().obscureText, isFalse);
  });

  testWidgets('buttons are disabled until the form is complete', (
    tester,
  ) async {
    await _pumpGate(tester, storage: FakeProviderStorage());
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await _fillXtream(tester);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('successful test shows account status, no credentials', (
    tester,
  ) async {
    await _pumpGate(tester, storage: FakeProviderStorage());
    await _fillXtream(tester);
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connected'), findsOneWidget);
    expect(find.textContaining('Active'), findsOneWidget);
    final status = tester.widget<Text>(find.textContaining('Connected')).data!;
    for (final secret in [_pass, _user, 'example.com']) {
      expect(status, isNot(contains(secret)));
    }
  });

  testWidgets('rejected login shows a clear error', (tester) async {
    await _pumpGate(tester, storage: FakeProviderStorage());
    await _fillXtream(tester, pass: 'wrong-pass');
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Login failed'), findsOneWidget);
    expect(_allText(tester), isNot(contains('wrong-pass')));
  });

  testWidgets('HTTP errors are reported without the host', (tester) async {
    await _pumpGate(
      tester,
      storage: FakeProviderStorage(),
      client: _panel(loginStatus: 500),
    );
    await _fillXtream(tester);
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(
      tester.widget<Text>(find.textContaining('HTTP 500')).data,
      isNot(contains('example.com')),
    );
  });

  testWidgets('editing the form clears a previous result', (tester) async {
    await _pumpGate(tester, storage: FakeProviderStorage());
    await _fillXtream(tester);
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connected'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('setup.username')), 'other');
    await tester.pump();
    expect(find.textContaining('Connected'), findsNothing);
  });

  testWidgets('saving stores the config and opens Live TV', (tester) async {
    final storage = FakeProviderStorage();
    await _pumpGate(tester, storage: storage);
    await _fillXtream(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(storage.saves, 1);
    expect(storage.saved?.type, ProviderType.xtream);
    expect(storage.saved?.username, _user);
    expect(storage.saved?.password, _pass);
    expect(find.text('Test Channel 1'), findsOneWidget);
  });

  testWidgets('M3U mode tests the playlist', (tester) async {
    final client = MockClient(
      (_) async => http.Response(
        '#EXTM3U\n'
        '#EXTINF:-1 group-title="Test News",Test Channel 1\n'
        'http://example.com/live/1.ts\n'
        '#EXTINF:-1 group-title="Test Sports",Test Channel 2\n'
        'http://example.com/live/2.ts\n',
        200,
      ),
    );
    await _pumpGate(tester, storage: FakeProviderStorage(), client: client);
    await tester.tap(find.text('M3U URL'));
    await tester.pump();
    expect(find.byKey(const Key('setup.host')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('setup.playlistUrl')),
      'http://example.com/playlist.m3u?username=user&password=pass',
    );
    await tester.pump();
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(
      find.text('Playlist loaded: 2 entries in 2 groups.'),
      findsOneWidget,
    );
  });

  testWidgets('invalid M3U URL is rejected before any request', (tester) async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('', 200);
    });
    await _pumpGate(tester, storage: FakeProviderStorage(), client: client);
    await tester.tap(find.text('M3U URL'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('setup.playlistUrl')),
      'not a url',
    );
    await tester.pump();
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('valid http(s) playlist URL'), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('save failure shows the keyring error and stays on setup', (
    tester,
  ) async {
    final storage = FakeProviderStorage();
    await _pumpGate(tester, storage: storage);
    storage.failure = const ProviderStorageException(
      'Could not access the system keyring.',
    );
    await _fillXtream(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not access the system keyring.'), findsOneWidget);
    expect(find.text('Add a provider'), findsOneWidget);
  });

  testWidgets('unavailable keyring at startup shows error with retry', (
    tester,
  ) async {
    final storage = FakeProviderStorage()
      ..failure = const ProviderStorageException('Keyring is locked.');
    await _pumpGate(tester, storage: storage);

    expect(find.text('Keyring unavailable'), findsOneWidget);
    expect(find.text('Keyring is locked.'), findsOneWidget);

    storage.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Add a provider'), findsOneWidget);
  });

  testWidgets('removing the provider from settings returns to setup', (
    tester,
  ) async {
    final storage = FakeProviderStorage(
      const ProviderConfig.m3u(playlistUrl: 'http://example.com/list.m3u'),
    );
    await _pumpGate(
      tester,
      storage: storage,
      client: MockClient((_) async => http.Response('', 404)),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('M3U playlist'), findsOneWidget);

    await tester.tap(find.text('Remove provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(storage.saved, isNull);
    expect(find.text('Add a provider'), findsOneWidget);
  });

  testWidgets('edit provider prefills the form', (tester) async {
    final storage = FakeProviderStorage(
      const ProviderConfig.xtream(
        host: _host,
        username: _user,
        password: _pass,
      ),
    );
    await _pumpGate(tester, storage: storage);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit provider'));
    await tester.pumpAndSettle();

    expect(find.text('Edit provider'), findsWidgets);
    expect(find.widgetWithText(TextField, _user), findsOneWidget);
    await tester.enterText(find.byKey(const Key('setup.username')), 'newuser');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(storage.saved?.username, 'newuser');
    expect(find.text('Remove provider'), findsOneWidget); // Back on settings.
  });

  test('provider config round-trips through the storage encoding', () {
    const xtream = ProviderConfig.xtream(
      host: _host,
      username: _user,
      password: _pass,
    );
    final decoded = decodeProviderConfig(encodeProviderConfig(xtream))!;
    expect(decoded.type, ProviderType.xtream);
    expect(decoded.host, _host);
    expect(decoded.username, _user);
    expect(decoded.password, _pass);

    const m3u = ProviderConfig.m3u(playlistUrl: 'http://example.com/a.m3u');
    expect(
      decodeProviderConfig(encodeProviderConfig(m3u))?.playlistUrl,
      'http://example.com/a.m3u',
    );
    expect(decodeProviderConfig('not json'), isNull);
    expect(decodeProviderConfig('{"type":"other"}'), isNull);
  });
}
