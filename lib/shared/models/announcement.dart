/// Shared domain models for Project 26: Campus Announcement Scheduler.
/// Covers bounded workflow states, roles, failure simulation modes, and
/// data-minimized projections (Week 13 SA7 & Week 14 SA8/IA5).
library;

enum AnnouncementStatus {
  draft('draft', 'Draft'),
  inReview('in_review', 'In Review'),
  rejected('rejected', 'Changes Requested'),
  approved('approved', 'Approved'),
  scheduled('scheduled', 'Scheduled'),
  publishFailedTransient('publish_failed_transient', 'Retry Pending (Transient)'),
  publishFailedPermanent('publish_failed_permanent', 'Action Required (Permanent Failure)'),
  published('published', 'Published'),
  expired('expired', 'Expired'),
  archived('archived', 'Archived');

  final String wireName;
  final String label;
  const AnnouncementStatus(this.wireName, this.label);

  static AnnouncementStatus fromWire(String value) {
    return AnnouncementStatus.values.firstWhere(
      (e) => e.wireName == value || e.name == value,
      orElse: () => AnnouncementStatus.draft,
    );
  }
}

enum UserRole {
  author('author', 'Content Author'),
  reviewer('reviewer', 'Reviewer'),
  publisher('publisher', 'Publisher'),
  campusUser('campus_user', 'Campus User');

  final String wireName;
  final String label;
  const UserRole(this.wireName, this.label);

  static UserRole fromWire(String value) {
    return UserRole.values.firstWhere(
      (e) => e.wireName == value || e.name == value,
      orElse: () => UserRole.campusUser,
    );
  }
}

enum AnnouncementCategory {
  academic('academic', 'Academic'),
  emergency('emergency', 'Emergency Alert'),
  events('events', 'Campus Events'),
  maintenance('maintenance', 'IT & Facilities'),
  general('general', 'General Notice');

  final String wireName;
  final String label;
  const AnnouncementCategory(this.wireName, this.label);

  static AnnouncementCategory fromWire(String value) {
    return AnnouncementCategory.values.firstWhere(
      (e) => e.wireName == value || e.name == value,
      orElse: () => AnnouncementCategory.general,
    );
  }
}

enum FailureSimulationMode {
  none('none', 'Normal Delivery (Healthy)'),
  transientOnce('transient_once', 'Simulate Transient Outage (Auto-Recovers on Retry)'),
  permanentFailure('permanent_failure', 'Simulate Permanent Failure (Routes to Human Action)');

  final String wireName;
  final String label;
  const FailureSimulationMode(this.wireName, this.label);

