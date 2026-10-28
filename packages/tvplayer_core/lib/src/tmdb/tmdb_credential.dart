/// How a [TmdbCredential] is sent.
enum TmdbCredentialKind {
  /// The "API Read Access Token", sent as `Authorization: Bearer …`.
  bearer,

  /// The v3 "API Key", sent as the `api_key` query parameter.
  apiKey,
}

/// The user's own TMDB credential. Either kind from TMDB's API settings is
/// accepted; [parse] tells them apart. [toString] never shows the value.
final class TmdbCredential {
  const TmdbCredential._(this.kind, this.value);

  static final _apiKey = RegExp(r'^[0-9a-fA-F]{32}$');
  static final _whitespace = RegExp(r'\s');

  /// The credential in [text] as pasted: a 32-character hex v3 API key, or
  /// a read access token (with or without a leading `Bearer `). Null when
  /// [text] is empty or can't be either.
  static TmdbCredential? parse(String text) {
    var s = text.trim();
    if (s.toLowerCase().startsWith('bearer ')) s = s.substring(7).trim();
    if (s.isEmpty || _whitespace.hasMatch(s)) return null;
    if (_apiKey.hasMatch(s)) {
      return TmdbCredential._(TmdbCredentialKind.apiKey, s);
    }
    // Read access tokens are JWTs, far longer than an API key.
    if (s.length < 40) return null;
    return TmdbCredential._(TmdbCredentialKind.bearer, s);
  }

  final TmdbCredentialKind kind;

  /// The secret itself, for storage and requests only.
  final String value;

  /// Headers to send with each request.
  Map<String, String> get headers => switch (kind) {
    TmdbCredentialKind.bearer => {'Authorization': 'Bearer $value'},
    TmdbCredentialKind.apiKey => const {},
  };

  /// Query parameters to add to each request.
  Map<String, String> get query => switch (kind) {
    TmdbCredentialKind.bearer => const {},
    TmdbCredentialKind.apiKey => {'api_key': value},
  };

  @override
  bool operator ==(Object other) =>
      other is TmdbCredential && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'TmdbCredential(${kind.name})';
}
