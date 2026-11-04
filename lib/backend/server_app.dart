/// Complete REST API application for Project 26: Campus Announcement Scheduler.
/// Implements Weeks 13–18 backend requirements:
/// - Bounded workflow endpoints (Draft -> Review -> Approve -> Schedule -> Publish -> Expire -> Archive)
/// - Week 13: Scheduled publishing, conflict detection (409), transient retry, permanent human escalation, structured audit logs
/// - Week 14: HMAC-SHA256 Auth (401), RBAC (403), input validation (400), safe logging, data minimization, security headers
/// - Week 16: Health (/health), telemetry (/metrics), and snapshot/rollback endpoints
library;

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../shared/models/announcement.dart';
import '../../shared/validation/announcement_validator.dart';
import 'automation/automation_engine.dart';
import 'automation/conflict_detector.dart';
import 'security/auth_service.dart';
import 'storage/announcement_repository.dart';

class ServerApp {
  final AnnouncementRepository repository;
  final AuthService authService;
  final AutomationEngine automationEngine;
  final DateTime startedAt = DateTime.now().toUtc();

  // Week 16 Observability & Performance Metrics
  int totalRequests = 0;
  int error4xxCount = 0;
  int error5xxCount = 0;
  int authFailureCount = 0;
  int rbacDeniedCount = 0;
  int conflictRejectionCount = 0;
  int validationRejectionCount = 0;
  final List<double> requestLatenciesMs = [];

  int _corrSeq = 1;

  ServerApp({
    AnnouncementRepository? repository,
    AuthService? authService,
    AutomationEngine? automationEngine,
  }) : this._internal(
         repository: repository ?? AnnouncementRepository(),
         authService: authService ?? AuthService(),
         automationEngine: automationEngine,
       );

  ServerApp._internal({
    required this.repository,
    required this.authService,
    AutomationEngine? automationEngine,
  }) : automationEngine =
           automationEngine ?? AutomationEngine(repository: repository);

  Handler get handler {
    final router = Router();

    // Public observability & auth routes
    router.get('/api/v1/health', _handleHealth);
    router.get('/api/v1/metrics', _handleMetrics);
    router.get('/api/v1/auth/demo-accounts', _handleDemoAccounts);
    router.post('/api/v1/auth/login', _handleLogin);

    // Protected announcement workflow routes
    router.get('/api/v1/announcements', _handleListAnnouncements);
    router.get('/api/v1/announcements/<id>', _handleGetAnnouncement);
    router.post('/api/v1/announcements', _handleCreateDraft);
    router.put('/api/v1/announcements/<id>', _handleUpdateDraft);
    router.post('/api/v1/announcements/<id>/submit', _handleSubmitForReview);
    router.post('/api/v1/announcements/<id>/review', _handleReviewDecision);
    router.post('/api/v1/announcements/<id>/schedule', _handleSchedule);
    router.post('/api/v1/announcements/<id>/recover', _handleHumanRecovery);
    router.post('/api/v1/announcements/<id>/archive', _handleArchive);

    // Automation, Audit, and Recovery/Rollback routes
    router.post('/api/v1/automation/tick', _handleAutomationTick);
    router.get('/api/v1/audit-logs', _handleGetAuditLogs);
    router.post('/api/v1/admin/snapshot', _handleCreateSnapshot);
    router.post('/api/v1/admin/rollback', _handleRestoreSnapshot);
    router.post('/api/v1/admin/reset-demo', _handleResetDemo);

    return const Pipeline()
        .addMiddleware(corsHeaders())
        .addMiddleware(_securityAndTelemetryMiddleware())
        .addHandler(router.call);
  }

  Middleware _securityAndTelemetryMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final sw = Stopwatch()..start();
        totalRequests++;
        final corrId =
            request.headers['x-correlation-id'] ?? 'corr-${10000 + (_corrSeq++)}';