  static FailureSimulationMode fromWire(String? value) {
    if (value == null) return FailureSimulationMode.none;
    return FailureSimulationMode.values.firstWhere(
      (e) => e.wireName == value || e.name == value,
      orElse: () => FailureSimulationMode.none,
    );
  }
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final AnnouncementCategory category;
  final String targetAudience;
  final bool pinned;
  final AnnouncementStatus status;
  final String authorId;
  final String authorName;
  final String? reviewerId;
  final String? reviewNotes;
  final DateTime? publishAt;
  final DateTime? expiresAt;
  final DateTime? publishedAt;
  final DateTime? expiredAt;
  final DateTime? archivedAt;
  final DateTime? nextRetryAt;
  final int retryCount;
  final String? lastError;
  final FailureSimulationMode simulateFailure;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.targetAudience,
    this.pinned = false,
    required this.status,
    required this.authorId,
    required this.authorName,
    this.reviewerId,
    this.reviewNotes,
    this.publishAt,
    this.expiresAt,
    this.publishedAt,
    this.expiredAt,
    this.archivedAt,
    this.nextRetryAt,
    this.retryCount = 0,
    this.lastError,
    this.simulateFailure = FailureSimulationMode.none,
    required this.createdAt,
    required this.updatedAt,
  });

  Announcement copyWith({
    String? title,
    String? body,
    AnnouncementCategory? category,
    String? targetAudience,
    bool? pinned,
    AnnouncementStatus? status,
    String? reviewerId,
    String? reviewNotes,
    DateTime? publishAt,
    DateTime? expiresAt,
    DateTime? publishedAt,
    DateTime? expiredAt,
    DateTime? archivedAt,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    int? retryCount,
    String? lastError,
    bool clearLastError = false,
    FailureSimulationMode? simulateFailure,
    DateTime? updatedAt,
  }) {
    return Announcement(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      category: category ?? this.category,
      targetAudience: targetAudience ?? this.targetAudience,
      pinned: pinned ?? this.pinned,
      status: status ?? this.status,
      authorId: authorId,
      authorName: authorName,
      reviewerId: reviewerId ?? this.reviewerId,
      reviewNotes: reviewNotes ?? this.reviewNotes,
      publishAt: publishAt ?? this.publishAt,
      expiresAt: expiresAt ?? this.expiresAt,
      publishedAt: publishedAt ?? this.publishedAt,
      expiredAt: expiredAt ?? this.expiredAt,
      archivedAt: archivedAt ?? this.archivedAt,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      retryCount: retryCount ?? this.retryCount,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      simulateFailure: simulateFailure ?? this.simulateFailure,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Full serialization for authorized staff roles (Author, Reviewer, Publisher).
  Map<String, dynamic> toStaffJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'category': category.wireName,
      'targetAudience': targetAudience,
      'pinned': pinned,
      'status': status.wireName,
      'authorId': authorId,
      'authorName': authorName,
      'reviewerId': reviewerId,
      'reviewNotes': reviewNotes,
      'publishAt': publishAt?.toUtc().toIso8601String(),
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
      'publishedAt': publishedAt?.toUtc().toIso8601String(),
      'expiredAt': expiredAt?.toUtc().toIso8601String(),
      'archivedAt': archivedAt?.toUtc().toIso8601String(),
      'nextRetryAt': nextRetryAt?.toUtc().toIso8601String(),
      'retryCount': retryCount,
      'lastError': lastError,
      'simulateFailure': simulateFailure.wireName,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Week 14 Data Minimization (SA8/IA5):
  /// Campus Users only receive public fields of active published announcements.
  /// Internal workflow metadata (authorId, reviewerId, reviewNotes, retryCount,
  /// lastError, simulateFailure) is strictly omitted.
  Map<String, dynamic> toMinimizedCampusJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'category': category.wireName,
      'targetAudience': targetAudience,
      'pinned': pinned,
      'status': status.wireName,
      'publishedAt': publishedAt?.toUtc().toIso8601String(),
      'expiresAt': expiresAt?.toUtc().toIso8601String(),
    };
  }

  factory Announcement.fromJson(Map<String, dynamic> json) {
    DateTime? parseOptDate(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.parse(v).toUtc() : null;

    final now = DateTime.now().toUtc();
    return Announcement(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      category: AnnouncementCategory.fromWire(
        (json['category'] as String?) ?? 'general',
      ),
      targetAudience: (json['targetAudience'] as String?) ?? 'All Campus',
      pinned: (json['pinned'] as bool?) ?? false,
      status: AnnouncementStatus.fromWire(
        (json['status'] as String?) ?? 'draft',
      ),
      authorId: (json['authorId'] as String?) ?? 'public-redacted',
      authorName: (json['authorName'] as String?) ?? 'Campus Communications',
      reviewerId: json['reviewerId'] as String?,
      reviewNotes: json['reviewNotes'] as String?,
      publishAt: parseOptDate(json['publishAt']),
      expiresAt: parseOptDate(json['expiresAt']),
      publishedAt: parseOptDate(json['publishedAt']),
      expiredAt: parseOptDate(json['expiredAt']),
      archivedAt: parseOptDate(json['archivedAt']),
      nextRetryAt: parseOptDate(json['nextRetryAt']),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      simulateFailure: FailureSimulationMode.fromWire(
        json['simulateFailure'] as String?,
      ),
      createdAt: parseOptDate(json['createdAt']) ?? now,
      updatedAt: parseOptDate(json['updatedAt']) ?? now,
    );
  }
}

