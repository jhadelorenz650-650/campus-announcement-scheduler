/// Week 13 Automation Foundation (SA7):
/// Scheduled publishing, exponential backoff retry for transient failures,
/// permanent failure routing for human action, and automatic expiration.
library;

import '../../shared/models/announcement.dart';
import '../storage/announcement_repository.dart';

class SchedulerTickReport {
  final DateTime virtualTime;
  final List<String> publishedIds;
  final List<String> recoveredTransientIds;
  final List<String> transientFailedIds;
  final List<String> permanentEscalatedIds;
  final List<String> expiredIds;

  const SchedulerTickReport({
    required this.virtualTime,
    required this.publishedIds,
    required this.recoveredTransientIds,
    required this.transientFailedIds,
    required this.permanentEscalatedIds,
    required this.expiredIds,
  });

  Map<String, dynamic> toJson() => {
    'virtualTime': virtualTime.toUtc().toIso8601String(),
    'publishedIds': publishedIds,
    'recoveredTransientIds': recoveredTransientIds,
    'transientFailedIds': transientFailedIds,
    'permanentEscalatedIds': permanentEscalatedIds,
    'expiredIds': expiredIds,
    'totalProcessed':
        publishedIds.length +
        recoveredTransientIds.length +
        transientFailedIds.length +
        permanentEscalatedIds.length +
        expiredIds.length,
  };
}

class AutomationEngine {
  final AnnouncementRepository repository;
  final int maxRetryAttempts;
  final Duration baseRetryBackoff;

  Duration _clockOffset = Duration.zero;

  // Week 16 Telemetry Counters
  int totalTicksRun = 0;
  int publishedTotal = 0;
  int transientFailuresTotal = 0;
  int transientRecoveriesTotal = 0;
  int permanentEscalationsTotal = 0;
  int autoExpirationsTotal = 0;

  AutomationEngine({
    required this.repository,
    this.maxRetryAttempts = 3,
    this.baseRetryBackoff = const Duration(seconds: 5),
  });

  /// Returns current effective UTC time (real UTC clock + virtual offset).
  DateTime get now => DateTime.now().toUtc().add(_clockOffset);

  Duration get clockOffset => _clockOffset;

  void advanceClock(Duration delta) {
    _clockOffset += delta;
  }

  void resetClock() {
    _clockOffset = Duration.zero;
  }

  /// Calculates exponential backoff: `base * 2^(attempt - 1)`.
  Duration computeBackoff(int attemptNumber) {
    final multiplier = 1 << (attemptNumber - 1).clamp(0, 6);
    return Duration(
      milliseconds: baseRetryBackoff.inMilliseconds * multiplier,
    );
  }

  /// Executes a single deterministic scheduler cycle:
  /// 1. Evaluates `scheduled` and `publishFailedTransient` items due at `now`.
  /// 2. Applies retry/recovery or human escalation policies on failure.
  /// 3. Evaluates `published` items whose `expiresAt <= now` and expires them.
  SchedulerTickReport runTick({
    String correlationId = 'corr-scheduler-tick',
    String triggeredBy = 'automation-scheduler',
    bool ignoreRetryBackoff = false,
  }) {
    totalTicksRun++;
    final currentTime = now;
    final publishedIds = <String>[];
    final recoveredTransientIds = <String>[];
    final transientFailedIds = <String>[];
    final permanentEscalatedIds = <String>[];
    final expiredIds = <String>[];

    final all = repository.getAllAnnouncements();

    for (final ann in all) {
      // Phase 1: Scheduled Publication & Transient Retry Evaluation
      if (ann.status == AnnouncementStatus.scheduled ||
          ann.status == AnnouncementStatus.publishFailedTransient) {
        final dueToPublish =
            ann.publishAt != null && !ann.publishAt!.isAfter(currentTime);
        if (!dueToPublish) continue;

        if (ann.status == AnnouncementStatus.publishFailedTransient &&
            !ignoreRetryBackoff &&
            ann.nextRetryAt != null &&
            ann.nextRetryAt!.isAfter(currentTime)) {
          continue;
        }

        _processPublicationAttempt(
          ann: ann,
          currentTime: currentTime,
          correlationId: correlationId,
          publishedIds: publishedIds,
          recoveredTransientIds: recoveredTransientIds,
          transientFailedIds: transientFailedIds,
          permanentEscalatedIds: permanentEscalatedIds,
        );
      }

      // Phase 2: Automatic Expiration of Published Announcements
      final latest = repository.getById(ann.id) ?? ann;
      if (latest.status == AnnouncementStatus.published &&
          latest.expiresAt != null &&
          !latest.expiresAt!.isAfter(currentTime)) {
        final expired = latest.copyWith(
          status: AnnouncementStatus.expired,
          expiredAt: currentTime,
          updatedAt: currentTime,
        );
        repository.save(expired);
        autoExpirationsTotal++;
        expiredIds.add(expired.id);

        repository.recordAudit(
          correlationId: correlationId,
          actorId: triggeredBy,
          actorRole: 'system',
          action: 'ANNOUNCEMENT_AUTO_EXPIRED',
          announcementId: expired.id,
          previousStatus: AnnouncementStatus.published.wireName,
          newStatus: AnnouncementStatus.expired.wireName,
          outcome: 'SUCCESS',
          timestamp: currentTime,
          details: {
            'title': expired.title,
            'expiresAt': expired.expiresAt?.toUtc().toIso8601String(),
            'virtualTime': currentTime.toIso8601String(),
          },
        );
      }
    }

    return SchedulerTickReport(
      virtualTime: currentTime,
      publishedIds: publishedIds,
      recoveredTransientIds: recoveredTransientIds,
      transientFailedIds: transientFailedIds,
      permanentEscalatedIds: permanentEscalatedIds,
      expiredIds: expiredIds,
    );
  }