        try {
          final reqWithCorr = request.change(
            context: {...request.context, 'correlationId': corrId},
          );
          final response = await innerHandler(reqWithCorr);
          sw.stop();
          _recordLatency(sw.elapsedMicroseconds / 1000.0);

          if (response.statusCode >= 400 && response.statusCode < 500) {
            error4xxCount++;
          } else if (response.statusCode >= 500) {
            error5xxCount++;
          }

          return response.change(
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'x-correlation-id': corrId,
              'strict-transport-security':
                  'max-age=31536000; includeSubDomains',
              'x-content-type-options': 'nosniff',
              'x-frame-options': 'DENY',
              'content-security-policy': "default-src 'self'",
              'cache-control': 'no-store',
            },
          );
        } catch (err) {
          sw.stop();
          _recordLatency(sw.elapsedMicroseconds / 1000.0);
          error5xxCount++;
          repository.recordAudit(
            correlationId: corrId,
            actorId: 'system',
            actorRole: 'system',
            action: 'UNHANDLED_SERVER_ERROR',
            outcome: 'ERROR',
            timestamp: automationEngine.now,
            details: {'path': request.url.path, 'error': err.toString()},
          );
          return _jsonResponse(500, {
            'error': 'INTERNAL_SERVER_ERROR',
            'message': 'An unexpected server error occurred.',
            'correlationId': corrId,
          });
        }
      };
    };
  }

  void _recordLatency(double ms) {
    requestLatenciesMs.add(ms);
    if (requestLatenciesMs.length > 2000) {
      requestLatenciesMs.removeAt(0);
    }
  }

  double _percentile(double p) {
    if (requestLatenciesMs.isEmpty) return 0.0;
    final sorted = List<double>.from(requestLatenciesMs)..sort();
    final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return double.parse(sorted[idx].toStringAsFixed(2));
  }

  String _corrId(Request req) =>
      (req.context['correlationId'] as String?) ?? 'corr-default';

  Response _jsonResponse(int statusCode, Map<String, dynamic> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<Map<String, dynamic>> _parseJsonBody(Request request) async {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('JSON body must be an object.');
  }

  /// Authenticates request and optionally enforces allowed roles.
  ({TokenVerificationResult auth, Response? errorResponse}) _guard(
    Request request, {
    List<UserRole>? allowedRoles,
  }) {
    final corrId = _corrId(request);
    final authHeader = request.headers['authorization'];
    final verification = authService.verifyToken(authHeader);

    if (!verification.isValid) {
      authFailureCount++;
      repository.recordAudit(
        correlationId: corrId,
        actorId: 'anonymous',
        actorRole: 'unauthenticated',
        action: 'AUTH_TOKEN_REJECTED',
        outcome: 'DENIED',
        timestamp: automationEngine.now,
        details: {
          'path': request.url.path,
          'errorCode': verification.errorCode,
          'reason': verification.errorMessage,
          'authorizationHeader': authHeader ?? 'missing',
        },
      );
      return (
        auth: verification,
        errorResponse: _jsonResponse(401, {
          'error': verification.errorCode,
          'message': verification.errorMessage,
          'correlationId': corrId,
        }),
      );
    }

    if (allowedRoles != null && !allowedRoles.contains(verification.role)) {
      rbacDeniedCount++;
      repository.recordAudit(
        correlationId: corrId,
        actorId: verification.userId!,
        actorRole: verification.role!.wireName,
        action: 'RBAC_AUTHORIZATION_DENIED',
        outcome: 'DENIED',
        timestamp: automationEngine.now,
        details: {
          'path': request.url.path,
          'actorRole': verification.role!.wireName,
          'requiredRoles': allowedRoles.map((r) => r.wireName).toList(),
        },
      );
      return (
        auth: verification,
        errorResponse: _jsonResponse(403, {
          'error': 'RBAC_FORBIDDEN',
          'message':
              'Role "${verification.role!.label}" is not authorized to perform this action. Required: ${allowedRoles.map((r) => r.label).join(", ")}.',
          'correlationId': corrId,
        }),
      );
    }

    return (auth: verification, errorResponse: null);
  }

  // ==========================================================================
  // Route Handlers
  // ==========================================================================

  Response _handleHealth(Request request) {
    final all = repository.getAllAnnouncements();
    final permanentFailures = all
        .where((a) => a.status == AnnouncementStatus.publishFailedPermanent)
        .length;

    return _jsonResponse(200, {
      'status': permanentFailures > 0 ? 'DEGRADED_ACTION_REQUIRED' : 'HEALTHY',
      'service': 'campus-announcement-scheduler-api',
      'version': '1.0.0',
      'uptimeSeconds': DateTime.now().toUtc().difference(startedAt).inSeconds,
      'virtualTime': automationEngine.now.toIso8601String(),
      'clockOffsetMinutes': automationEngine.clockOffset.inMinutes,
      'checks': {
        'repository': 'UP',
        'automationScheduler': 'UP',
        'escalationQueueDepth': permanentFailures,
      },
    });
  }

  Response _handleMetrics(Request request) {
    final all = repository.getAllAnnouncements();
    final byStatus = <String, int>{};
    for (final s in AnnouncementStatus.values) {
      byStatus[s.wireName] = all.where((a) => a.status == s).length;
    }

    return _jsonResponse(200, {
      'timestamp': automationEngine.now.toIso8601String(),
      'http': {
        'totalRequests': totalRequests,
        'error4xxCount': error4xxCount,
        'error5xxCount': error5xxCount,
        'latencyMs': {
          'p50': _percentile(0.50),
          'p95': _percentile(0.95),
          'p99': _percentile(0.99),
          'sampleCount': requestLatenciesMs.length,
        },
      },
      'security': {
        'authFailureCount': authFailureCount,
        'rbacDeniedCount': rbacDeniedCount,
        'validationRejectionCount': validationRejectionCount,
      },
      'automation': {
        'totalTicksRun': automationEngine.totalTicksRun,
        'publishedTotal': automationEngine.publishedTotal,
        'transientFailuresTotal': automationEngine.transientFailuresTotal,
        'transientRecoveriesTotal': automationEngine.transientRecoveriesTotal,
        'permanentEscalationsTotal': automationEngine.permanentEscalationsTotal,
        'autoExpirationsTotal': automationEngine.autoExpirationsTotal,
        'conflictRejectionCount': conflictRejectionCount,
      },
      'announcementsByStatus': byStatus,
    });
  }

  Response _handleDemoAccounts(Request request) {
    return _jsonResponse(200, {
      'accounts': authService.demoAccounts.map((a) => a.toPublicJson()).toList(),
    });
  }

  Future<Response> _handleLogin(Request request) async {
    final corrId = _corrId(request);
    Map<String, dynamic> body;
    try {
      body = await _parseJsonBody(request);
    } catch (_) {
      return _jsonResponse(400, {
        'error': 'INVALID_JSON',
        'message': 'Request body must be valid JSON.',
      });
    }

    final email = (body['email'] as String?)?.trim() ?? '';
    final password = (body['password'] as String?) ?? '';
    final tokenMode = (body['tokenMode'] as String?) ?? 'valid';

    final user = authService.authenticatePassword(email, password);
    if (user == null) {
      authFailureCount++;
      repository.recordAudit(
        correlationId: corrId,
        actorId: email.isEmpty ? 'unknown' : email,
        actorRole: 'unauthenticated',
        action: 'USER_LOGIN_FAILED',
        outcome: 'DENIED',
        timestamp: automationEngine.now,
        details: {
          'email': email,
          'password': password, // Automatically redacted by AuditLogEntry!
          'reason': 'Invalid email or password',
        },
      );
      return _jsonResponse(401, {
        'error': 'AUTH_INVALID_CREDENTIALS',
        'message': 'Invalid email or password.',
        'correlationId': corrId,
      });
    }

    String token;
    if (tokenMode == 'expired') {
      token = authService.issueExpiredToken(user);
    } else if (tokenMode == 'tampered') {
      token = authService.issueTamperedToken(user);
    } else {
      token = authService.issueToken(user);
    }

    repository.recordAudit(
      correlationId: corrId,
      actorId: user.id,
      actorRole: user.role.wireName,
      action: 'USER_LOGIN_SUCCESS',
      outcome: 'SUCCESS',
      timestamp: automationEngine.now,
      details: {
        'email': user.email,
        'tokenModeIssued': tokenMode,
        'issuedToken': token, // Automatically redacted by AuditLogEntry!
      },
    );

    return _jsonResponse(200, {
      'token': token,
      'tokenMode': tokenMode,
      'user': user.toPublicJson(),
      'virtualTime': automationEngine.now.toIso8601String(),
    });
  }

  Response _handleListAnnouncements(Request request) {
    final guarded = _guard(request);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;

    // Week 14 Data Minimization: Campus users only receive active published
    // announcements with internal metadata stripped.
    if (auth.role == UserRole.campusUser) {
      final active = repository.getPublishedCampusAnnouncements(
        now: automationEngine.now,
      );
      return _jsonResponse(200, {
        'dataMinimized': true,
        'viewerRole': auth.role!.wireName,
        'virtualTime': automationEngine.now.toIso8601String(),
        'announcements': active.map((a) => a.toMinimizedCampusJson()).toList(),
      });
    }

    final all = repository.getAllAnnouncements();
    return _jsonResponse(200, {
      'dataMinimized': false,
      'viewerRole': auth.role!.wireName,
      'virtualTime': automationEngine.now.toIso8601String(),
      'announcements': all.map((a) => a.toStaffJson()).toList(),
    });
  }

  Response _handleGetAnnouncement(Request request, String id) {
    final guarded = _guard(request);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;

    final ann = repository.getById(id);
    if (ann == null) {
      return _jsonResponse(404, {
        'error': 'NOT_FOUND',
        'message': 'Announcement "$id" was not found.',
      });
    }

    if (auth.role == UserRole.campusUser) {
      if (ann.status != AnnouncementStatus.published) {
        rbacDeniedCount++;
        return _jsonResponse(403, {
          'error': 'RBAC_FORBIDDEN',
          'message': 'Campus users may only view published announcements.',
        });
      }
      return _jsonResponse(200, {'announcement': ann.toMinimizedCampusJson()});
    }

    return _jsonResponse(200, {'announcement': ann.toStaffJson()});
  }

  Future<Response> _handleCreateDraft(Request request) async {
    final guarded = _guard(request, allowedRoles: [UserRole.author]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final body = await _parseJsonBody(request);
    final title = body['title'] as String?;
    final content = body['body'] as String?;
    final categoryStr = (body['category'] as String?) ?? 'general';
    final targetAudience = (body['targetAudience'] as String?) ?? 'All Campus';
    final pinned = (body['pinned'] as bool?) ?? false;

    final validation = AnnouncementValidator.validateDraftPayload(
      title: title,
      body: content,
      targetAudience: targetAudience,
    );

    if (!validation.isValid) {
      validationRejectionCount++;
      repository.recordAudit(
        correlationId: corrId,
        actorId: auth.userId!,
        actorRole: auth.role!.wireName,
        action: 'CREATE_DRAFT_INVALID_INPUT',
        outcome: 'INVALID',
        timestamp: automationEngine.now,
        details: {'errors': validation.errors},
      );
      return _jsonResponse(400, {
        'error': 'VALIDATION_ERROR',
        'message': validation.errors.join(' '),
        'errors': validation.errors,
        'correlationId': corrId,
      });
    }

    final now = automationEngine.now;
    final created = Announcement(
      id: repository.nextAnnouncementId(),
      title: title!.trim(),
      body: content!.trim(),
      category: AnnouncementCategory.fromWire(categoryStr),
      targetAudience: targetAudience.trim(),
      pinned: pinned,
      status: AnnouncementStatus.draft,
      authorId: auth.userId!,
      authorName: auth.displayName!,
      createdAt: now,
      updatedAt: now,
    );

    repository.save(created);
    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'DRAFT_CREATED',
      announcementId: created.id,
      previousStatus: 'none',
      newStatus: AnnouncementStatus.draft.wireName,
      outcome: 'SUCCESS',
      timestamp: now,
      details: {
        'title': created.title,
        'category': created.category.wireName,
        'pinned': created.pinned,
      },
    );

    return _jsonResponse(201, {'announcement': created.toStaffJson()});
  }

  Future<Response> _handleUpdateDraft(Request request, String id) async {
    final guarded = _guard(request, allowedRoles: [UserRole.author]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final existing = repository.getById(id);
    if (existing == null) {
      return _jsonResponse(404, {
        'error': 'NOT_FOUND',
        'message': 'Announcement "$id" not found.',
      });
    }

    if (existing.status != AnnouncementStatus.draft &&
        existing.status != AnnouncementStatus.rejected) {
      return _jsonResponse(400, {
        'error': 'INVALID_STATE_OPERATION',
        'message':
            'Only announcements in "draft" or "rejected" state can be edited by an author (current: "${existing.status.wireName}").',
      });
    }

    final body = await _parseJsonBody(request);
    final title = (body['title'] as String?) ?? existing.title;
    final content = (body['body'] as String?) ?? existing.body;
    final targetAudience =
        (body['targetAudience'] as String?) ?? existing.targetAudience;
    final category = body['category'] != null
        ? AnnouncementCategory.fromWire(body['category'] as String)
        : existing.category;
    final pinned = (body['pinned'] as bool?) ?? existing.pinned;

    final validation = AnnouncementValidator.validateDraftPayload(
      title: title,
      body: content,
      targetAudience: targetAudience,
    );

    if (!validation.isValid) {
      validationRejectionCount++;
      return _jsonResponse(400, {
        'error': 'VALIDATION_ERROR',
        'message': validation.errors.join(' '),
        'errors': validation.errors,
      });
    }

    final updated = existing.copyWith(
      title: title.trim(),
      body: content.trim(),
      targetAudience: targetAudience.trim(),
      category: category,
      pinned: pinned,
      status: AnnouncementStatus.draft,
      updatedAt: automationEngine.now,
    );
    repository.save(updated);

    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'DRAFT_UPDATED',
      announcementId: updated.id,
      previousStatus: existing.status.wireName,
      newStatus: updated.status.wireName,
      outcome: 'SUCCESS',
      timestamp: automationEngine.now,
      details: {'title': updated.title},
    );

    return _jsonResponse(200, {'announcement': updated.toStaffJson()});
  }

  Future<Response> _handleSubmitForReview(Request request, String id) async {
    final guarded = _guard(request, allowedRoles: [UserRole.author]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final existing = repository.getById(id);
    if (existing == null) {
      return _jsonResponse(404, {
        'error': 'NOT_FOUND',
        'message': 'Announcement "$id" not found.',
      });
    }

    final transition = AnnouncementValidator.validateStateTransition(
      from: existing.status,
      to: AnnouncementStatus.inReview,
    );
    if (!transition.isValid) {
      validationRejectionCount++;
      return _jsonResponse(400, {
        'error': 'INVALID_STATE_TRANSITION',
        'message': transition.errors.first,
      });
    }

    final submitted = existing.copyWith(
      status: AnnouncementStatus.inReview,
      updatedAt: automationEngine.now,
    );
    repository.save(submitted);

    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'SUBMITTED_FOR_REVIEW',
      announcementId: submitted.id,
      previousStatus: existing.status.wireName,
      newStatus: submitted.status.wireName,
      outcome: 'SUCCESS',
      timestamp: automationEngine.now,
      details: {'title': submitted.title},
    );

    return _jsonResponse(200, {'announcement': submitted.toStaffJson()});
  }

  Future<Response> _handleReviewDecision(Request request, String id) async {
    final guarded = _guard(request, allowedRoles: [UserRole.reviewer]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final existing = repository.getById(id);
    if (existing == null) {
      return _jsonResponse(404, {
        'error': 'NOT_FOUND',
        'message': 'Announcement "$id" not found.',
      });
    }

    final body = await _parseJsonBody(request);
    final decision = (body['decision'] as String?)?.toLowerCase() ?? 'approve';
    final notes = (body['reviewNotes'] as String?)?.trim() ?? '';

    final targetStatus = decision == 'reject'
        ? AnnouncementStatus.rejected
        : AnnouncementStatus.approved;

    final transition = AnnouncementValidator.validateStateTransition(
      from: existing.status,
      to: targetStatus,
    );
    if (!transition.isValid) {
      validationRejectionCount++;
      return _jsonResponse(400, {
        'error': 'INVALID_STATE_TRANSITION',
        'message': transition.errors.first,
      });
    }

    if (targetStatus == AnnouncementStatus.rejected && notes.isEmpty) {
      validationRejectionCount++;
      return _jsonResponse(400, {
        'error': 'VALIDATION_ERROR',
        'message': 'Reviewer notes are required when rejecting an announcement.',
      });
    }

    final reviewed = existing.copyWith(
      status: targetStatus,
      reviewerId: auth.userId,
      reviewNotes: notes.isEmpty ? 'Approved by Reviewer.' : notes,
      updatedAt: automationEngine.now,
    );
    repository.save(reviewed);

    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: targetStatus == AnnouncementStatus.approved
          ? 'REVIEW_APPROVED'
          : 'REVIEW_REJECTED',
      announcementId: reviewed.id,
      previousStatus: existing.status.wireName,
      newStatus: reviewed.status.wireName,
      outcome: 'SUCCESS',
      timestamp: automationEngine.now,
      details: {
        'title': reviewed.title,
        'reviewNotes': reviewed.reviewNotes,
      },
    );

    return _jsonResponse(200, {'announcement': reviewed.toStaffJson()});
  }

  Future<Response> _handleSchedule(Request request, String id) async {
    final guarded = _guard(request, allowedRoles: [UserRole.publisher]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final existing = repository.getById(id);
    if (existing == null) {
      return _jsonResponse(404, {
        'error': 'NOT_FOUND',
        'message': 'Announcement "$id" not found.',
      });
    }

    final transition = AnnouncementValidator.validateStateTransition(
      from: existing.status,
      to: AnnouncementStatus.scheduled,
    );
    if (!transition.isValid) {
      validationRejectionCount++;
      repository.recordAudit(
        correlationId: corrId,
        actorId: auth.userId!,
        actorRole: auth.role!.wireName,
        action: 'SCHEDULE_INVALID_STATE',
        announcementId: existing.id,
        previousStatus: existing.status.wireName,
        newStatus: existing.status.wireName,
        outcome: 'INVALID',
        timestamp: automationEngine.now,
        details: {'error': transition.errors.first},
      );
      return _jsonResponse(400, {
        'error': 'INVALID_STATE_TRANSITION',
        'message': transition.errors.first,
      });
    }

    final body = await _parseJsonBody(request);
    DateTime? publishAt;
    DateTime? expiresAt;
    try {
      if (body['publishAt'] != null) {
        publishAt = DateTime.parse(body['publishAt'] as String).toUtc();
      }
      if (body['expiresAt'] != null) {
        expiresAt = DateTime.parse(body['expiresAt'] as String).toUtc();
      }
    } catch (_) {
      validationRejectionCount++;
      return _jsonResponse(400, {
        'error': 'INVALID_DATE_FORMAT',
        'message': 'publishAt and expiresAt must be valid ISO-8601 timestamps.',
      });
    }

    final windowValidation = AnnouncementValidator.validateScheduleWindow(
      publishAt: publishAt,
      expiresAt: expiresAt,
    );
    if (!windowValidation.isValid) {
      validationRejectionCount++;
      return _jsonResponse(400, {
        'error': 'INVALID_SCHEDULE_WINDOW',
        'message': windowValidation.errors.join(' '),
        'errors': windowValidation.errors,
      });
    }

    final pinned = (body['pinned'] as bool?) ?? existing.pinned;
    final simulateFailure = FailureSimulationMode.fromWire(
      body['simulateFailure'] as String?,
    );

    // Week 13 SA7 Conflict Check
    final conflictCheck = ConflictDetector.evaluate(
      candidate: existing,
      publishAt: publishAt!,
      expiresAt: expiresAt!,
      pinned: pinned,
      existingAnnouncements: repository.getAllAnnouncements(),
    );

    if (conflictCheck.hasConflict) {
      conflictRejectionCount++;
      repository.recordAudit(
        correlationId: corrId,
        actorId: auth.userId!,
        actorRole: auth.role!.wireName,
        action: 'SCHEDULE_CONFLICT_REJECTED',
        announcementId: existing.id,
        previousStatus: existing.status.wireName,
        newStatus: existing.status.wireName,
        outcome: 'DENIED',
        timestamp: automationEngine.now,
        details: {
          'conflicts': conflictCheck.conflicts.map((c) => c.toJson()).toList(),
        },
      );
      return _jsonResponse(409, {
        'error': 'SCHEDULE_CONFLICT',
        'message': conflictCheck.conflicts.first.reason,
        'conflicts': conflictCheck.conflicts.map((c) => c.toJson()).toList(),
        'correlationId': corrId,
      });
    }

    final scheduled = existing.copyWith(
      status: AnnouncementStatus.scheduled,
      publishAt: publishAt,
      expiresAt: expiresAt,
      pinned: pinned,
      simulateFailure: simulateFailure,
      retryCount: 0,
      clearLastError: true,
      clearNextRetryAt: true,
      updatedAt: automationEngine.now,
    );
    repository.save(scheduled);

    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'ANNOUNCEMENT_SCHEDULED',
      announcementId: scheduled.id,
      previousStatus: existing.status.wireName,
      newStatus: scheduled.status.wireName,
      outcome: 'SUCCESS',
      timestamp: automationEngine.now,
      details: {
        'title': scheduled.title,
        'publishAt': publishAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'pinned': pinned,
        'simulateFailure': simulateFailure.wireName,
      },
    );

    return _jsonResponse(200, {'announcement': scheduled.toStaffJson()});
  }

  /// Week 13 SA7: Human recovery route for announcements in
  /// `publish_failed_permanent` state.
  Future<Response> _handleHumanRecovery(Request request, String id) async {
    final guarded = _guard(request, allowedRoles: [UserRole.publisher]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final existing = repository.getById(id);
    if (existing == null) {
      return _jsonResponse(404, {
        'error': 'NOT_FOUND',
        'message': 'Announcement "$id" not found.',
      });
    }

    if (existing.status != AnnouncementStatus.publishFailedPermanent) {
      return _jsonResponse(400, {
        'error': 'INVALID_RECOVERY_STATE',
        'message':
            'Only announcements in "publish_failed_permanent" state require human recovery (current: "${existing.status.wireName}").',
      });
    }

    final body = await _parseJsonBody(request);
    final resolutionNote =
        (body['resolutionNote'] as String?)?.trim() ??
        'Corrected downstream broadcast channel configuration and cleared permanent error.';
    final publishImmediately = (body['publishImmediately'] as bool?) ?? true;

    final now = automationEngine.now;
    final recoveredStatus = publishImmediately
        ? AnnouncementStatus.published
        : AnnouncementStatus.scheduled;

    final recovered = existing.copyWith(
      status: recoveredStatus,
      publishedAt: publishImmediately ? now : existing.publishedAt,
      expiresAt: existing.expiresAt ?? now.add(const Duration(hours: 24)),
      simulateFailure: FailureSimulationMode.none,
      retryCount: 0,
      clearLastError: true,
      clearNextRetryAt: true,
      updatedAt: now,
    );
    repository.save(recovered);

    if (publishImmediately) {
      automationEngine.publishedTotal++;
    }

    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'HUMAN_RECOVERY_RESOLVED_PERMANENT_FAILURE',
      announcementId: recovered.id,
      previousStatus: AnnouncementStatus.publishFailedPermanent.wireName,
      newStatus: recovered.status.wireName,
      outcome: 'SUCCESS',
      timestamp: now,
      details: {
        'title': recovered.title,
        'previousError': existing.lastError,
        'resolutionNote': resolutionNote,
        'publishImmediately': publishImmediately,
      },
    );

    return _jsonResponse(200, {'announcement': recovered.toStaffJson()});
  }

  Future<Response> _handleArchive(Request request, String id) async {
    final guarded = _guard(request, allowedRoles: [UserRole.publisher]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final existing = repository.getById(id);
    if (existing == null) {
      return _jsonResponse(404, {
        'error': 'NOT_FOUND',
        'message': 'Announcement "$id" not found.',
      });
    }

    final transition = AnnouncementValidator.validateStateTransition(
      from: existing.status,
      to: AnnouncementStatus.archived,
    );
    if (!transition.isValid) {
      validationRejectionCount++;
      return _jsonResponse(400, {
        'error': 'INVALID_STATE_TRANSITION',
        'message': transition.errors.first,
      });
    }

    final now = automationEngine.now;
    final archived = existing.copyWith(
      status: AnnouncementStatus.archived,
      archivedAt: now,
      updatedAt: now,
    );
    repository.save(archived);

    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'ANNOUNCEMENT_ARCHIVED',
      announcementId: archived.id,
      previousStatus: existing.status.wireName,
      newStatus: archived.status.wireName,
      outcome: 'SUCCESS',
      timestamp: now,
      details: {'title': archived.title},
    );

    return _jsonResponse(200, {'announcement': archived.toStaffJson()});
  }

  Future<Response> _handleAutomationTick(Request request) async {
    final guarded = _guard(request, allowedRoles: [UserRole.publisher]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final body = await _parseJsonBody(request);
    final advanceMinutes = (body['advanceMinutes'] as num?)?.toInt() ?? 0;
    final advanceSeconds = (body['advanceSeconds'] as num?)?.toInt() ?? 0;
    final ignoreRetryBackoff = (body['ignoreRetryBackoff'] as bool?) ?? true;

    if (advanceMinutes != 0 || advanceSeconds != 0) {
      automationEngine.advanceClock(
        Duration(minutes: advanceMinutes, seconds: advanceSeconds),
      );
    }

    final report = automationEngine.runTick(
      correlationId: corrId,
      triggeredBy: auth.userId!,
      ignoreRetryBackoff: ignoreRetryBackoff,
    );

    return _jsonResponse(200, {
      'tickReport': report.toJson(),
      'virtualTime': automationEngine.now.toIso8601String(),
    });
  }

  Response _handleGetAuditLogs(Request request) {
    final guarded = _guard(
      request,
      allowedRoles: [UserRole.reviewer, UserRole.publisher],
    );
    if (guarded.errorResponse != null) return guarded.errorResponse!;

    final logs = repository.getAuditLogs(limit: 250);
    return _jsonResponse(200, {
      'count': logs.length,
      'auditLogs': logs.map((l) => l.toJson()).toList(),
    });
  }

  Response _handleCreateSnapshot(Request request) {
    final guarded = _guard(request, allowedRoles: [UserRole.publisher]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final meta = repository.createSnapshot(timestamp: automationEngine.now);
    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'STATE_SNAPSHOT_CREATED',
      outcome: 'SUCCESS',
      timestamp: automationEngine.now,
      details: meta,
    );
    return _jsonResponse(200, {'snapshot': meta});
  }

  Response _handleRestoreSnapshot(Request request) {
    final guarded = _guard(request, allowedRoles: [UserRole.publisher]);
    if (guarded.errorResponse != null) return guarded.errorResponse!;
    final auth = guarded.auth;
    final corrId = _corrId(request);

    final ok = repository.restoreSnapshot();
    if (!ok) {
      return _jsonResponse(400, {
        'error': 'NO_SNAPSHOT_AVAILABLE',
        'message': 'No snapshot is available to restore.',
      });
    }

    repository.recordAudit(
      correlationId: corrId,
      actorId: auth.userId!,
      actorRole: auth.role!.wireName,
      action: 'STATE_ROLLBACK_RESTORED',
      outcome: 'SUCCESS',
      timestamp: automationEngine.now,
      details: {'note': 'Restored repository state from point-in-time snapshot.'},
    );
    return _jsonResponse(200, {
      'restored': true,
      'virtualTime': automationEngine.now.toIso8601String(),
    });
  }

  Response _handleResetDemo(Request request) {
    automationEngine.resetClock();
    repository.seedControlledDataset(referenceTime: automationEngine.now);
    return _jsonResponse(200, {
      'reset': true,
      'virtualTime': automationEngine.now.toIso8601String(),
      'message':
          'Controlled dataset and virtual clock reset to initial demonstration state.',
    });
  }
}
