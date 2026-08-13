import 'package:cloud_firestore/cloud_firestore.dart';

/// A single failed AI call, batched and written to Firestore `api_error_logs`
/// so the admin panel can show live failure stats.
class ApiErrorLog {
  final String? id;
  final String keyId;
  final String keyName;
  final String userId;
  final String feature;
  final String errorType;
  final int statusCode;
  final String message;
  final bool retried;
  final bool retrySuccess;
  final DateTime timestamp;

  /// Firestore TTL field: docs older than this are auto-deleted once the
  /// console TTL policy is enabled on `api_error_logs` (default +30 days).
  final DateTime ttlExpireAt;

  ApiErrorLog({
    this.id,
    required this.keyId,
    required this.keyName,
    required this.userId,
    required this.feature,
    required this.errorType,
    required this.statusCode,
    required this.message,
    this.retried = false,
    this.retrySuccess = false,
    required this.timestamp,
    DateTime? ttlExpireAt,
  }) : ttlExpireAt = ttlExpireAt ?? timestamp.add(const Duration(days: 30));

  factory ApiErrorLog.fromMap(Map<String, dynamic> map, [String? docId]) {
    return ApiErrorLog(
      id: docId,
      keyId: map['keyId'] as String? ?? '',
      keyName: map['keyName'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      feature: map['feature'] as String? ?? '',
      errorType: map['errorType'] as String? ?? '',
      statusCode: map['statusCode'] as int? ?? 0,
      message: map['message'] as String? ?? '',
      retried: map['retried'] as bool? ?? false,
      retrySuccess: map['retrySuccess'] as bool? ?? false,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ttlExpireAt: (map['ttlExpireAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 30)),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'keyId': keyId,
      'keyName': keyName,
      'userId': userId,
      'feature': feature,
      'errorType': errorType,
      'statusCode': statusCode,
      'message': message,
      'retried': retried,
      'retrySuccess': retrySuccess,
      'timestamp': Timestamp.fromDate(timestamp),
      'ttlExpireAt': Timestamp.fromDate(ttlExpireAt),
    };
  }

  @override
  String toString() => 'ApiErrorLog(id: $id, type: $errorType, key: $keyName)';
}
