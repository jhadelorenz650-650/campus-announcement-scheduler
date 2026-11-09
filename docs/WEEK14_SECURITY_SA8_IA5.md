# Week 14 Secure Integration — SA8 and IA5

## 1. Security Controls Overview & Justification
Every cryptographic and security control in **Project 26** is tied to a concrete protection objective:

| Control | Implementation Location | Protection Objective & Justification |
| :--- | :--- | :--- |
| **Iterative Salted SHA-256 Password Hashing** | `AuthService.hashPassword` (`lib/backend/security/auth_service.dart`) | Protects user credentials at rest against rainbow-table and credential-dump attacks using per-user salts and 1,000 iterative rounds. Plaintext passwords are never stored. |
| **HMAC-SHA256 Signed Bearer Tokens** | `AuthService.issueToken` / `verifyToken` (`lib/backend/security/auth_service.dart`) | Guarantees stateless message authentication, role claim integrity (`role`), and expiration (`exp`) using constant-time signature comparison (`_constantTimeEquals`) to prevent timing side-channels and privilege tampering. |
| **Role-Based Access Control (RBAC)** | `ServerApp._guard` (`lib/backend/server_app.dart`) | Enforces separation of duties across `author`, `reviewer`, `publisher`, and `campus_user`. Every mutating endpoint explicitly whitelists permitted roles. |
| **HTTPS / TLS & Hardened HTTP Headers** | `bin/server.dart` (`SecurityContext`) + `ServerApp._securityAndTelemetryMiddleware` | Protects data in transit via `--tls` (`ENABLE_TLS=true`) and attaches `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Content-Security-Policy: default-src 'self'`, and `Cache-Control: no-store`. |
| **Protected Configuration** | `.env.example` + `Platform.environment` (`bin/server.dart`) | Keeps `JWT_HMAC_SECRET`, TLS private keys, and port bindings outside source control. |
| **Input Validation & XSS Prevention** | `AnnouncementValidator` (`lib/shared/validation/announcement_validator.dart`) | Enforces length boundaries (`title: 5..120`, `body: 10..2000`, `window: 5m..90d`) and blocks `<script>`, `javascript:`, `onerror=`, `onload=`, `<iframe>`, and `<object>` payloads with `HTTP 400`. |
| **Safe Structured Logging** | `AuditLogEntry.redactSensitiveMap` (`lib/shared/models/audit_log.dart`) | Automatically recursively scrubs `password`, `token`, `secret`, `authorization`, and JWT-formatted strings into `[REDACTED]` / `[REDACTED_TOKEN]` before storage or output. |
| **Data Minimization** | `Announcement.toMinimizedCampusJson` (`lib/shared/models/announcement.dart`) | Ensures `campus_user` callers only receive active `published` announcements and strips internal fields (`authorId`, `reviewerId`, `reviewNotes`, `retryCount`, `lastError`, `simulateFailure`). |

---

## 2. Role-Based Authorization Matrix (RBAC)

| Endpoint / Operation | Content Author (`author`) | Reviewer (`reviewer`) | Publisher (`publisher`) | Campus User (`campus_user`) |
| :--- | :---: | :---: | :---: | :---: |
| `POST /api/v1/announcements` (Create Draft) | **ALLOW** | `403 Forbidden` | `403 Forbidden` | `403 Forbidden` |
| `PUT /api/v1/announcements/:id` (Edit Draft) | **ALLOW** | `403 Forbidden` | `403 Forbidden` | `403 Forbidden` |
| `POST /api/v1/announcements/:id/submit` | **ALLOW** | `403 Forbidden` | `403 Forbidden` | `403 Forbidden` |
| `POST /api/v1/announcements/:id/review` | `403 Forbidden` | **ALLOW** | `403 Forbidden` | `403 Forbidden` |
| `POST /api/v1/announcements/:id/schedule` | `403 Forbidden` | `403 Forbidden` | **ALLOW** | `403 Forbidden` |
| `POST /api/v1/announcements/:id/recover` | `403 Forbidden` | `403 Forbidden` | **ALLOW** | `403 Forbidden` |
| `POST /api/v1/announcements/:id/archive` | `403 Forbidden` | `403 Forbidden` | **ALLOW** | `403 Forbidden` |
| `POST /api/v1/automation/tick` | `403 Forbidden` | `403 Forbidden` | **ALLOW** | `403 Forbidden` |
| `GET /api/v1/audit-logs` | `403 Forbidden` | **ALLOW** | **ALLOW** | `403 Forbidden` |
| `GET /api/v1/announcements` | Full Staff DTO | Full Staff DTO | Full Staff DTO | **Published Only + Minimized DTO** |

