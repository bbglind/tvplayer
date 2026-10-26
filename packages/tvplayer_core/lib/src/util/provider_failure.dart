/// What went wrong talking to a provider, so the UI can say it in plain
/// words without showing the technical message.
enum ProviderFailure {
  /// No answer in time, or the download stalled.
  timeout,

  /// The provider couldn't be reached (DNS, connection refused, TLS…).
  network,

  /// The provider's server failed (HTTP 5xx).
  server,

  /// The provider refused the request (HTTP 4xx other than a login error).
  refused,

  /// The username or password was rejected.
  auth,

  /// The response couldn't be read (not JSON, not a playlist).
  invalidData,

  other;

  /// The failure an HTTP [statusCode] stands for; [other] when there is
  /// none.
  static ProviderFailure forStatus(int? statusCode) => switch (statusCode) {
    null => other,
    >= 500 => server,
    >= 400 => refused,
    _ => other,
  };
}
