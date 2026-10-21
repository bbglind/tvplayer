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