---

## 3. Demonstrated Negative-Path Evidence (Altered, Expired, Invalid, Unauthorized)

All four behaviors are verified in automated tests (`test/backend_workflow_and_security_test.dart`) and interactive one-click probes in **Tab 4 (Security & Negative Lab)** of the Flutter Web UI:

1. **Altered / Tampered Token (`HTTP 401 AUTH_INVALID_SIGNATURE`)**:
   - Payload modified to escalate `author` to `publisher` without the server's HMAC key.
   - Response:
     ```json
     {
       "error": "AUTH_INVALID_SIGNATURE",
       "message": "Token HMAC-SHA256 signature verification failed (altered or forged token).",
       "correlationId": "corr-10008"
     }
     ```
2. **Expired Token (`HTTP 401 AUTH_TOKEN_EXPIRED`)**:
   - Token with `exp < currentUtcTimestamp` presented to `/api/v1/announcements`.
   - Response:
     ```json
     {
       "error": "AUTH_TOKEN_EXPIRED",
       "message": "Authentication token has expired.",
       "correlationId": "corr-10009"
     }
     ```
3. **Unauthorized Role Action (`HTTP 403 RBAC_FORBIDDEN`)**:
   - `author@campus.edu` attempts `POST /api/v1/announcements/ANN-105/schedule`.
   - Response:
     ```json
     {
       "error": "RBAC_FORBIDDEN",
       "message": "Role \"Content Author\" is not authorized to perform this action. Required: Publisher.",
       "correlationId": "corr-10010"
     }
     ```
4. **Invalid / Malicious Input (`HTTP 400 VALIDATION_ERROR`)**:
   - `<script>fetch("https://evil.tld")</script>` submitted in draft title.
   - Response:
     ```json
     {
       "error": "VALIDATION_ERROR",
       "message": "Input contains prohibited script or active HTML injection patterns.",
       "errors": ["Input contains prohibited script or active HTML injection patterns."],
       "correlationId": "corr-10011"
     }
     ```

---

## 4. Residual Risk Register

| Risk ID | Residual Risk Description | Likelihood | Impact | Mitigation / Compensating Control |
| :--- | :--- | :---: | :---: | :--- |
| **RR-01** | **Stateless Token Revocation Window**: HMAC-SHA256 tokens remain valid until `exp` (60 min) if a user device is compromised mid-session unless the server secret is rotated. | Low | Medium | Keep `TOKEN_TTL_MINUTES` short (15–60 min) and add an in-memory revoked-token denylist (`jti`) in production. |
| **RR-02** | **Local JSON File Locking Under Multi-Process Clustering**: Single-process JSON persistence (`data/announcements_db.json`) does not support multi-node horizontal write locking. | Low | Medium | Suitable for single-instance campus prototype; migrate `StoragePersistenceAdapter` to PostgreSQL with row-level transactions for multi-node production. |
| **RR-03** | **Self-Signed TLS Certificate Trust in Local Browsers**: Local `--tls` uses self-signed certificates that require manual trust in Chrome during local testing. | Medium | Low | Terminate TLS at a campus reverse proxy (Nginx / Cloudflare / Let's Encrypt) in production while keeping HSTS enabled. |

