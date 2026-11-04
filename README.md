# PFEBSIT 002: Integrative Programming and Technologies 2
## Week 13: Automation Foundation — SA7

### Student Information
- **Student Name:** Martin, Jhade Lorenz Gedo C.
- **Course & Year:** Bachelor of Science in Information Technology (BSIT) — 3rd Year
- **Institution:** University of La Salette, Inc.
- **Project Assigned:** Project 26 — Campus Announcement Scheduler

---

## Project 26: Campus Announcement Scheduler (Week 13 Scope)

### 1. Problem and Intended Users
Approved announcements need controlled publication, automatic expiration, and collision-free scheduling. The primary users are:
- **Content Authors**: Draft and submit announcements for review.
- **Reviewers**: Evaluate announcements for policy compliance, approving or returning with mandatory revision notes.
- **Publishers**: Schedule approved announcements with automatic conflict detection, manage automation schedules, and resolve escalated permanent failures.
- **Campus Users**: Access active, non-expired announcements through a clean, published feed.

### 2. Bounded Workflow & State Machine
The student prototype implements a strict 10-state bounded state machine:
```text
[Draft] ---> [In Review] ---> [Approved] ---> [Scheduled] ---> [Published] ---> [Expired] ---> [Archived]
                 |                                |
                 v                                v (Fault Paths)
             [Rejected]                 +--------------------------------+
                                        | [Publish Failed - Transient]   | (Auto-retries with exponential backoff)
                                        | [Publish Failed - Permanent]   | (Routes to Publisher Human Action Queue)
                                        +--------------------------------+
```

### 3. Week 13 SA7 Required Deliverables Summary

| Requirement | Implementation Details | Evidence Location |
| :--- | :--- | :--- |
| **Workflow Boundary** | Covers `draft`, `in_review`, `rejected`, `approved`, `scheduled`, `publish_failed_transient`, `publish_failed_permanent`, `published`, `expired`, and `archived`. | `lib/shared/validation/announcement_validator.dart` |
| **Trigger Decision** | Hybrid trigger architecture: 30-second periodic background daemon worker (`Timer.periodic` in `bin/server.dart`) + on-demand virtual-clock execution (`POST /api/v1/automation/tick`). | `lib/backend/automation/automation_engine.dart` |
| **Flutter Web Screen Flow** | Responsive 5-tab interface: Workflow Pipeline, Automation & Recovery Console, Campus Feed, Security/Negative Lab, and Audit Logs. | `lib/frontend/screens/dashboard_screen.dart` |
| **API Contract** | Standardized REST API under `/api/v1/` with full request/response schemas. | `openapi/openapi.yaml` |
| **Retry & Recovery Policy** | Bounded exponential backoff retry ($5\text{s} \times 2^{\text{attempt}-1}$, max 3 attempts) for transient errors; permanent failure routing to Publisher Human Action Queue. | `lib/backend/automation/automation_engine.dart` |
| **Conflict Checks** | Conflict detection engine preventing overlapping pinned slots and duplicate active titles (`HTTP 409 SCHEDULE_CONFLICT`). | `lib/backend/automation/conflict_detector.dart` |
| **Structured Logs** | JSON audit logging capturing actor, correlation ID, state transition, and outcome. | `docs/WEEK13_AUTOMATION_SA7.md` (§6) |
| **Recovered Transient Failure** | `ANN-103` encounters simulated gateway timeout ($503$), transitions to `publish_failed_transient`, retries with backoff, and automatically recovers to `published`. | Live UI Tab 2 & Test `T-REL-01` |
| **Permanent Failure Routed to Human Action** | `ANN-104` encounters permanent downstream schema rejection, transitions to `publish_failed_permanent`, halts retries, routes to escalation queue, and resolves via manual action. | Live UI Tab 2 & Test `T-REL-01` |
| **Maintainability Note** | Pure-Dart domain engine with decoupled persistence and deterministic virtual clock for zero-friction testing. | `docs/WEEK13_AUTOMATION_SA7.md` (§7) |

---

## Setup and Execution Instructions

### 1. Prerequisites
- Flutter SDK (stable channel) with Web support enabled (`flutter config --enable-web`)
- Dart SDK 3.x+ (included with Flutter)
- Google Chrome or any modern browser

### 2. Get Dependencies
```bash
flutter pub get
```

### 3. Run the Backend REST API Server (Optional — App also features an automatic offline fallback!)
```bash
dart run bin/server.dart
```
- Server endpoint: `http://127.0.0.1:8080`
- Health check: `http://127.0.0.1:8080/api/v1/health`
- Metrics: `http://127.0.0.1:8080/api/v1/metrics`

### 4. Launch the Flutter Web Application
```bash
flutter run -d chrome
```

### 5. Run Automated Tests
```bash
flutter test
```
*(Runs 13 unit, widget, boundary, conflict, and recovery tests verifying the Week 13 automation lifecycle.)*

---

## Pre-Seeded Demonstration Accounts (One-Click Role Switcher in UI)

| Role | Email | Password | Access Rights |
| :--- | :--- | :--- | :--- |
| **Content Author** | `author@campus.edu` | `AuthorPass!26` | Create drafts, edit rejected announcements, submit for review |
| **Reviewer** | `reviewer@campus.edu` | `ReviewerPass!26` | Review queue, approve or reject with mandatory revision notes |
| **Publisher** | `publisher@campus.edu` | `PublisherPass!26` | Schedule publication, run conflict checks, trigger ticks, human recovery |
| **Campus User** | `student@campus.edu` | `StudentPass!26` | View active, non-expired published announcements |

---

## Detailed Week 13 Technical Documentation
For the complete technical report, workflow boundary analysis, trigger decisions, structured log extracts, and maintainability notes, please refer to:
👉 **[`docs/WEEK13_AUTOMATION_SA7.md`](docs/WEEK13_AUTOMATION_SA7.md)**
