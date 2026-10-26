/// Removes a stream URL, and the parts of it that may identify the provider
/// or account, from free text such as mpv log lines.
class UrlRedactor {
  UrlRedactor([Uri? url]) : _secrets = url == null ? const [] : _secretsOf(url);

  /// Longest first, so a secret containing another is fully replaced.
  final List<String> _secrets;

  static List<String> _secretsOf(Uri url) => {
    url.toString(),
    url.host,
    url.userInfo,
    for (final s in url.pathSegments)
      if (s.length >= 3 &&
          !const {'live', 'movie', 'series', 'timeshift'}.contains(s))
        s,
    for (final v in url.queryParameters.values)
      if (v.length >= 3) v,
  }.where((s) => s.isNotEmpty).toList()..sort((a, b) => b.length - a.length);

  static final _urlPattern = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://\S+');

  /// [text] with any URL replaced by `<url>` and every secret by `***`.
  String redact(String text) {
    var result = text.replaceAll(_urlPattern, '<url>');
    for (final s in _secrets) {
      result = result.replaceAll(s, '***');
    }
    return result;
  }
}
