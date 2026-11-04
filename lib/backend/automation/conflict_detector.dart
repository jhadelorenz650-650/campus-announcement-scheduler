/// Week 13 Automation Foundation (SA7):
/// Conflict detection engine for scheduled campus announcements.
library;

import '../../shared/models/announcement.dart';

class ScheduleConflict {
  final String conflictingAnnouncementId;
  final String conflictingTitle;
  final String reason;
  final DateTime existingPublishAt;
  final DateTime existingExpiresAt;

  const ScheduleConflict({
    required this.conflictingAnnouncementId,
    required this.conflictingTitle,
    required this.reason,
    required this.existingPublishAt,
    required this.existingExpiresAt,
  });

  Map<String, dynamic> toJson() => {
    'conflictingAnnouncementId': conflictingAnnouncementId,
    'conflictingTitle': conflictingTitle,
    'reason': reason,
    'existingPublishAt': existingPublishAt.toUtc().toIso8601String(),
    'existingExpiresAt': existingExpiresAt.toUtc().toIso8601String(),
  };
}

class ConflictCheckResult {
  final bool hasConflict;
  final List<ScheduleConflict> conflicts;

  const ConflictCheckResult.clear() : hasConflict = false, conflicts = const [];
  const ConflictCheckResult.detected(this.conflicts) : hasConflict = true;
}

class ConflictDetector {
  /// Checks if scheduling [candidate] within `[publishAt, expiresAt]` conflicts
  /// with any active (`scheduled`, `publishFailedTransient`, or `published`)
  /// announcement in [existingAnnouncements].
  ///
  /// Conflict Rules:
  /// 1. Pinned Channel Slot Exclusivity: Two `pinned: true` announcements in
  ///    the same `category` and `targetAudience` cannot have overlapping windows.
  /// 2. Duplicate Title Collision: Two announcements with the exact same
  ///    normalized title in the same category cannot overlap in time.
  static ConflictCheckResult evaluate({
    required Announcement candidate,
    required DateTime publishAt,
    required DateTime expiresAt,
    required bool pinned,
    required List<Announcement> existingAnnouncements,
  }) {
    final conflicts = <ScheduleConflict>[];
    final activeStates = {
      AnnouncementStatus.scheduled,
      AnnouncementStatus.publishFailedTransient,
      AnnouncementStatus.published,
    };

    for (final other in existingAnnouncements) {
      if (other.id == candidate.id) continue;
      if (!activeStates.contains(other.status)) continue;
      if (other.publishAt == null || other.expiresAt == null) continue;

      final overlaps =
          publishAt.isBefore(other.expiresAt!) &&
          expiresAt.isAfter(other.publishAt!);
      if (!overlaps) continue;

      // Rule 1: Pinned slot exclusivity within same category & audience
      final sameCategory = other.category == candidate.category;
      final sameAudience =
          other.targetAudience.trim().toLowerCase() ==
          candidate.targetAudience.trim().toLowerCase();

      if (pinned && other.pinned && sameCategory && sameAudience) {
        conflicts.add(
          ScheduleConflict(
            conflictingAnnouncementId: other.id,
            conflictingTitle: other.title,
            reason:
                'Pinned slot conflict: Another pinned "${candidate.category.label}" announcement for "${candidate.targetAudience}" is already active in this time window.',
            existingPublishAt: other.publishAt!,
            existingExpiresAt: other.expiresAt!,
          ),
        );
        continue;
      }

      // Rule 2: Duplicate normalized title collision in overlapping window
      final sameTitle =
          other.title.trim().toLowerCase() ==
          candidate.title.trim().toLowerCase();
      if (sameCategory && sameTitle) {
        conflicts.add(
          ScheduleConflict(
            conflictingAnnouncementId: other.id,
            conflictingTitle: other.title,
            reason:
                'Duplicate title conflict: An announcement with the same title in "${candidate.category.label}" already overlaps this schedule window.',
            existingPublishAt: other.publishAt!,
            existingExpiresAt: other.expiresAt!,
          ),
        );
      }
    }

    return conflicts.isEmpty
        ? const ConflictCheckResult.clear()
        : ConflictCheckResult.detected(conflicts);
  }
}

