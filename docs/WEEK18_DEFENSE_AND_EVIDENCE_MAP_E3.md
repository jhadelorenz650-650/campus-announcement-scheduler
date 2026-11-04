# Week 18 Final Examination & Technical Defense Guide — E3

## 1. Master Evidence Map (Weeks 13–18 Traceability)

| Week & Competency | Required Deliverable / Evidence | Exact Repository File / Location | Verification Command / UI Action |
| :--- | :--- | :--- | :--- |
| **Week 13 — SA7** | Workflow boundary & trigger decision | `docs/WEEK13_AUTOMATION_SA7.md` (§1–§2) | Inspect state matrix in `lib/shared/validation/announcement_validator.dart` |
| **Week 13 — SA7** | Flutter Web screen flow | `lib/frontend/screens/dashboard_screen.dart` | Launch app; step through Tabs 1–5 |
| **Week 13 — SA7** | API contract | `openapi/openapi.yaml` | 15 documented REST endpoints & schemas |
| **Week 13 — SA7** | Scheduled publishing, expiration & conflict check | `lib/backend/automation/automation_engine.dart`, `conflict_detector.dart` | Tab 2: Click **Run Scheduler Tick Now** & Tab 4: Probe #5 (`409 Conflict`) |
| **Week 13 — SA7** | 1 Recovered transient failure + 1 Permanent failure routed for human action | `ANN-103` (transient -> recovered) & `ANN-104` (permanent -> human recovery) | Tab 2: Click **Run Scheduler Tick Now** twice, then click **Resolve & Recover** on `ANN-104` |
| **Week 14 — SA8/IA5** | Authentication, RBAC, HTTPS, protected config | `lib/backend/security/auth_service.dart`, `.env.example`, `bin/server.dart` | Top Bar Role Switcher + Tab 4 Probes #1, #2, #3 (`401` / `403`) |
| **Week 14 — SA8/IA5** | Input validation, safe logging, data minimization | `announcement_validator.dart`, `audit_log.dart`, `announcement.dart` | Tab 3: **Inspect Minimized JSON DTO** + Tab 5: `[REDACTED]` audit logs |
| **Week 14 — SA8/IA5** | Residual risk documentation | `docs/WEEK14_SECURITY_SA8_IA5.md` (§4) | Documented risks `RR-01` through `RR-03` |
| **Week 15 — IA6** | Functional, boundary, conflict, auth, RBAC, reliability & UI tests | `test/backend_workflow_and_security_test.dart`, `test/widget_test.dart` | Run `flutter test` (`13/13` passing tests) |
| **Week 15 — IA6** | Prioritized weaknesses fixed & regression evidence | `docs/WEEK15_TESTING_HARDENING_IA6.md` (§2) | Documented virtual-clock/JWT TTL decoupling fix & rerun |
| **Week 16** | Ordinary & peak workload models, latency/throughput/memory metrics | `tool/benchmark_runner.dart`, `docs/WEEK16_PERFORMANCE_DEPLOYMENT.md` | Run `dart run tool/benchmark_runner.dart` |
| **Week 16** | Health/monitoring signals, rollback rehearsal & readiness recommendation | `/api/v1/health`, `/api/v1/metrics`, `/api/v1/admin/rollback` | Tab 5: **Create Snapshot** & **Rollback to Snapshot** |
| **Week 17 — SA9/AS3** | UAT scenarios, findings, dispositions & retests | `docs/WEEK17_UAT_AND_ARCHITECTURE_SA9_AS3.md` (§1) | 8 controlled UAT scenarios (`UAT-01`..`UAT-08`) |
| **Week 17 — SA9/AS3** | Architecture/data-flow diagrams, ADRs, limitations & maintenance plan | `docs/WEEK17_UAT_AND_ARCHITECTURE_SA9_AS3.md` (§2–§4) | Mermaid diagrams + `ADR-01`..`ADR-03` |
| **Week 18 — E3** | Controlled data & prepared fallback for live defense | `lib/frontend/services/api_client.dart`, `announcement_repository.dart` | Top AppBar: **Prepared Fallback Active** toggle & **Reset Demo Data** button |

---

## 2. Step-by-Step 5-Minute Live Defense Script (Week 18)

### Preparation (30 seconds before defense)
1. Start the backend server in Terminal 1 (optional — the app also works standalone via Prepared Fallback!):
   ```powershell
   dart run bin/server.dart
   ```
2. Launch the Flutter Web application in Chrome (Terminal 2 or Android Studio Run button):
   ```powershell
   flutter run -d chrome
   ```
3. Click **"Reset Demo Data"** in the top-right bar to guarantee a clean, deterministic starting state (`ANN-101` through `ANN-107`).

### Step 1: Demonstrate Bounded Normal Workflow (1.5 minutes)
1. In the top bar, click **"Content Author"** (`Prof. Elena Vance`).
2. In **Tab 1 (Workflow Pipeline)**, locate `ANN-107` (*Graduate Thesis Formatting Workshop* in `Draft` state) and click **"Submit for Review (Author)"** → Status becomes `In Review`.
3. Switch role to **"Reviewer"** (`Dean Marcus Sterling`), locate `ANN-107`, and click **"Approve (Reviewer)"** → Status becomes `Approved`.
4. Switch role to **"Publisher"** (`Hannah Cho`), click **"Schedule Publication (Publisher)"** on `ANN-107`, keep `Normal Delivery (Healthy)`, and click **"Confirm & Run Conflict Check"** → Status becomes `Scheduled`.

