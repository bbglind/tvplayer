import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/url_redactor.dart';

void main() {
  final url = Uri.parse('http://192.0.2.1:8080/live/someuser/somepass/101.ts');
  final redactor = UrlRedactor(url);

  test('replaces full URLs', () {
    expect(redactor.redact('Failed to open $url.'), 'Failed to open <url>');
    expect(
      redactor.redact('redirect to https://example.com/x?token=abc'),
      'redirect to <url>',
    );
  });

  test('replaces host and credentials appearing on their own', () {
    final out = redactor.redact(
      'tcp: connection to 192.0.2.1 failed for someuser / somepass',
    );
    expect(out, isNot(contains('192.0.2.1')));
    expect(out, isNot(contains('someuser')));
    expect(out, isNot(contains('somepass')));
  });

  test('leaves unrelated text alone', () {
    expect(
      redactor.redact('[ffmpeg/video] h264: no frame!'),
      '[ffmpeg/video] h264: no frame!',
    );
    expect(UrlRedactor().redact('live stream'), 'live stream');
  });

  test('redacts query parameter values', () {
    final r = UrlRedactor(
      Uri.parse(
        'http://example.com/get.php?username=someuser&password=somepass',
      ),
    );
    expect(r.redact('auth someuser:somepass'), 'auth ***:***');
  });
}
