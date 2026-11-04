/// Week 15 Testing and Hardening (IA6):
/// Traceable Functional, Invalid-Input, Boundary, Interoperability/Conflict,
/// Authentication, Authorization, Reliability/Recovery, and Security Tests.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:campus_announcement_scheduler/backend/automation/automation_engine.dart';
import 'package:campus_announcement_scheduler/backend/security/auth_service.dart';
import 'package:campus_announcement_scheduler/backend/server_app.dart';
import 'package:campus_announcement_scheduler/backend/storage/announcement_repository.dart';

void main() {
  late AnnouncementRepository repo;
  late AuthService auth;
  late AutomationEngine engine;
  late ServerApp serverApp;
  late Handler handler;

  Future<({int status, Map<String, dynamic> body, Map<String, String> headers})>
  callApi(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? jsonBody,
  }) async {
    final req = Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: jsonBody != null ? jsonEncode(jsonBody) : null,
    );
    final res = await handler(req);
    final raw = await res.readAsString();
    final map = raw.isNotEmpty
        ? (jsonDecode(raw) as Map<String, dynamic>)
        : <String, dynamic>{};
    return (status: res.statusCode, body: map, headers: res.headers);
  }

  Future<String> loginAs(
    String email,
    String password, {
    String tokenMode = 'valid',
  }) async {
    final res = await callApi(
      'POST',
      '/api/v1/auth/login',
      jsonBody: {
        'email': email,
        'password': password,
        'tokenMode': tokenMode,
      },
    );
    expect(res.status, 200);
    return res.body['token'] as String;
  }

  setUp(() {
    repo = AnnouncementRepository(seedIfEmpty: true);
    auth = AuthService();
    engine = AutomationEngine(repository: repo);
    serverApp = ServerApp(
      repository: repo,
      authService: auth,
      automationEngine: engine,
    );
    handler = serverApp.handler;
  });

  group('1. Functional Workflow Tests (Normal & Rejection Paths)', () {
    test(
      'T-FUNC-01: Complete bounded lifecycle (Draft -> InReview -> Approved -> Scheduled -> Published -> Expired -> Archived)',
      () async {
        final authorToken = await loginAs('author@campus.edu', 'AuthorPass!26');
        final reviewerToken = await loginAs(
          'reviewer@campus.edu',
          'ReviewerPass!26',
        );
        final publisherToken = await loginAs(
          'publisher@campus.edu',
          'PublisherPass!26',
        );

        // Step 1: Author creates a Draft
        final createRes = await callApi(
          'POST',
          '/api/v1/announcements',
          token: authorToken,
          jsonBody: {
            'title': 'Spring Semester Library Extended Study Hours',
            'body':
                'The Main Campus Library will remain open 24/7 starting next Monday through the end of finals week.',
            'category': 'academic',
            'targetAudience': 'All Students',
            'pinned': false,
          },
        );
        expect(createRes.status, 201);
        final id = createRes.body['announcement']['id'] as String;
        expect(createRes.body['announcement']['status'], 'draft');

        // Step 2: Author submits Draft for Review
        final submitRes = await callApi(
          'POST',
          '/api/v1/announcements/$id/submit',
          token: authorToken,
        );
        expect(submitRes.status, 200);
        expect(submitRes.body['announcement']['status'], 'in_review');

        // Step 3: Reviewer approves announcement
        final reviewRes = await callApi(
          'POST',
          '/api/v1/announcements/$id/review',
          token: reviewerToken,
          jsonBody: {
            'decision': 'approve',
            'reviewNotes': 'Confirmed with Library Dean.',
          },
        );
        expect(reviewRes.status, 200);
        expect(reviewRes.body['announcement']['status'], 'approved');

        // Step 4: Publisher schedules announcement
        final pubTime = engine.now;
        final expTime = pubTime.add(const Duration(hours: 6));
        final schedRes = await callApi(
          'POST',
          '/api/v1/announcements/$id/schedule',
          token: publisherToken,
          jsonBody: {
            'publishAt': pubTime.toIso8601String(),
            'expiresAt': expTime.toIso8601String(),
            'pinned': false,
            'simulateFailure': 'none',
          },
        );
        expect(schedRes.status, 200);
        expect(schedRes.body['announcement']['status'], 'scheduled');

        // Step 5: Scheduler tick publishes announcement
        final tick1 = await callApi(
          'POST',
          '/api/v1/automation/tick',
          token: publisherToken,
          jsonBody: {'advanceMinutes': 1},
        );
        expect(tick1.status, 200);
        expect(
          (tick1.body['tickReport']['publishedIds'] as List).contains(id),
          isTrue,
        );

        final afterPub = await callApi(
          'GET',
          '/api/v1/announcements/$id',
          token: publisherToken,
        );
        expect(afterPub.body['announcement']['status'], 'published');

        // Step 6: Advance clock past expiresAt -> Auto-Expires
        final tick2 = await callApi(
          'POST',
          '/api/v1/automation/tick',
          token: publisherToken,
          jsonBody: {'advanceMinutes': 400},
        );
        expect(tick2.status, 200);
        expect(
          (tick2.body['tickReport']['expiredIds'] as List).contains(id),
          isTrue,
        );

        // Step 7: Publisher archives expired announcement
        final archRes = await callApi(
          'POST',
          '/api/v1/announcements/$id/archive',
          token: publisherToken,
        );
        expect(archRes.status, 200);
        expect(archRes.body['announcement']['status'], 'archived');
      },
    );

    test(
      'T-FUNC-02: Reviewer rejection returns item to Author, who edits and resubmits',
      () async {
        final authorToken = await loginAs('author@campus.edu', 'AuthorPass!26');
        final reviewerToken = await loginAs(
          'reviewer@campus.edu',
          'ReviewerPass!26',
        );

        // ANN-106 is seeded in 'in_review'
        final rejRes = await callApi(
          'POST',
          '/api/v1/announcements/ANN-106/review',
          token: reviewerToken,
          jsonBody: {
            'decision': 'reject',
            'reviewNotes': 'Please add clinic room number.',
          },
        );
        expect(rejRes.status, 200);
        expect(rejRes.body['announcement']['status'], 'rejected');

        // Author updates rejected draft
        final editRes = await callApi(
          'PUT',
          '/api/v1/announcements/ANN-106',
          token: authorToken,
          jsonBody: {
            'body':
                'Walk-in flu vaccinations are available free of charge in Wellness Center Room 204 Monday–Friday 09:00–16:00.',
          },
        );
        expect(editRes.status, 200);
        expect(editRes.body['announcement']['status'], 'draft');

        // Author resubmits
        final resubRes = await callApi(
          'POST',
          '/api/v1/announcements/ANN-106/submit',
          token: authorToken,
        );
        expect(resubRes.status, 200);
        expect(resubRes.body['announcement']['status'], 'in_review');
      },
    );
  });

  group('2. Invalid-Input, Boundary & State Machine Tests', () {
    test('T-BND-01: Rejects title shorter than 5 chars or longer than 120 chars', () async {
      final authorToken = await loginAs('author@campus.edu', 'AuthorPass!26');

      final tooShort = await callApi(
        'POST',
        '/api/v1/announcements',
        token: authorToken,
        jsonBody: {
          'title': 'Hi',
          'body': 'Valid announcement body text exceeding ten characters.',
          'category': 'general',
          'targetAudience': 'All Campus',
        },
      );
      expect(tooShort.status, 400);
      expect(tooShort.body['error'], 'VALIDATION_ERROR');

      final tooLong = await callApi(
        'POST',
        '/api/v1/announcements',
        token: authorToken,
        jsonBody: {
          'title': 'A' * 125,
          'body': 'Valid announcement body text exceeding ten characters.',
          'category': 'general',
          'targetAudience': 'All Campus',
        },
      );
      expect(tooLong.status, 400);
    });

    test('T-BND-02: Rejects invalid schedule windows (expiresAt <= publishAt or > 90 days)', () async {
      final publisherToken = await loginAs(
        'publisher@campus.edu',
        'PublisherPass!26',
      );
      final now = engine.now;

      // ANN-105 is 'approved'
      final invertedWindow = await callApi(
        'POST',
        '/api/v1/announcements/ANN-105/schedule',
        token: publisherToken,
        jsonBody: {
          'publishAt': now.toIso8601String(),
          'expiresAt': now.subtract(const Duration(minutes: 10)).toIso8601String(),
        },
      );
      expect(invertedWindow.status, 400);
      expect(invertedWindow.body['error'], 'INVALID_SCHEDULE_WINDOW');

      final over90Days = await callApi(
        'POST',
        '/api/v1/announcements/ANN-105/schedule',
        token: publisherToken,
        jsonBody: {
          'publishAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(days: 95)).toIso8601String(),
        },
      );
      expect(over90Days.status, 400);
      expect(over90Days.body['error'], 'INVALID_SCHEDULE_WINDOW');
    });

    test('T-BND-03: Rejects illegal workflow state transitions (Draft -> Schedule)', () async {
      final publisherToken = await loginAs(
        'publisher@campus.edu',
        'PublisherPass!26',
      );
      final now = engine.now;

      // ANN-107 is in 'draft' state
      final res = await callApi(
        'POST',
        '/api/v1/announcements/ANN-107/schedule',
        token: publisherToken,
        jsonBody: {
          'publishAt': now.toIso8601String(),
          'expiresAt': now.add(const Duration(hours: 4)).toIso8601String(),
        },
      );
      expect(res.status, 400);
      expect(res.body['error'], 'INVALID_STATE_TRANSITION');
    });
  });

  group('3. Conflict Detection & Interoperability Tests (Week 13 SA7)', () {
    test('T-CONF-01: Rejects overlapping pinned announcement in same category and audience with 409 Conflict', () async {
      final authorToken = await loginAs('author@campus.edu', 'AuthorPass!26');
      final reviewerToken = await loginAs(
        'reviewer@campus.edu',
        'ReviewerPass!26',
      );
      final publisherToken = await loginAs(
        'publisher@campus.edu',
        'PublisherPass!26',
      );

      // ANN-101 is Pinned + Academic + All Campus active from (now - 4h) to (now + 20h)
      final draft = await callApi(
        'POST',
        '/api/v1/announcements',
        token: authorToken,
        jsonBody: {
          'title': 'Second Pinned Academic Notice Overlapping Exam Window',
          'body':
              'Attempting to book the pinned Academic slot while ANN-101 is still active.',
          'category': 'academic',
          'targetAudience': 'All Campus',
          'pinned': true,
        },
      );
      final id = draft.body['announcement']['id'] as String;
      await callApi('POST', '/api/v1/announcements/$id/submit', token: authorToken);
      await callApi(
        'POST',
        '/api/v1/announcements/$id/review',
        token: reviewerToken,
        jsonBody: {'decision': 'approve', 'reviewNotes': 'Approved.'},
      );

      final conflictRes = await callApi(
        'POST',
        '/api/v1/announcements/$id/schedule',
        token: publisherToken,
        jsonBody: {
          'publishAt': engine.now.toIso8601String(),
          'expiresAt': engine.now.add(const Duration(hours: 5)).toIso8601String(),
          'pinned': true,
        },
      );
      expect(conflictRes.status, 409);
      expect(conflictRes.body['error'], 'SCHEDULE_CONFLICT');
      expect(conflictRes.body['conflicts'], isNotEmpty);

      // Scheduling the same item as UNPINNED succeeds without conflict
      final unpinnedRes = await callApi(
        'POST',
        '/api/v1/announcements/$id/schedule',
        token: publisherToken,
        jsonBody: {
          'publishAt': engine.now.toIso8601String(),
          'expiresAt': engine.now.add(const Duration(hours: 5)).toIso8601String(),
          'pinned': false,
        },
      );
      expect(unpinnedRes.status, 200);
    });
  });

  group('4. Authentication, RBAC, Safe Logging & Data Minimization (Week 14 SA8/IA5)', () {
    test('T-SEC-01: Rejects missing, altered/tampered, and expired tokens with HTTP 401', () async {
      final missingRes = await callApi('GET', '/api/v1/announcements');
      expect(missingRes.status, 401);
      expect(missingRes.body['error'], 'AUTH_MISSING_TOKEN');

      final tamperedToken = await loginAs(
        'author@campus.edu',
        'AuthorPass!26',
        tokenMode: 'tampered',
      );
      final tamperedRes = await callApi(
        'GET',
        '/api/v1/announcements',
        token: tamperedToken,
      );
      expect(tamperedRes.status, 401);
      expect(tamperedRes.body['error'], 'AUTH_INVALID_SIGNATURE');

      final expiredToken = await loginAs(
        'reviewer@campus.edu',
        'ReviewerPass!26',
        tokenMode: 'expired',
      );
      final expiredRes = await callApi(
        'GET',
        '/api/v1/announcements',
        token: expiredToken,
      );
      expect(expiredRes.status, 401);
      expect(expiredRes.body['error'], 'AUTH_TOKEN_EXPIRED');
    });

    test('T-SEC-02: Enforces RBAC least privilege with HTTP 403 Forbidden', () async {
      final authorToken = await loginAs('author@campus.edu', 'AuthorPass!26');
      final studentToken = await loginAs('student@campus.edu', 'StudentPass!26');

      // Author cannot approve or schedule
      final authorApprove = await callApi(
        'POST',
        '/api/v1/announcements/ANN-106/review',
        token: authorToken,
        jsonBody: {'decision': 'approve'},
      );
      expect(authorApprove.status, 403);

      final authorSchedule = await callApi(
        'POST',
        '/api/v1/announcements/ANN-105/schedule',
        token: authorToken,
        jsonBody: {},
      );
      expect(authorSchedule.status, 403);

      // Campus user cannot create draft or read audit logs
      final studentCreate = await callApi(
        'POST',
        '/api/v1/announcements',
        token: studentToken,
        jsonBody: {
          'title': 'Unauthorized Student Post',
          'body': 'Students cannot create official announcements.',
          'category': 'general',
          'targetAudience': 'All Campus',
        },
      );
      expect(studentCreate.status, 403);

      final studentAudit = await callApi(
        'GET',
        '/api/v1/audit-logs',
        token: studentToken,
      );
      expect(studentAudit.status, 403);
    });

    test('T-SEC-03: Rejects XSS/Script injection payloads with HTTP 400', () async {
      final authorToken = await loginAs('author@campus.edu', 'AuthorPass!26');
      final xssRes = await callApi(
        'POST',
        '/api/v1/announcements',
        token: authorToken,
        jsonBody: {
          'title': 'Scholarship <script>alert(1)</script>',
          'body': 'Apply now at javascript:evil()',
          'category': 'academic',
          'targetAudience': 'All Campus',
        },
      );
      expect(xssRes.status, 400);
      expect(xssRes.body['error'], 'VALIDATION_ERROR');
    });

    test('T-SEC-04: Enforces Data Minimization for Campus Users & Safe Logging Redaction', () async {
      final studentToken = await loginAs('student@campus.edu', 'StudentPass!26');
      final publisherToken = await loginAs(
        'publisher@campus.edu',
        'PublisherPass!26',
      );

      final campusRes = await callApi(
        'GET',
        '/api/v1/announcements',
        token: studentToken,
      );
      expect(campusRes.status, 200);
      expect(campusRes.body['dataMinimized'], isTrue);
      final list = campusRes.body['announcements'] as List<dynamic>;
      expect(list, isNotEmpty);
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        expect(map['status'], 'published');
        expect(map.containsKey('reviewNotes'), isFalse);
        expect(map.containsKey('authorId'), isFalse);
        expect(map.containsKey('lastError'), isFalse);
        expect(map.containsKey('retryCount'), isFalse);
      }

      // Check security headers
      expect(
        campusRes.headers['x-content-type-options'],
        equals('nosniff'),
      );
      expect(campusRes.headers['x-frame-options'], equals('DENY'));

      // Trigger failed login and verify password is redacted in audit logs
      await callApi(
        'POST',
        '/api/v1/auth/login',
        jsonBody: {
          'email': 'author@campus.edu',
          'password': 'SuperSecretWrongPassword123!',
        },
      );

      final logsRes = await callApi(
        'GET',
        '/api/v1/audit-logs',
        token: publisherToken,
      );
      expect(logsRes.status, 200);
      final logsJson = jsonEncode(logsRes.body['auditLogs']);
      expect(logsJson.contains('SuperSecretWrongPassword123!'), isFalse);
      expect(logsJson.contains('[REDACTED]'), isTrue);
    });
  });

  group('5. Reliability, Transient Auto-Retry & Permanent Human Recovery (Week 13 SA7)', () {
    test(
      'T-REL-01: Transient failure (ANN-103) auto-recovers on retry; Permanent failure (ANN-104) escalates to human action and recovers on Publisher action',
      () async {
        final publisherToken = await loginAs(
          'publisher@campus.edu',
          'PublisherPass!26',
        );

        // Tick 1:
        // - ANN-102 (normal) publishes immediately
        // - ANN-103 (transient_once) fails attempt #1 -> publish_failed_transient
        // - ANN-104 (permanent_failure) escalates -> publish_failed_permanent
        final tick1 = await callApi(
          'POST',
          '/api/v1/automation/tick',
          token: publisherToken,
        );
        expect(tick1.status, 200);
        final report1 = tick1.body['tickReport'] as Map<String, dynamic>;
        expect(report1['publishedIds'], contains('ANN-102'));
        expect(report1['transientFailedIds'], contains('ANN-103'));
        expect(report1['permanentEscalatedIds'], contains('ANN-104'));

        // Tick 2:
        // - ANN-103 retries and automatically recovers -> published!
        // - ANN-104 remains in publish_failed_permanent awaiting human action
        final tick2 = await callApi(
          'POST',
          '/api/v1/automation/tick',
          token: publisherToken,
          jsonBody: {'advanceSeconds': 10},
        );
        expect(tick2.status, 200);
        final report2 = tick2.body['tickReport'] as Map<String, dynamic>;
        expect(report2['recoveredTransientIds'], contains('ANN-103'));

        final ann103 = await callApi(
          'GET',
          '/api/v1/announcements/ANN-103',
          token: publisherToken,
        );
        expect(ann103.body['announcement']['status'], 'published');

        final ann104Before = await callApi(
          'GET',
          '/api/v1/announcements/ANN-104',
          token: publisherToken,
        );
        expect(
          ann104Before.body['announcement']['status'],
          'publish_failed_permanent',
        );

        // Human recovery on ANN-104 by Publisher
        final recoverRes = await callApi(
          'POST',
          '/api/v1/announcements/ANN-104/recover',
          token: publisherToken,
          jsonBody: {
            'resolutionNote':
                'Reconfigured emergency broadcast channel schema and verified delivery.',
            'publishImmediately': true,
          },
        );
        expect(recoverRes.status, 200);
        expect(recoverRes.body['announcement']['status'], 'published');
      },
    );

    test('T-REL-02: Point-in-time Snapshot and Rollback restores full repository state (Week 16)', () async {
      final publisherToken = await loginAs(
        'publisher@campus.edu',
        'PublisherPass!26',
      );

      final snapRes = await callApi(
        'POST',
        '/api/v1/admin/snapshot',
        token: publisherToken,
      );
      expect(snapRes.status, 200);

      // Mutate state by running scheduler tick
      await callApi('POST', '/api/v1/automation/tick', token: publisherToken);
      final afterTick = await callApi(
        'GET',
        '/api/v1/announcements/ANN-102',
        token: publisherToken,
      );
      expect(afterTick.body['announcement']['status'], 'published');

      // Rollback to snapshot
      final rollbackRes = await callApi(
        'POST',
        '/api/v1/admin/rollback',
        token: publisherToken,
      );
      expect(rollbackRes.status, 200);

      final restored = await callApi(
        'GET',
        '/api/v1/announcements/ANN-102',
        token: publisherToken,
      );
      expect(restored.body['announcement']['status'], 'scheduled');
    });
  });
}

