import '../util/json.dart';

/// Account and server details returned by an Xtream login.
///
/// The panel echoes the username and password back; they are intentionally
/// not kept here.
final class AccountInfo {
  const AccountInfo({
    required this.status,
    this.expiresAt,
    this.isTrial = false,
    this.activeConnections,
    this.maxConnections,
    this.createdAt,
    this.allowedOutputFormats = const [],
    this.serverTimezone,
  });

  static AccountInfo fromJson(Map<String, Object?> json) {
    final user = readMap(json['user_info']) ?? const {};
    final server = readMap(json['server_info']) ?? const {};
    return AccountInfo(
      status: readString(user['status']) ?? 'Unknown',
      expiresAt: readEpochSeconds(user['exp_date']),
      isTrial: readBool(user['is_trial']),
      activeConnections: readInt(user['active_cons']),
      maxConnections: readInt(user['max_connections']),
      createdAt: readEpochSeconds(user['created_at']),
      allowedOutputFormats: readStringList(user['allowed_output_formats']),
      serverTimezone: readString(server['timezone']),
    );
  }

  /// Account status as reported by the panel, e.g. `Active` or `Expired`.
  final String status;

  /// Expiry date, or null for accounts without expiry.
  final DateTime? expiresAt;
  final bool isTrial;
  final int? activeConnections;
  final int? maxConnections;
  final DateTime? createdAt;

  /// Container formats the account may use for live streams, e.g. `ts`, `m3u8`.
  final List<String> allowedOutputFormats;
  final String? serverTimezone;

  bool get isActive => status.toLowerCase() == 'active';

  @override
  String toString() => 'AccountInfo($status, expires: $expiresAt)';
}
