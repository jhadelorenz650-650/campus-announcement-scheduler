/// Repository managing Announcements, Audit Logs, Snapshots, and Controlled
/// Demo Seed Data. Written in pure Dart so it works identically in the
/// Backend Server (with JSON disk persistence) and in the Flutter Web
/// Week 18 Prepared Offline Fallback mode.
library;

import 'dart:convert';
import '../../shared/models/announcement.dart';
import '../../shared/models/audit_log.dart';

abstract class StoragePersistenceAdapter {
  String? readStateJson();
  void writeStateJson(String jsonContent);
  String? readSnapshotJson();
  void writeSnapshotJson(String jsonContent);
}

class AnnouncementRepository {
  final StoragePersistenceAdapter? _persistence;
  final Map<String, Announcement> _announcements = {};
  final List<AuditLogEntry> _auditLogs = [];
  String? _inMemorySnapshotJson;
  int _idSequence = 100;
  int _auditSequence = 1000;

  AnnouncementRepository({
    StoragePersistenceAdapter? persistence,
    bool seedIfEmpty = true,
    DateTime? seedReferenceTime,
  }) : _persistence = persistence {
    final loaded = _loadFromPersistence();
    if (!loaded && seedIfEmpty) {
      seedControlledDataset(referenceTime: seedReferenceTime);
    }
  }

