/// Turns mpv's error messages into text for the player's error banner.
///
/// mpv's own wording never reaches the UI: known messages get plain words,
/// harmless ones none (they stay in the log), anything else a general
/// "The stream couldn't be played."
library;

/// mpv errors that don't stop playback, e.g. a seek on a live stream that
/// can't seek: media_kit's Android video output seeks to the current
/// position each time its surface changes (such as the turn to landscape).
const _harmless = ['cannot seek in this stream', 'force-seekable'];

/// ffmpeg's "HTTP error 403 Forbidden" and "Server returned 404 Not Found".
final _httpStatus = RegExp(r'(?:http error|server returned) ([45]\d\d)\b');

/// The banner text for mpv's error [message], or null when it is
/// harmless and only belongs in the log.
String? friendlyPlayerError(String message) {
  final text = message.toLowerCase();
  if (_harmless.any(text.contains)) return null;
  final status = _httpStatus.firstMatch(text)?.group(1);
  if (status != null) {
    return switch (status) {
      '401' || '403' => 'The provider refused the stream (HTTP $status).',
      '404' => "The provider doesn't have this stream (HTTP 404).",
      '429' => 'The provider is busy: too many streams (HTTP 429).',
      _ when status.startsWith('5') =>
        "The provider's server had a problem (HTTP $status).",
      _ => 'The provider refused the stream (HTTP $status).',
    };
  }
  if (text.startsWith('tcp:') ||
      text.contains('connection') ||
      text.contains('timed out') ||
      text.contains('network')) {
    return "Couldn't connect to the stream.";
  }
  if (text.contains('codec') || text.contains('decod')) {
    return "This video or audio format can't be played.";
  }
  if (text.contains('loading failed')) {
    return "The stream couldn't be loaded.";
  }
  if (text.contains('unrecognized file format') ||
      text.contains('no audio or video data')) {
    return "The stream couldn't be read.";
  }
  if (text.contains('no such file') || text.contains('not found')) {
    return "The file wasn't found.";
  }
  return "The stream couldn't be played.";
}
