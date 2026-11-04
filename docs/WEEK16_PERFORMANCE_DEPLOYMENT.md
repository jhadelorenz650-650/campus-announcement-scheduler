# Week 16 Performance, Reliability and Deployment Evaluation

## 1. Workload Models Defined
To evaluate the **Campus Announcement Scheduler** under realistic campus conditions, two repeatable workload models are codified in `tool/benchmark_runner.dart`:

1. **Ordinary Workload Model**:
   - **Scenario**: Typical weekday campus portal traffic where students check active announcements (`70%`), staff inspect the workflow pipeline (`20%`), and health probes poll `/api/v1/health` (`10%`).
   - **Parameters**: `200` total requests at concurrency `10`.
2. **Peak Workload Model**:
   - **Scenario**: Exam-week or emergency weather alert burst where 50 concurrent student/staff sessions simultaneously fetch announcements while telemetry probes poll the server.
   - **Parameters**: `500` total requests at concurrency `50`.

---

## 2. Measured Performance, Throughput, Error & Resource Evidence

Executed via `dart run tool/benchmark_runner.dart` on Dart SDK `3.11.0` (`windows_x64`):

| Metric | Ordinary Workload (200 reqs, c=10) | Peak Workload (500 reqs, c=50) | Target SLA Threshold | Status |
| :--- | :---: | :---: | :---: | :---: |
| **Success Rate** | `200 / 200` (`100%`) | `500 / 500` (`100%`) | `>= 99.9%` | PASS |
| **Error Rate (`4xx`/`5xx`)** | `0.0%` | `0.0%` | `< 0.1%` | PASS |
| **Throughput (`req/sec`)** | `784.8 req/s` | `1,333.8 req/s` | `>= 250 req/s` | PASS |
| **Client End-to-End Latency `p50`** | `10.97 ms` | `32.72 ms` | `< 100 ms` | PASS |
| **Client End-to-End Latency `p95`** | `17.37 ms` | `57.49 ms` | `< 200 ms` | PASS |
| **Client End-to-End Latency `p99`** | `35.44 ms` | `58.92 ms` | `< 350 ms` | PASS |
| **Server-Internal Handler Latency (`p50`/`p95`/`p99`)** | `0.14 ms` / `0.39 ms` / `0.73 ms` | `0.14 ms` / `0.39 ms` / `0.73 ms` | `< 10 ms` | PASS |
| **Memory RSS Footprint** | `230.99 MB` (Baseline) | `260.13 MB` (`+29.14 MB`) | `< 512 MB` | PASS |

---

## 3. Monitoring & Health Signals Verification

The backend exposes two dedicated observability endpoints:
1. **`GET /api/v1/health`**:
   - Reports `"HEALTHY"` when the escalation queue (`publish_failed_permanent`) is `0`, and `"DEGRADED_ACTION_REQUIRED"` when one or more announcements require human intervention by a Publisher.
   - Sample verified payload:
     ```json
     {
       "status": "HEALTHY",
       "service": "campus-announcement-scheduler-api",
       "version": "1.0.0",
       "uptimeSeconds": 12,
       "virtualTime": "2026-11-04T13:39:37.168697Z",
       "clockOffsetMinutes": 0,
       "checks": {
         "repository": "UP",
         "automationScheduler": "UP",
         "escalationQueueDepth": 0
       }
     }
     ```
2. **`GET /api/v1/metrics`**:
   - Tracks HTTP request counts, `4xx`/`5xx` error counters, rolling `p50`/`p95`/`p99` handler latency, security rejection counters (`authFailureCount`, `rbacDeniedCount`, `validationRejectionCount`), automation counters (`publishedTotal`, `transientFailuresTotal`, `transientRecoveriesTotal`, `permanentEscalationsTotal`, `autoExpirationsTotal`), and live announcement counts by status.

---

## 4. Environment Comparison

| Dimension | Local Development / Demo (`bin/server.dart`) | Prepared Offline Fallback (Flutter Web In-Memory) | Recommended Production Campus Deployment |
| :--- | :--- | :--- | :--- |
| **Transport** | HTTP `127.0.0.1:8080` or `--tls` HTTPS | In-process `shelf.Handler` inside Flutter Web | HTTPS (TLS 1.3 via Nginx / Cloud Load Balancer) |
| **Persistence** | JSON file (`data/announcements_db.json`) | Deterministic in-memory repository | PostgreSQL 16 with ACID transactions |
| **Scheduler Trigger** | 30s `Timer.periodic` + `/automation/tick` | On-demand `/automation/tick` UI controls | Dedicated worker + distributed advisory lock |
| **Secrets Management** | `.env` / environment variables | Ephemeral demo key | Cloud Secret Manager / Vault |

---

## 5. Rollback & Recovery Rehearsal

Rehearsed automatically in `tool/benchmark_runner.dart` and `T-REL-02`:
1. **Step 1 (Snapshot)**: Invoke `POST /api/v1/admin/snapshot` before maintenance or bulk scheduler release (`data/announcements_snapshot.json` written).
2. **Step 2 (Fault / Unintended State Mutation)**: Advance clock and execute scheduler tick mutating announcements.
3. **Step 3 (Rollback)**: Invoke `POST /api/v1/admin/rollback` to restore the exact pre-change state.
4. **Measured Recovery Time Objective (RTO)**: `19 ms` (`HTTP 200 OK`), zero data loss for all announcements and audit logs captured at snapshot time.

---

## 6. Conditional Readiness Recommendation

**Recommendation**: **Conditionally Ready for Controlled Campus Pilot Deployment.**
- **Strengths**: Sub-60ms `p99` latency under 50-concurrent burst load, `0.0%` error rate, deterministic conflict prevention, automated transient failure recovery, human escalation routing, and verified `< 20ms` state rollback.
- **Conditions Prior to University-Wide Production Cutover**:
  1. Replace single-node JSON file persistence (`FilePersistenceAdapter`) with PostgreSQL to support multi-instance horizontal scaling.
  2. Integrate university SSO (SAML 2.0 / OIDC) alongside the HMAC-SHA256 token service.
  3. Connect `AutomationEngine` to the live campus SMTP / push notification gateway.

