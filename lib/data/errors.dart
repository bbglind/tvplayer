import 'package:tvplayer_core/tvplayer_core.dart';

/// A user-facing description of a provider error. Never includes hosts,
/// credentials or URLs: core exceptions are already redacted, and anything
/// else is reduced to its type.
String describeProviderError(Object error) => switch (error) {
  XtreamAuthException() =>
    'Login failed: the username or password was rejected.',
  XtreamException(:final message, :final statusCode) ||
  M3uException(
    :final message,
    :final statusCode,
  ) => statusCode == null ? message : '$message (HTTP $statusCode)',
  _ => 'Unexpected error (${error.runtimeType}).',
};

/// Why a playlist refresh failed, in plain words for the user: no
/// technical detail beyond an HTTP status, and never a host, credential or
/// URL.
String describeRefreshError(Object error) => switch (error) {
  EmptyResultException() => 'The provider sent an empty list. Try again later.',
  XtreamException(:final kind, :final statusCode) ||
  M3uException(:final kind, :final statusCode) => switch (kind) {
    ProviderFailure.timeout => "The provider didn't respond in time.",
    ProviderFailure.network =>
      "Couldn't reach the provider. Check the internet connection.",
    ProviderFailure.server =>
      "The provider's server had a problem (HTTP $statusCode).",
    ProviderFailure.refused =>
      'The provider refused the request (HTTP $statusCode).',
    ProviderFailure.auth =>
      'Login failed: the username or password was rejected.',
    ProviderFailure.invalidData =>
      "The provider sent data that couldn't be read.",
    ProviderFailure.other =>
      statusCode == null
          ? 'Something went wrong.'
          : 'Something went wrong (HTTP $statusCode).',
  },
  FormatException() => "The provider sent data that couldn't be read.",
  _ => 'Something went wrong (${error.runtimeType}).',
};
