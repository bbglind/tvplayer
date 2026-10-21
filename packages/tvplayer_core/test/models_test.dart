import 'package:test/test.dart';
import 'package:tvplayer_core/tvplayer_core.dart';

void main() {
  test('ProviderConfig.toString hides credentials', () {
    const xtream = ProviderConfig.xtream(
      host: 'http://example.com:8080',
      username: 'testuser',
      password: 'testpass',
    );
    const m3u = ProviderConfig.m3u(
      playlistUrl: 'http://example.com/get.php?username=testuser',
    );
    for (final config in [xtream, m3u]) {
      final text = config.toString();
      expect(text, isNot(contains('example.com')));
      expect(text, isNot(contains('testuser')));
      expect(text, isNot(contains('testpass')));
    }
    expect(xtream.type, ProviderType.xtream);
    expect(m3u.type, ProviderType.m3u);
  });

  test('M3uEntry.toString hides the URL', () {
    const entry = M3uEntry(
      name: 'Test Channel 1',
      url: 'http://example.com/live/testuser/testpass/1.ts',
    );
    expect(entry.toString(), isNot(contains('example.com')));
    expect(entry.toString(), isNot(contains('testpass')));
  });

  test('EpgProgram.isAiringAt', () {
    final program = EpgProgram(
      channelId: 'test1.example',
      title: 'Test',
      start: DateTime.utc(2024, 1, 1, 8),
      stop: DateTime.utc(2024, 1, 1, 9),
    );
    expect(program.isAiringAt(DateTime.utc(2024, 1, 1, 8)), isTrue);
    expect(program.isAiringAt(DateTime.utc(2024, 1, 1, 8, 59)), isTrue);
    expect(program.isAiringAt(DateTime.utc(2024, 1, 1, 9)), isFalse);
    expect(program.duration, const Duration(hours: 1));
  });
}
