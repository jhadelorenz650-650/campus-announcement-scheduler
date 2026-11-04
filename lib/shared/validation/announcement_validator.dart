/// Centralized Input Validation, XSS Sanitization, and Bounded State Machine
/// Enforcement (Week 13 SA7, Week 14 SA8/IA5, Week 15 IA6).
library;

import '../models/announcement.dart';

class ValidationResult {
  final bool isValid;
  final List<String> errors;

  const ValidationResult.valid() : isValid = true, errors = const [];
  const ValidationResult.invalid(this.errors) : isValid = false;
}

class AnnouncementValidator {
  static const int minTitleLength = 5;
  static const int maxTitleLength = 120;
  static const int minBodyLength = 10;
  static const int maxBodyLength = 2000;
  static const Duration minScheduleWindow = Duration(minutes: 5);
  static const Duration maxScheduleWindow = Duration(days: 90);

  static final RegExp _dangerousPattern = RegExp(
    r'(<\s*script|javascript\s*:|onerror\s*=|onload\s*=|<\s*iframe|<\s*object)',
    caseSensitive: false,
  );

  /// Validates creation or editing of an announcement draft.
  static ValidationResult validateDraftPayload({
    required String? title,
    required String? body,
    required String? targetAudience,
  }) {
    final errors = <String>[];
    final cleanTitle = title?.trim() ?? '';
    final cleanBody = body?.trim() ?? '';
    final cleanAudience = targetAudience?.trim() ?? '';

    if (cleanTitle.length < minTitleLength ||
        cleanTitle.length > maxTitleLength) {
      errors.add(
        'Title must be between $minTitleLength and $maxTitleLength characters (received ${cleanTitle.length}).',
      );
    }
    if (cleanBody.length < minBodyLength || cleanBody.length > maxBodyLength) {
      errors.add(
        'Body must be between $minBodyLength and $maxBodyLength characters (received ${cleanBody.length}).',
      );
    }
    if (cleanAudience.isEmpty || cleanAudience.length > 80) {
      errors.add('Target audience must be between 1 and 80 characters.');
    }
    if (_dangerousPattern.hasMatch(cleanTitle) ||
        _dangerousPattern.hasMatch(cleanBody) ||
        _dangerousPattern.hasMatch(cleanAudience)) {
      errors.add(
        'Input contains prohibited script or active HTML injection patterns.',
      );
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  /// Validates scheduling timestamps (publishAt and expiresAt).
  static ValidationResult validateScheduleWindow({
    required DateTime? publishAt,
    required DateTime? expiresAt,
  }) {
    final errors = <String>[];
    if (publishAt == null) {
      errors.add('publishAt timestamp is required for scheduling.');
    }
    if (expiresAt == null) {
      errors.add('expiresAt timestamp is required for scheduling.');
    }
    if (publishAt != null && expiresAt != null) {
      final duration = expiresAt.difference(publishAt);
      if (duration < minScheduleWindow) {
        errors.add(
          'expiresAt must be at least ${minScheduleWindow.inMinutes} minutes after publishAt.',
        );
      }
      if (duration > maxScheduleWindow) {
        errors.add(
          'Publication window cannot exceed ${maxScheduleWindow.inDays} days.',
        );
      }
    }
    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  /// Bounded workflow state machine check.
  static ValidationResult validateStateTransition({
    required AnnouncementStatus from,
    required AnnouncementStatus to,
  }) {
    final allowed = <AnnouncementStatus, Set<AnnouncementStatus>>{
      AnnouncementStatus.draft: {AnnouncementStatus.inReview},
      AnnouncementStatus.rejected: {
        AnnouncementStatus.draft,
        AnnouncementStatus.inReview,
      },
      AnnouncementStatus.inReview: {
        AnnouncementStatus.approved,
        AnnouncementStatus.rejected,
        AnnouncementStatus.draft,
      },
      AnnouncementStatus.approved: {AnnouncementStatus.scheduled},
      AnnouncementStatus.scheduled: {
        AnnouncementStatus.published,
        AnnouncementStatus.publishFailedTransient,
        AnnouncementStatus.publishFailedPermanent,
      },
      AnnouncementStatus.publishFailedTransient: {
        AnnouncementStatus.published,
        AnnouncementStatus.publishFailedTransient,
        AnnouncementStatus.publishFailedPermanent,
      },
      AnnouncementStatus.publishFailedPermanent: {
        AnnouncementStatus.scheduled,
        AnnouncementStatus.published,
        AnnouncementStatus.archived,
      },
      AnnouncementStatus.published: {AnnouncementStatus.expired},
      AnnouncementStatus.expired: {AnnouncementStatus.archived},
      AnnouncementStatus.archived: {},
    };

    final validNext = allowed[from] ?? const {};
    if (!validNext.contains(to)) {
      return ValidationResult.invalid([
        'Invalid workflow state transition from "${from.wireName}" to "${to.wireName}".',
      ]);
    }
    return const ValidationResult.valid();
  }
}

