/// Structured Audit Log model with built-in sensitive field redaction
/// (Week 13 SA7 Structured Logging & Week 14 SA8/IA5 Safe Logging).
library;

class AuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String correlationId;
  final String actorId;
  final String actorRole;
  final String action;
  final String? announcementId;
  final String? previousStatus;
  final String? newStatus;
  final String outcome; // SUCCESS, FAILURE_TRANSIENT, FAILURE_PERMANENT, DENIED, INVALID
  final Map<String, dynamic> details;

  AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.correlationId,
    required this.actorId,
    required this.actorRole,
    required this.action,
    this.announcementId,
    this.previousStatus,
    this.newStatus,
    required this.outcome,
    Map<String, dynamic> details = const {},
  }) : details = redactSensitiveMap(details);

  static const Set<String> _sensitiveKeys = {
    'password',
    'passwd',
    'secret',
    'token',
    'authorization',
    'bearer',
    'api_key',
    'apikey',
    'private_key',
  };

  /// Recursively redacts any sensitive keys or bearer token strings before
  /// persisting or displaying logs (Week 14 Safe Logging control).
  static Map<String, dynamic> redactSensitiveMap(Map<String, dynamic> input) {
    final sanitized = <String, dynamic>{};
    for (final entry in input.entries) {
      final lowerKey = entry.key.toLowerCase();
      if (_sensitiveKeys.any((k) => lowerKey.contains(k))) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] = redactSensitiveMap(
          entry.value as Map<String, dynamic>,
        );
      } else if (entry.value is String) {
        final strVal = entry.value as String;
        if (strVal.toLowerCase().startsWith('bearer ') ||
            RegExp(r'^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$')
                .hasMatch(strVal)) {
          sanitized[entry.key] = '[REDACTED_TOKEN]';
        } else {
          sanitized[entry.key] = strVal;
        }
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'correlationId': correlationId,
      'actorId': actorId,
      'actorRole': actorRole,
      'action': action,
      'announcementId': announcementId,
      'previousStatus': previousStatus,
      'newStatus': newStatus,
      'outcome': outcome,
      'details': details,
    };
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      correlationId: (json['correlationId'] as String?) ?? 'corr-unknown',
      actorId: (json['actorId'] as String?) ?? 'system',
      actorRole: (json['actorRole'] as String?) ?? 'system',
      action: json['action'] as String,
      announcementId: json['announcementId'] as String?,
      previousStatus: json['previousStatus'] as String?,
      newStatus: json['newStatus'] as String?,
      outcome: (json['outcome'] as String?) ?? 'SUCCESS',
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