### Step 2: Demonstrate Week 13 Automation, Transient Auto-Recovery & Permanent Escalation (1.5 minutes)
1. Open **Tab 2 (Automation & Recovery — SA7)**.
2. Click **"1. Run Scheduler Tick Now"**:
   - Point out that `ANN-102` and `ANN-107` publish immediately (`Published`).
   - Point out that `ANN-103` (*Cybersecurity MFA Upgrade*) simulated a transient gateway timeout (`503`) and moved to **Transient Failures Pending Automatic Retry (`Retry Attempts: 1/3`)**.
   - Point out that `ANN-104` (*Emergency Severed Fiber Line*) simulated a permanent gateway rejection and routed to **Permanent Failures Routed for Human Action**.
3. Click **"2. Advance +15m & Run Retry Tick"**:
   - Point out that `ANN-103` **automatically recovered** on Attempt #2 and is now `Published`!
4. On `ANN-104` in the Escalation Queue, click **"Human Action: Resolve & Recover (Publisher)"** → **"Resolve & Publish Immediately"**.
5. Click **"3. Advance +25h (Trigger Auto-Expiration)"** to show published announcements automatically transitioning to `Expired`, then click **"Archive Announcement"** on an expired card.

### Step 3: Demonstrate Week 14 Security, Privacy & Negative Paths (1 minute)
1. Open **Tab 3 (Campus Feed & Privacy)** and click **"Switch to Campus User"**:
   - Expand **"Inspect Minimized JSON DTO"** to show that `authorId`, `reviewerId`, `reviewNotes`, and `lastError` are stripped.
2. Open **Tab 4 (Security & Negative Lab)** and click **"Execute Probe"** on:
   - **1. Altered / Forged HMAC Signature** → `HTTP 401 AUTH_INVALID_SIGNATURE`
   - **2. Expired Session Token** → `HTTP 401 AUTH_TOKEN_EXPIRED`
   - **3. Unauthorized Role Violation** → `HTTP 403 RBAC_FORBIDDEN`
   - **4. Script / XSS Injection Payload** → `HTTP 400 VALIDATION_ERROR`
   - **5. Pinned Channel Slot Schedule Conflict** → `HTTP 409 SCHEDULE_CONFLICT`

### Step 4: Demonstrate Week 16 Observability, Rollback & Week 18 Fallback (1 minute)
1. Switch back to **"Publisher"** and open **Tab 5 (Audit, Health & Rollback)**.
2. Show the live latency (`p50`/`p95`), request counters, and `[REDACTED]` safe structured audit logs.
3. Click **"Create Snapshot"** and **"Rollback to Snapshot"** to demonstrate instant recovery.
4. Click the **"Live API Connected / Prepared Fallback Active"** pill in the top-right AppBar to prove the UI continues operating seamlessly even if the backend server is disconnected.

---

## 3. Technical Viva Defense Q&A Preparation

- **Q1: Why did you choose HMAC-SHA256 tokens and salted SHA-256 password hashing instead of plaintext sessions or heavy asymmetric RSA keys?**
  - *Defense*: Plaintext tokens allow trivial role spoofing (`author` changing cookie to `publisher`). HMAC-SHA256 provides cryptographic integrity and authenticity verification in $< 0.05\text{ ms}$ using a shared server secret (`JWT_HMAC_SECRET`), while salted 1,000-round SHA-256 prevents rainbow-table reversal of stored user passwords without requiring external native C libraries on Flutter Web.
- **Q2: How does your system prevent an infinite retry storm when a downstream notification gateway fails?**
  - *Defense*: `AutomationEngine` distinguishes between **transient failures** (which use bounded exponential backoff $\text{delay} = 5\text{s} \times 2^{\text{attempt}-1}$ capped at `maxRetryAttempts = 3`) and **permanent failures**. Once `retryCount` reaches the cap or a permanent schema rejection occurs, the announcement transitions to `publish_failed_permanent`, halting all automated retries and surfacing in the Publisher Escalation Queue (`GET /api/v1/health` also transitions to `DEGRADED_ACTION_REQUIRED`).
- **Q3: How did you ensure advancing the virtual clock for testing announcement expiration does not break authentication?**
  - *Defense*: During Week 15 testing (`T-FUNC-01`), we discovered that coupling JWT expiration checks to the virtual schedule clock caused operator tokens to expire when fast-forwarding `+25 hours`. We decoupled `AuthService.verifyToken` to use real UTC wall-clock time while `AutomationEngine` uses the virtual schedule clock offset.

---

## 4. Individual Contribution Record & Reflection Template

| Team Member Name / Student ID | Primary Responsibilities & Modules Owned | Key Technical Contributions | Individual Reflection Summary |
| :--- | :--- | :--- | :--- |
| **Student 1** *(Update Name / ID)* | Architecture, Backend API (`lib/backend/`), Automation Engine (`SA7`), Security (`SA8`/`IA5`), Flutter Web UI (`lib/frontend/`), Testing (`IA6`), Benchmarking & Documentation | Designed the bounded 10-state workflow, HMAC-SHA256 auth & RBAC guard, schedule conflict detector, exponential backoff retry & human recovery engine, responsive 5-tab Flutter Web console, and 13 automated test suites. | Building the Campus Announcement Scheduler demonstrated how explicit state machines, deterministic virtual-clock testing, and role-based data minimization prevent both operational race conditions and privilege-escalation vulnerabilities in campus-scale automation systems. |