  void _processPublicationAttempt({
    required Announcement ann,
    required DateTime currentTime,
    required String correlationId,
    required List<String> publishedIds,
    required List<String> recoveredTransientIds,
    required List<String> transientFailedIds,
    required List<String> permanentEscalatedIds,
  }) {
    final attemptNum = ann.retryCount + 1;

    // Case A: Permanent failure simulation OR max retries exceeded
    if (ann.simulateFailure == FailureSimulationMode.permanentFailure ||
        attemptNum > maxRetryAttempts) {
      const errorMsg =
          'DOWNSTREAM_GATEWAY_REJECTED_PERMANENT: Target emergency broadcast channel rejected payload schema (unrecoverable without publisher intervention).';
      final escalated = ann.copyWith(
        status: AnnouncementStatus.publishFailedPermanent,
        retryCount: attemptNum,
        lastError: errorMsg,
        clearNextRetryAt: true,
        updatedAt: currentTime,
      );
      repository.save(escalated);
      permanentEscalationsTotal++;
      permanentEscalatedIds.add(escalated.id);

      repository.recordAudit(
        correlationId: correlationId,
        actorId: 'automation-scheduler',
        actorRole: 'system',
        action: 'PUBLISH_FAILED_PERMANENT_ESCALATED',
        announcementId: escalated.id,
        previousStatus: ann.status.wireName,
        newStatus: AnnouncementStatus.publishFailedPermanent.wireName,
        outcome: 'FAILURE_PERMANENT',
        timestamp: currentTime,
        details: {
          'title': escalated.title,
          'attempt': attemptNum,
          'maxRetries': maxRetryAttempts,
          'error': errorMsg,
          'routedTo': 'Publisher Human Escalation Queue',
        },
      );
      return;
    }

    // Case B: Transient failure on first attempt (auto-recovers on retry #2)
    if (ann.simulateFailure == FailureSimulationMode.transientOnce &&
        ann.retryCount == 0) {
      final backoff = computeBackoff(attemptNum);
      final nextRetry = currentTime.add(backoff);
      const transientError =
          'GATEWAY_TIMEOUT_503: Campus Push Notification Gateway timed out (transient network blip). Scheduled automatic retry.';

      final failedTransient = ann.copyWith(
        status: AnnouncementStatus.publishFailedTransient,
        retryCount: attemptNum,
        nextRetryAt: nextRetry,
        lastError: transientError,
        updatedAt: currentTime,
      );
      repository.save(failedTransient);
      transientFailuresTotal++;
      transientFailedIds.add(failedTransient.id);

      repository.recordAudit(
        correlationId: correlationId,
        actorId: 'automation-scheduler',
        actorRole: 'system',
        action: 'PUBLISH_ATTEMPT_FAILED_TRANSIENT',
        announcementId: failedTransient.id,
        previousStatus: ann.status.wireName,
        newStatus: AnnouncementStatus.publishFailedTransient.wireName,
        outcome: 'FAILURE_TRANSIENT',
        timestamp: currentTime,
        details: {
          'title': failedTransient.title,
          'attempt': attemptNum,
          'maxRetries': maxRetryAttempts,
          'backoffSeconds': backoff.inSeconds,
          'nextRetryAt': nextRetry.toIso8601String(),
          'error': transientError,
        },
      );
      return;
    }

    // Case C: Successful publication (either normal or recovered after retry!)
    final wasTransientRecovery =
        ann.status == AnnouncementStatus.publishFailedTransient ||
        ann.retryCount > 0;

    final published = ann.copyWith(
      status: AnnouncementStatus.published,
      publishedAt: currentTime,
      clearNextRetryAt: true,
      clearLastError: true,
      simulateFailure: FailureSimulationMode.none,
      updatedAt: currentTime,
    );
    repository.save(published);
    publishedTotal++;

    if (wasTransientRecovery) {
      transientRecoveriesTotal++;
      recoveredTransientIds.add(published.id);
      repository.recordAudit(
        correlationId: correlationId,
        actorId: 'automation-scheduler',
        actorRole: 'system',
        action: 'PUBLISH_RECOVERED_AFTER_RETRY',
        announcementId: published.id,
        previousStatus: ann.status.wireName,
        newStatus: AnnouncementStatus.published.wireName,
        outcome: 'SUCCESS',
        timestamp: currentTime,
        details: {
          'title': published.title,
          'recoveredOnAttempt': attemptNum,
          'previousErrorResolved': ann.lastError ?? 'GATEWAY_TIMEOUT_503',
          'publishedAt': currentTime.toIso8601String(),
        },
      );
    } else {
      publishedIds.add(published.id);
      repository.recordAudit(
        correlationId: correlationId,
        actorId: 'automation-scheduler',
        actorRole: 'system',
        action: 'ANNOUNCEMENT_PUBLISHED_SCHEDULED',
        announcementId: published.id,
        previousStatus: ann.status.wireName,
        newStatus: AnnouncementStatus.published.wireName,
        outcome: 'SUCCESS',
        timestamp: currentTime,
        details: {
          'title': published.title,
          'attempt': attemptNum,
          'publishedAt': currentTime.toIso8601String(),
          'expiresAt': published.expiresAt?.toUtc().toIso8601String(),
        },
      );
    }
  }
}

