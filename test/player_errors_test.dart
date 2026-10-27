import 'package:flutter_test/flutter_test.dart';
import 'package:tvplayer/player/player_errors.dart';

void main() {
  test('a seek on a live stream that can\'t seek is not shown', () {
    expect(friendlyPlayerError('Cannot seek in this stream.'), isNull);
    expect(
      friendlyPlayerError("You can force it with '--force-seekable=yes'."),
      isNull,
    );
  });

  test('HTTP errors say what the provider did', () {
    expect(
      friendlyPlayerError('HTTP error 403 Forbidden'),
      'The provider refused the stream (HTTP 403).',
    );
    expect(
      friendlyPlayerError('Server returned 404 Not Found'),
      "The provider doesn't have this stream (HTTP 404).",
    );
    expect(
      friendlyPlayerError('HTTP error 502 Bad Gateway'),
      "The provider's server had a problem (HTTP 502).",
    );
  });

  test('connection and format errors get plain words', () {
    expect(
      friendlyPlayerError('tcp: ffurl_read returned 0xffffff99'),
      "Couldn't connect to the stream.",
    );
    expect(
      friendlyPlayerError('Could not open codec.'),
      "This video or audio format can't be played.",
    );
    expect(
      friendlyPlayerError('loading failed'),
      "The stream couldn't be loaded.",
    );
  });

  test('anything else never shows mpv\'s text', () {
    expect(
      friendlyPlayerError('[cplayer] something odd at 192.0.2.1'),
      "The stream couldn't be played.",
    );
  });
}
