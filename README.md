# Project 26: Campus Announcement Scheduler

A complete **Flutter Web** and **Dart (`package:shelf`) REST API** system implementing controlled publication, schedule conflict detection, resilient retry/escalation automation, role-based security, and automatic expiration for campus announcements (**Weeks 13–18 Deliverables**).

---

## Quick Start (Android Studio & CLI)

### 1. Install Dependencies
```powershell
flutter pub get
```

### 2. Run the Backend REST API Server (Optional — App also includes automatic offline fallback!)
```powershell
dart run bin/server.dart
```
- Listens on `http://127.0.0.1:8080`
- Health endpoint: `http://127.0.0.1:8080/api/v1/health`
- Metrics endpoint: `http://127.0.0.1:8080/api/v1/metrics`

### 3. Launch the Flutter Web Application
```powershell
flutter run -d chrome
```
*(Note: If `bin/server.dart` is not running, the Flutter Web client automatically activates its **Week 18 Prepared Controlled Fallback Engine** so all workflows, role switches, scheduler ticks, and security probes work out-of-the-box with zero configuration.)*

### 4. Run Automated Tests & Static Analysis (Week 15 IA6)
```powershell
flutter analyze
flutter test
```

### 5. Run Performance & Load Evaluation Benchmark (Week 16)
```powershell
dart run tool/benchmark_runner.dart
```

---

## Pre-Seeded Demo Accounts (One-Click Switcher in Top UI Bar)

| Role | Email | Password | Permissions |
| :--- | :--- | :--- | :--- |
| **Content Author** | `author@campus.edu` | `AuthorPass!26` | Create drafts, edit drafts/rejected items, submit for review |
| **Reviewer** | `reviewer@campus.edu` | `ReviewerPass!26` | Inspect `in_review` queue, approve or reject with mandatory notes, view audit logs |
| **Publisher** | `publisher@campus.edu` | `PublisherPass!26` | Schedule approved announcements, run conflict checks, trigger scheduler ticks, resolve permanent failures, archive expired items, manage snapshots/rollbacks |
| **Campus User** | `student@campus.edu` | `StudentPass!26` | View active `published` announcements only (strictly data-minimized DTO) |

---

## Repository Structure & Deliverables Index

```text
├── bin/
│   └── server.dart                                # Standalone Dart Shelf HTTP/HTTPS server entrypoint
├── lib/
│   ├── main.dart                                  # Flutter Web application entrypoint
│   ├── shared/
│   │   ├── models/
│   │   │   ├── announcement.dart                  # Bounded workflow states, Staff DTO & Minimized Campus DTO
│   │   │   └── audit_log.dart                     # Structured audit log with automatic secret/token redaction
│   │   └── validation/
│   │       └── announcement_validator.dart        # Input bounds, XSS prevention & state transition matrix
│   ├── backend/
│   │   ├── automation/
│   │   │   ├── automation_engine.dart             # Scheduled publish, exponential backoff retry, escalation, auto-expire
│   │   │   └── conflict_detector.dart             # Pinned slot & duplicate title overlap detection (HTTP 409)
│   │   ├── security/
│   │   │   └── auth_service.dart                  # Salted SHA-256 password hashing & HMAC-SHA256 bearer tokens
│   │   ├── storage/
│   │   │   ├── announcement_repository.dart       # Controlled dataset seeder, audit store & snapshot/rollback
│   │   │   └── file_persistence_adapter.dart      # JSON file persistence adapter
│   │   └── server_app.dart                        # REST API routes, RBAC guard, security headers & telemetry
│   └── frontend/
│       ├── services/
│       │   └── api_client.dart                    # Dual-transport HTTP + Week 18 Prepared Fallback client
│       ├── state/
│       │   └── app_state.dart                     # Flutter Web state controller & security probe runner
│       └── screens/
│           └── dashboard_screen.dart              # Responsive 5-tab Flutter Web UI
├── openapi/
│   └── openapi.yaml                               # Complete OpenAPI 3.0.3 API specification
├── test/
│   ├── backend_workflow_and_security_test.dart    # 12 traceable functional, boundary, conflict, auth & recovery tests
│   └── widget_test.dart                           # Flutter Web responsive widget & state test
├── tool/
│   └── benchmark_runner.dart                      # Week 16 Ordinary & Peak workload performance benchmark
├── docs/
│   ├── WEEK13_AUTOMATION_SA7.md                   # Workflow boundary, trigger decision, retry policy & structured logs
│   ├── WEEK14_SECURITY_SA8_IA5.md                 # RBAC matrix, crypto justification, negative paths & residual risks
│   ├── WEEK15_TESTING_HARDENING_IA6.md            # Traceability matrix, defects fixed & regression rerun evidence
│   ├── WEEK16_PERFORMANCE_DEPLOYMENT.md           # Workload models, measured p50/p95/p99 metrics & rollback rehearsal
│   ├── WEEK17_UAT_AND_ARCHITECTURE_SA9_AS3.md     # UAT scenarios/dispositions, Mermaid diagrams, ADRs & maintenance plan
│   └── WEEK18_DEFENSE_AND_EVIDENCE_MAP_E3.md      # Master evidence map, 5-minute live defense script & viva Q&A
└── .env.example                                   # Protected configuration template without secrets
```
