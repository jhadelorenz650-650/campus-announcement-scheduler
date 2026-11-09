# Week 15 Testing and Hardening — IA6

## 1. Traceability Matrix
Every requirement across the bounded workflow, automation engine, and security integration is mapped to automated tests in `test/backend_workflow_and_security_test.dart` and `test/widget_test.dart`:

| Test ID | Category | Requirement / Risk Covered | Target Component / Endpoint | Expected Outcome | Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **T-FUNC-01** | Functional | Normal path (`Draft -> InReview -> Approved -> Scheduled -> Published -> Expired -> Archived`) | `/api/v1/announcements/*`, `/automation/tick` | `201 -> 200`, terminal state `archived` | PASS |
| **T-FUNC-02** | Functional | Reviewer rejection with notes (`in_review -> rejected`), Author edit (`PUT`) & resubmit (`in_review`) | `/review`, `PUT /announcements/:id`, `/submit` | `200 OK`, transitions verified | PASS |
| **T-BND-01** | Invalid-Input & Boundary | Title length boundaries (`< 5` chars and `> 120` chars rejected) | `AnnouncementValidator.validateDraftPayload` | `400 VALIDATION_ERROR` | PASS |
| **T-BND-02** | Boundary | Schedule window boundaries (`expiresAt <= publishAt` and `> 90 days` rejected) | `AnnouncementValidator.validateScheduleWindow` | `400 INVALID_SCHEDULE_WINDOW` | PASS |
| **T-BND-03** | State Boundary | Illegal state jump (`Draft -> Scheduled` bypassing approval) | `AnnouncementValidator.validateStateTransition` | `400 INVALID_STATE_TRANSITION` | PASS |
| **T-CONF-01** | Interoperability / Conflict | Overlapping `pinned: true` announcements in same category & audience rejected; unpinned allowed | `ConflictDetector.evaluate`, `/schedule` | `409 SCHEDULE_CONFLICT` then `200 OK` | PASS |
| **T-SEC-01** | Authentication | Missing token, tampered HMAC signature, and expired token rejected | `AuthService.verifyToken`, `ServerApp._guard` | `401 AUTH_MISSING_TOKEN`, `AUTH_INVALID_SIGNATURE`, `AUTH_TOKEN_EXPIRED` | PASS |
| **T-SEC-02** | Authorization (RBAC) | Author denied `/review` & `/schedule`; Campus User denied `POST /announcements` & `GET /audit-logs` | `ServerApp._guard` | `403 RBAC_FORBIDDEN` | PASS |
| **T-SEC-03** | Security / Injection | Active `<script>` and `javascript:` payloads rejected | `AnnouncementValidator` | `400 VALIDATION_ERROR` | PASS |
| **T-SEC-04** | Privacy & Safe Logging | Campus User receives minimized DTO (no `reviewNotes`/`authorId`); failed login password redacted in audit log; HSTS & `nosniff` headers present | `toMinimizedCampusJson`, `AuditLogEntry.redactSensitiveMap` | `200 OK`, `[REDACTED]` verified | PASS |
| **T-REL-01** | Reliability & Recovery | Transient failure (`ANN-103`) auto-retries & recovers; Permanent failure (`ANN-104`) routes to `publish_failed_permanent` & recovers via `/recover` | `AutomationEngine.runTick`, `/recover` | `ANN-103` & `ANN-104` reach `published` | PASS |
| **T-REL-02** | Reliability / Rollback | Point-in-time state snapshot creation, state mutation, and rollback restoration | `/admin/snapshot`, `/admin/rollback` | State restored to pre-tick baseline | PASS |
| **T-UI-01** | Flutter Web State & UI | Responsive dashboard renders, executes scheduler tick, switches role to Campus User (verifies data minimization), and executes tampered token probe | `DashboardScreen`, `AppState` | All widget assertions pass | PASS |

---

## 2. Prioritized Weaknesses Identified, Fixed & Regression Evidence

During Week 15 hardening and initial test execution (`task-45`), two high-priority defects were uncovered, fixed, and verified via regression reruns:

### Weakness #1 (High Priority): Virtual Clock Fast-Forward Invalidated Operator JWT Sessions
- **Initial Failure Observed**:
  In `T-FUNC-01`, advancing the scheduler's virtual clock by `+400 minutes` (`POST /api/v1/automation/tick` with `advanceMinutes: 400`) to trigger automatic announcement expiration caused the subsequent `POST /api/v1/announcements/:id/archive` request to fail with `HTTP 401 AUTH_TOKEN_EXPIRED` (Expected `200`, Actual `401`).
- **Root Cause**:
  `ServerApp._guard` passed `now: automationEngine.now` into `authService.verifyToken()`. Because session tokens have a 60-minute TTL, fast-forwarding the announcement schedule clock by `+400 minutes` caused the authentication guard to believe 6.6 hours of real time had elapsed.
- **Fix Applied (`lib/backend/server_app.dart`)**:
  Decoupled authentication session TTL verification (which now strictly uses real UTC wall-clock time) from the announcement scheduler's virtual clock (`automationEngine.now`).
- **Regression Rerun Evidence**:
  Re-running `flutter test` confirmed `T-FUNC-01` (`Draft -> InReview -> Approved -> Scheduled -> Published -> Expired -> Archived`) passes end-to-end while `T-SEC-01` continues to reject expired tokens with `HTTP 401`.

### Weakness #2 (High Priority): Default Constructor Repository Split in `ServerApp`
- **Initial Weakness Observed**:
  In `ServerApp`'s default constructor initializer list, calling `ServerApp()` without arguments instantiated two separate `AnnouncementRepository()` objects—one bound to `this.repository` and another bound to `this.automationEngine`.
- **Fix Applied (`lib/backend/server_app.dart`)**:
  Refactored `ServerApp` constructor to delegate to a private redirecting constructor `ServerApp._internal` so `this.repository` and `this.automationEngine` always share the single `AnnouncementRepository` instance.
- **Regression Rerun Evidence**:
  Verified in `T-UI-01` and `T-REL-01` that scheduler ticks immediately update the announcement statuses returned by `GET /api/v1/announcements`.

---

## 3. Test Execution Output
```text
$ flutter analyze
Analyzing Campus Announcement Scheduler...
No issues found!

$ flutter test
00:00 +0: loading test/backend_workflow_and_security_test.dart
00:02 +13: All tests passed!
```