  bool _loadFromPersistence() {
    final raw = _persistence?.readStateJson();
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      _restoreFromJsonString(raw);
      return _announcements.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _saveToPersistence() {
    if (_persistence == null) return;
    _persistence.writeStateJson(_serializeState());
  }

  String _serializeState() {
    return const JsonEncoder.withIndent('  ').convert({
      'idSequence': _idSequence,
      'auditSequence': _auditSequence,
      'announcements': _announcements.values
          .map((a) => a.toStaffJson())
          .toList(),
      'auditLogs': _auditLogs.map((l) => l.toJson()).toList(),
    });
  }

  void _restoreFromJsonString(String rawJson) {
    final map = jsonDecode(rawJson) as Map<String, dynamic>;
    _idSequence = (map['idSequence'] as num?)?.toInt() ?? 100;
    _auditSequence = (map['auditSequence'] as num?)?.toInt() ?? 1000;
    _announcements.clear();
    final annList = (map['announcements'] as List<dynamic>?) ?? const [];
    for (final item in annList) {
      final ann = Announcement.fromJson(item as Map<String, dynamic>);
      _announcements[ann.id] = ann;
    }
    _auditLogs.clear();
    final logList = (map['auditLogs'] as List<dynamic>?) ?? const [];
    for (final item in logList) {
      _auditLogs.add(AuditLogEntry.fromJson(item as Map<String, dynamic>));
    }
  }

  String nextAnnouncementId() {
    _idSequence++;
    return 'ANN-$_idSequence';
  }

  String nextAuditId() {
    _auditSequence++;
    return 'AUD-$_auditSequence';
  }

  List<Announcement> getAllAnnouncements() {
    final list = _announcements.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Returns only currently active `published` announcements for Campus Users.
  List<Announcement> getPublishedCampusAnnouncements({DateTime? now}) {
    final ref = (now ?? DateTime.now()).toUtc();
    final list = _announcements.values.where((a) {
      if (a.status != AnnouncementStatus.published) return false;
      if (a.expiresAt != null && !a.expiresAt!.isAfter(ref)) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      final aPub = a.publishedAt ?? a.updatedAt;
      final bPub = b.publishedAt ?? b.updatedAt;
      return bPub.compareTo(aPub);
    });
    return list;
  }

  Announcement? getById(String id) => _announcements[id];

  Announcement save(Announcement announcement) {
    _announcements[announcement.id] = announcement;
    _saveToPersistence();
    return announcement;
  }

  AuditLogEntry recordAudit({
    required String correlationId,
    required String actorId,
    required String actorRole,
    required String action,
    String? announcementId,
    String? previousStatus,
    String? newStatus,
    required String outcome,
    Map<String, dynamic> details = const {},
    DateTime? timestamp,
  }) {
    final entry = AuditLogEntry(
      id: nextAuditId(),
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      correlationId: correlationId,
      actorId: actorId,
      actorRole: actorRole,
      action: action,
      announcementId: announcementId,
      previousStatus: previousStatus,
      newStatus: newStatus,
      outcome: outcome,
      details: details,
    );
    _auditLogs.insert(0, entry);
    _saveToPersistence();
    return entry;
  }

  List<AuditLogEntry> getAuditLogs({int limit = 200}) {
    if (_auditLogs.length <= limit) return List.unmodifiable(_auditLogs);
    return List.unmodifiable(_auditLogs.take(limit));
  }

  /// Week 16 Deployment & Rollback Evaluation: Creates a point-in-time snapshot.
  Map<String, dynamic> createSnapshot({DateTime? timestamp}) {
    final serialized = _serializeState();
    _inMemorySnapshotJson = serialized;
    _persistence?.writeSnapshotJson(serialized);
    return {
      'snapshotTimestamp': (timestamp ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
      'announcementCount': _announcements.length,
      'auditLogCount': _auditLogs.length,
    };
  }

  /// Week 16 Deployment & Rollback Evaluation: Restores from snapshot.
  bool restoreSnapshot() {
    final raw = _persistence?.readSnapshotJson() ?? _inMemorySnapshotJson;
    if (raw == null || raw.isEmpty) return false;
    _restoreFromJsonString(raw);
    _saveToPersistence();
    return true;
  }

  /// Seeds a deterministic, controlled dataset covering all 7 workflow states
  /// plus ready-to-run transient recovery and permanent failure scenarios
  /// for Weeks 13–18 demonstrations.
  void seedControlledDataset({DateTime? referenceTime}) {
    final now = (referenceTime ?? DateTime.now()).toUtc();
    _announcements.clear();
    _auditLogs.clear();
    _idSequence = 107;
    _auditSequence = 1000;

    final seeded = <Announcement>[
      // 1. PUBLISHED & PINNED (Visible to Campus Users immediately)
      Announcement(
        id: 'ANN-101',
        title: 'Final Examination Schedule & Campus Quiet Hours Now Active',
        body:
            'Final examination schedules for Fall/Winter Semester are finalized. Library 24-hour quiet zones begin Monday at 08:00 AM. Please bring your valid Campus ID to all exam halls.',
        category: AnnouncementCategory.academic,
        targetAudience: 'All Campus',
        pinned: true,
        status: AnnouncementStatus.published,
        authorId: 'usr-author-01',
        authorName: 'Prof. Elena Vance',
        reviewerId: 'usr-reviewer-01',
        reviewNotes: 'Verified with Registrar calendar and approved.',
        publishAt: now.subtract(const Duration(hours: 4)),
        expiresAt: now.add(const Duration(hours: 20)),
        publishedAt: now.subtract(const Duration(hours: 4)),
        createdAt: now.subtract(const Duration(hours: 12)),
        updatedAt: now.subtract(const Duration(hours: 4)),
      ),
      // 2. SCHEDULED — NORMAL PATH (Ready to publish on next scheduler tick)
      Announcement(
        id: 'ANN-102',
        title: 'Campus Shuttle Route B Winter Weather Detour Notice',
        body:
            'Due to North Gate road resurfacing, Campus Shuttle Route B will board at the Science Complex East Plaza starting today. Normal routing resumes Friday at 18:00.',
        category: AnnouncementCategory.maintenance,
        targetAudience: 'All Campus',
        pinned: false,
        status: AnnouncementStatus.scheduled,
        authorId: 'usr-author-01',
        authorName: 'Prof. Elena Vance',
        reviewerId: 'usr-reviewer-01',
        reviewNotes: 'Approved by Facilities & Transport.',
        publishAt: now.subtract(const Duration(minutes: 1)),
        expiresAt: now.add(const Duration(hours: 48)),
        simulateFailure: FailureSimulationMode.none,
        createdAt: now.subtract(const Duration(hours: 6)),
        updatedAt: now.subtract(const Duration(minutes: 30)),
      ),
      // 3. SCHEDULED — TRANSIENT FAILURE DEMO (Fails attempt 1, auto-recovers on retry)
      Announcement(
        id: 'ANN-103',
        title: 'Cybersecurity MFA Upgrade Window for Student Portal',
        body:
            'Campus IT will upgrade Multi-Factor Authentication services tonight between 01:00 and 02:00 AM. Brief 3-minute sign-in interruptions may occur during the maintenance window.',
        category: AnnouncementCategory.maintenance,
        targetAudience: 'All Campus',
        pinned: false,
        status: AnnouncementStatus.scheduled,
        authorId: 'usr-author-01',
        authorName: 'Prof. Elena Vance',
        reviewerId: 'usr-reviewer-01',
        reviewNotes: 'Approved for immediate scheduled dispatch.',
        publishAt: now.subtract(const Duration(minutes: 2)),
        expiresAt: now.add(const Duration(hours: 24)),
        simulateFailure: FailureSimulationMode.transientOnce,
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(minutes: 20)),
      ),
      // 4. SCHEDULED — PERMANENT FAILURE DEMO (Routes to Human Action Queue)
      Announcement(
        id: 'ANN-104',
        title: 'Emergency Severed Fiber Line — West Engineering Annex',
        body:
            'Network connectivity in West Engineering Annex is temporarily degraded due to municipal utility work. Cellular Wi-Fi backup hotspots have been deployed on Floors 1–3.',
        category: AnnouncementCategory.emergency,
        targetAudience: 'Engineering Faculty & Students',
        pinned: true,
        status: AnnouncementStatus.scheduled,
        authorId: 'usr-author-01',
        authorName: 'Prof. Elena Vance',
        reviewerId: 'usr-reviewer-01',
        reviewNotes: 'Urgent emergency alert approved.',
        publishAt: now.subtract(const Duration(minutes: 3)),
        expiresAt: now.add(const Duration(hours: 12)),
        simulateFailure: FailureSimulationMode.permanentFailure,
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(minutes: 15)),
      ),
      // 5. APPROVED (Ready for Publisher to Schedule or test Conflict Check)
      Announcement(
        id: 'ANN-105',
        title: 'Annual Undergraduate Research Symposium Registration Open',
        body:
            'Abstract submissions for the Spring Undergraduate Research Symposium are now open through the Academic Portal. Faculty mentorship sign-ups close on the 15th.',
        category: AnnouncementCategory.events,
        targetAudience: 'All Campus',
        pinned: false,
        status: AnnouncementStatus.approved,
        authorId: 'usr-author-01',
        authorName: 'Prof. Elena Vance',
        reviewerId: 'usr-reviewer-01',
        reviewNotes: 'Content is accurate and ready for scheduling.',
        createdAt: now.subtract(const Duration(hours: 8)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      ),
      // 6. IN REVIEW (Ready for Reviewer to Approve or Reject)
      Announcement(
        id: 'ANN-106',
        title: 'Health Center Flu & Booster Vaccination Clinic Hours',
        body:
            'Walk-in flu vaccinations are available free of charge for all students and staff at the Wellness Center Monday through Friday from 09:00 AM to 04:00 PM.',
        category: AnnouncementCategory.general,
        targetAudience: 'All Campus',
        pinned: false,
        status: AnnouncementStatus.inReview,
        authorId: 'usr-author-01',
        authorName: 'Prof. Elena Vance',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
      // 7. DRAFT (Ready for Author to Edit & Submit)
      Announcement(
        id: 'ANN-107',
        title: 'Graduate Thesis Formatting Workshop — Main Auditorium',
        body:
            'Join the Graduate School editorial team for a hands-on workshop covering LaTeX and Word thesis templates, citation standards, and submission deadlines.',
        category: AnnouncementCategory.academic,
        targetAudience: 'Graduate Students',
        pinned: false,
        status: AnnouncementStatus.draft,
        authorId: 'usr-author-01',
        authorName: 'Prof. Elena Vance',
        createdAt: now.subtract(const Duration(minutes: 45)),
        updatedAt: now.subtract(const Duration(minutes: 45)),
      ),
    ];

    for (final a in seeded) {
      _announcements[a.id] = a;
    }

    recordAudit(
      correlationId: 'corr-seed-init',
      actorId: 'system-seeder',
      actorRole: 'system',
      action: 'SEED_CONTROLLED_DATASET',
      announcementId: 'ANN-101',
      previousStatus: 'scheduled',
      newStatus: 'published',
      outcome: 'SUCCESS',
      timestamp: now.subtract(const Duration(hours: 4)),
      details: {
        'seededCount': seeded.length,
        'note':
            'Initialized bounded workflow dataset across Draft, InReview, Approved, Scheduled (Normal, Transient, Permanent), and Published states.',
      },
    );

    createSnapshot(timestamp: now);
  }
}

