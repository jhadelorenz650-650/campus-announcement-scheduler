/// Responsive Flutter Web UI for Project 26: Campus Announcement Scheduler.
/// Provides 5 integrated workspaces covering Weeks 13–18 requirements:
/// 1. Bounded Workflow Pipeline (Draft -> Review -> Approve -> Schedule -> Publish -> Expire -> Archive)
/// 2. Week 13 Automation, Retry & Human Escalation Console
/// 3. Campus Feed & Week 14 Data Minimization Inspector
/// 4. Week 14/15 Security & Negative-Path Verification Lab
/// 5. Structured Audit Logs, Week 16 Health/Telemetry & Snapshot Rollback Console
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/announcement.dart';
import '../state/app_state.dart';

class DashboardScreen extends StatefulWidget {
  final AppState appState;

  const DashboardScreen({super.key, required this.appState});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTabIndex = 0;
  String _statusFilter = 'ALL';

  AppState get state => widget.appState;

  @override
  void initState() {
    super.initState();
    state.addListener(_onStateChanged);
    _initWithQueryParameters();
  }

  Future<void> _initWithQueryParameters() async {
    final params = Uri.base.queryParameters;
    if (params.isEmpty) {
      await state.initialize();
      return;
    }
    await state.resetControlledDemo();

    final tabParam = int.tryParse(params['tab'] ?? '');
    if (tabParam != null && tabParam >= 0 && tabParam <= 4) {
      _selectedTabIndex = tabParam;
    }
    if (params['filter'] != null) {
      _statusFilter = params['filter']!;
    }

    final tickParam = int.tryParse(params['tick'] ?? '0') ?? 0;
    for (int i = 0; i < tickParam; i++) {
      await state.runSchedulerTick(advanceSeconds: i * 10);
    }

    if (params['recover'] == '1') {
      await state.recoverPermanentFailure(
        id: 'ANN-104',
        resolutionNote:
            'Reconfigured emergency broadcast endpoint schema and verified delivery.',
        publishImmediately: true,
      );
    }

    if (params['expire'] == '1') {
      await state.runSchedulerTick(advanceMinutes: 1500);
    }

    if (params['role'] != null) {
      await state.switchRole(UserRole.fromWire(params['role']!));
    }

    if (params['probe'] != null) {
      await state.executeSecurityProbe(params['probe']!);
    }

    if (!mounted) return;
    setState(() {});

    final dialog = params['dialog'];
    if (dialog != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (dialog) {
          case 'create':
            _showCreateDraftDialog();
            break;
          case 'schedule':
            final ann = state.announcements.firstWhere(
              (a) => a.id == 'ANN-105',
              orElse: () => state.announcements.first,
            );
            _showScheduleDialog(ann);
            break;
          case 'recover':
            final ann = state.announcements.firstWhere(
              (a) => a.id == 'ANN-104',
              orElse: () => state.announcements.first,
            );
            _showHumanRecoveryDialog(ann);
            break;
          case 'reject':
            final ann = state.announcements.firstWhere(
              (a) => a.id == 'ANN-106',
              orElse: () => state.announcements.first,
            );
            _showRejectDialog(ann);
            break;
        }
      });
    }
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${DateFormat('yyyy-MM-dd HH:mm').format(dt.toUtc())} UTC';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        return Scaffold(
          backgroundColor: const Color(0xFFF4F6FA),
          appBar: _buildTopAppBar(isWide),
          body: Column(
            children: [
              _buildRoleAndClockBar(isWide),
              if (state.bannerMessage != null) _buildFeedbackBanner(),
              _buildNavigationBar(isWide),
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: [
                    _buildWorkflowTab(isWide),
                    _buildAutomationTab(isWide),
                    _buildCampusFeedTab(isWide),
                    _buildSecurityLabTab(isWide),
                    _buildAuditAndTelemetryTab(isWide),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildTopAppBar(bool isWide) {
    final fallbackActive = state.apiClient.forcePreparedFallback;
    return AppBar(
      backgroundColor: const Color(0xFF0F2942),
      foregroundColor: Colors.white,
      elevation: 2,
      title: Row(
        children: [
          const Icon(Icons.campaign_rounded, color: Color(0xFF4FC3F7)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              isWide
                  ? 'Campus Announcement Scheduler — Project 26'
                  : 'Campus Scheduler (P26)',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
        ],
      ),
      actions: [
        Tooltip(
          message:
              'Toggle between Live HTTP Backend API and Week 18 Prepared Controlled Fallback',
          child: InkWell(
            onTap: () => state.togglePreparedFallbackMode(
              !state.apiClient.forcePreparedFallback,
            ),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: fallbackActive
                    ? const Color(0xFFE65100)
                    : const Color(0xFF1B5E20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    fallbackActive ? Icons.shield_outlined : Icons.cloud_done,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    fallbackActive
                        ? 'Prepared Fallback Active'
                        : 'Live API Connected',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: state.resetControlledDemo,
          icon: const Icon(Icons.restart_alt, color: Colors.white, size: 18),
          label: const Text(
            'Reset Demo Data',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildRoleAndClockBar(bool isWide) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Active Role (RBAC):',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF1E293B),
                ),
              ),
              for (final role in UserRole.values)
                ChoiceChip(
                  key: Key('role_chip_${role.wireName}'),
                  label: Text(role.label),
                  selected:
                      state.currentRole == role &&
                      state.activeTokenMode == 'valid',
                  selectedColor: const Color(0xFF0284C7),
                  labelStyle: TextStyle(
                    color:
                        state.currentRole == role &&
                            state.activeTokenMode == 'valid'
                        ? Colors.white
                        : const Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  onSelected: (_) => state.switchRole(role),
                ),
            ],
          ),
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 15,
                      color: Color(0xFF0F172A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Virtual Clock: ${_formatDate(state.virtualTime)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.currentRole == UserRole.publisher)
                FilledButton.tonalIcon(
                  key: const Key('quick_tick_button'),
                  onPressed: () => state.runSchedulerTick(),
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text(
                    'Run Scheduler Tick',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackBanner() {
    final isErr = state.bannerIsError;
    return Container(
      key: const Key('feedback_banner'),
      width: double.infinity,
      color: isErr ? const Color(0xFFFEE2E2) : const Color(0xFFE0F2FE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            isErr ? Icons.error_outline : Icons.info_outline,
            color: isErr ? const Color(0xFFB91C1C) : const Color(0xFF0369A1),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.bannerMessage ?? '',
              style: TextStyle(
                color: isErr
                    ? const Color(0xFF7F1D1D)
                    : const Color(0xFF0C4A6E),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: state.clearBanner,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar(bool isWide) {
    final escalatedCount = state.escalatedFailures.length;
    final tabs = [
      (icon: Icons.view_kanban_outlined, label: '1. Workflow Pipeline'),
      (
        icon: Icons.bolt_outlined,
        label: escalatedCount > 0
            ? '2. Automation & Recovery ($escalatedCount Action Needed)'
            : '2. Automation & Recovery (SA7)',
      ),
      (icon: Icons.public_outlined, label: '3. Campus Feed & Privacy'),
      (icon: Icons.security_outlined, label: '4. Security & Negative Lab'),
      (icon: Icons.receipt_long_outlined, label: '5. Audit, Health & Rollback'),
    ];

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
        border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final selected = _selectedTabIndex == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('nav_tab_$i'),
                avatar: Icon(
                  tabs[i].icon,
                  size: 16,
                  color: selected ? Colors.white : const Color(0xFF334155),
                ),
                label: Text(tabs[i].label),
                selected: selected,
                selectedColor: const Color(0xFF0F2942),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF1E293B),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
                onSelected: (_) => setState(() => _selectedTabIndex = i),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ==========================================================================
  // TAB 1: Bounded Workflow Pipeline
  // ==========================================================================
  Widget _buildWorkflowTab(bool isWide) {
    final stages = [
      ('ALL', 'All (${state.announcements.length})'),
      ('draft', 'Draft'),
      ('in_review', 'In Review'),
      ('approved', 'Approved'),
      ('scheduled', 'Scheduled'),
      ('failures', 'Failed / Retry'),
      ('published', 'Published'),
      ('expired_archived', 'Expired / Archived'),
    ];

    final filtered = state.announcements.where((a) {
      if (_statusFilter == 'ALL') return true;
      if (_statusFilter == 'failures') {
        return a.status == AnnouncementStatus.publishFailedTransient ||
            a.status == AnnouncementStatus.publishFailedPermanent ||
            a.status == AnnouncementStatus.rejected;
      }
      if (_statusFilter == 'expired_archived') {
        return a.status == AnnouncementStatus.expired ||
            a.status == AnnouncementStatus.archived;
      }
      return a.status.wireName == _statusFilter;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in stages)
                      FilterChip(
                        label: Text(
                          s.$2,
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _statusFilter == s.$1,
                        onSelected: (_) =>
                            setState(() => _statusFilter = s.$1),
                      ),
                  ],
                ),
                FilledButton.icon(
                  key: const Key('create_draft_button'),
                  onPressed: () => _showCreateDraftDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Draft Announcement'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No announcements match the selected stage filter.'),
              ),
            ),
          )
        else
          ...filtered.map(_buildAnnouncementCard),
      ],
    );
  }

  Widget _buildAnnouncementCard(Announcement ann) {
    final statusColor = _statusColor(ann.status);
    return Card(
      key: Key('announcement_card_${ann.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: ann.status == AnnouncementStatus.publishFailedPermanent
              ? const Color(0xFFDC2626)
              : const Color(0xFFCBD5E1),
          width: ann.status == AnnouncementStatus.publishFailedPermanent
              ? 1.8
              : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    '${ann.id} • ${ann.status.label}',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    ann.category.label,
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const Icon(Icons.groups_outlined, size: 14),
                  label: Text(
                    ann.targetAudience,
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (ann.pinned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD97706)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 13,
                          color: Color(0xFFB45309),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'PINNED SLOT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (ann.simulateFailure != FailureSimulationMode.none)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'SimMode: ${ann.simulateFailure.label}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B21A8),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              ann.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ann.body,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (!state.isDataMinimizedView)
                  Text(
                    'Author: ${ann.authorName}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                if (ann.publishAt != null)
                  Text(
                    'Publish At: ${_formatDate(ann.publishAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (ann.expiresAt != null)
                  Text(
                    'Expires At: ${_formatDate(ann.expiresAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (ann.retryCount > 0)
                  Text(
                    'Retry Attempts: ${ann.retryCount}/3',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            if (ann.reviewNotes != null && ann.reviewNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  'Reviewer Note: ${ann.reviewNotes}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
            if (ann.lastError != null && ann.lastError!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF87171)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFB91C1C),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ann.lastError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7F1D1D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildWorkflowActionButtons(ann),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkflowActionButtons(Announcement ann) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (ann.status == AnnouncementStatus.draft ||
            ann.status == AnnouncementStatus.rejected)
          FilledButton.icon(
            key: Key('submit_btn_${ann.id}'),
            onPressed: () => state.submitForReview(ann.id),
            icon: const Icon(Icons.send_outlined, size: 16),
            label: const Text('Submit for Review (Author)'),
          ),
        if (ann.status == AnnouncementStatus.inReview) ...[
          FilledButton.icon(
            key: Key('approve_btn_${ann.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
            ),
            onPressed: () => state.reviewAnnouncement(
              id: ann.id,
              approve: true,
              reviewNotes: 'Approved after policy & accuracy verification.',
            ),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Approve (Reviewer)'),
          ),
          OutlinedButton.icon(
            key: Key('reject_btn_${ann.id}'),
            onPressed: () => _showRejectDialog(ann),
            icon: const Icon(Icons.reply_outlined, size: 16),
            label: const Text('Request Changes (Reviewer)'),
          ),
        ],
        if (ann.status == AnnouncementStatus.approved)
          FilledButton.icon(
            key: Key('schedule_btn_${ann.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0369A1),
            ),
            onPressed: () => _showScheduleDialog(ann),
            icon: const Icon(Icons.calendar_month_outlined, size: 16),
            label: const Text('Schedule Publication (Publisher)'),
          ),
        if (ann.status == AnnouncementStatus.scheduled ||
            ann.status == AnnouncementStatus.publishFailedTransient)
          FilledButton.tonalIcon(
            key: Key('tick_item_btn_${ann.id}'),
            onPressed: () => state.runSchedulerTick(),
            icon: const Icon(Icons.bolt, size: 16),
            label: Text(
              ann.status == AnnouncementStatus.publishFailedTransient
                  ? 'Execute Retry Tick Now'
                  : 'Run Scheduler Tick to Publish',
            ),
          ),
        if (ann.status == AnnouncementStatus.publishFailedPermanent)
          FilledButton.icon(
            key: Key('recover_btn_${ann.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => _showHumanRecoveryDialog(ann),
            icon: const Icon(Icons.build_circle_outlined, size: 16),
            label: const Text('Human Action: Resolve & Recover (Publisher)'),
          ),
        if (ann.status == AnnouncementStatus.published)
          OutlinedButton.icon(
            key: Key('fast_forward_expire_btn_${ann.id}'),
            onPressed: () => state.runSchedulerTick(advanceMinutes: 1500),
            icon: const Icon(Icons.fast_forward, size: 16),
            label: const Text('Fast-Forward Clock +25h to Auto-Expire'),
          ),
        if (ann.status == AnnouncementStatus.expired)
          FilledButton.tonalIcon(
            key: Key('archive_btn_${ann.id}'),
            onPressed: () => state.archiveAnnouncement(ann.id),
            icon: const Icon(Icons.inventory_2_outlined, size: 16),
            label: const Text('Archive Announcement (Publisher)'),
          ),
      ],
    );
  }

  // ==========================================================================
  // TAB 2: Week 13 Automation, Retry & Human Escalation Console (SA7)
  // ==========================================================================
  Widget _buildAutomationTab(bool isWide) {
    final escalated = state.escalatedFailures;
    final transient = state.transientRetries;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Week 13 Automation Foundation (SA7) — Scheduler & Virtual Clock Controls',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Trigger scheduled publication, observe transient failure exponential backoff retry (ANN-103), inspect permanent failure escalation to human action (ANN-104), and advance the virtual clock to verify automatic expiration.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      key: const Key('automation_tick_now_btn'),
                      onPressed: () => state.runSchedulerTick(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('1. Run Scheduler Tick Now'),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('automation_tick_15m_btn'),
                      onPressed: () =>
                          state.runSchedulerTick(advanceMinutes: 15),
                      icon: const Icon(Icons.update),
                      label: const Text('2. Advance +15m & Run Retry Tick'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('automation_tick_25h_btn'),
                      onPressed: () =>
                          state.runSchedulerTick(advanceMinutes: 1500),
                      icon: const Icon(Icons.timer_off_outlined),
                      label: const Text(
                        '3. Advance +25h (Trigger Auto-Expiration)',
                      ),
                    ),
                  ],
                ),
                if (state.lastTickReport != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Text(
                      'Last Tick Telemetry: ${const JsonEncoder.withIndent('  ').convert(state.lastTickReport)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Permanent Failures Routed for Human Action (${escalated.length})',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFFB91C1C),
          ),
        ),
        const SizedBox(height: 8),
        if (escalated.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No permanent failures currently in the escalation queue. Click "1. Run Scheduler Tick Now" on the seeded dataset to see ANN-104 route here.',
              ),
            ),
          )
        else
          ...escalated.map(_buildAnnouncementCard),
        const SizedBox(height: 16),
        Text(
          'Transient Failures Pending Automatic Retry (${transient.length})',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFFB45309),
          ),
        ),
        const SizedBox(height: 8),
        if (transient.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No announcements awaiting transient retry. Click "1. Run Scheduler Tick Now" to see ANN-103 fail once, then click it a second time to see it automatically recover and publish.',
              ),
            ),
          )
        else
          ...transient.map(_buildAnnouncementCard),
      ],
    );
  }

  // ==========================================================================
  // TAB 3: Campus User Feed & Data Minimization Inspector (Week 14)
  // ==========================================================================
  Widget _buildCampusFeedTab(bool isWide) {
    final publishedOnly = state.announcements
        .where((a) => a.status == AnnouncementStatus.published)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: const Color(0xFFE0F2FE),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF7DD3FC)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: Color(0xFF0369A1)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.currentRole == UserRole.campusUser
                        ? 'Viewing as Campus User: Strict Data Minimization is ACTIVE. Unpublished drafts, internal reviewer notes, author IDs, and failure diagnostics are stripped by the backend API.'
                        : 'Tip: Switch to "Campus User" in the top bar to verify that the API only returns active published announcements with minimized JSON fields.',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0C4A6E),
                    ),
                  ),
                ),
                if (state.currentRole != UserRole.campusUser)
                  FilledButton.tonal(
                    onPressed: () => state.switchRole(UserRole.campusUser),
                    child: const Text('Switch to Campus User'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (publishedOnly.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No active published campus announcements.'),
              ),
            ),
          )
        else
          ...publishedOnly.map((ann) {
            final minimizedJson = const JsonEncoder.withIndent(
              '  ',
            ).convert(ann.toMinimizedCampusJson());
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (ann.pinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.push_pin,
                              size: 16,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            ann.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Chip(label: Text(ann.category.label)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(ann.body),
                    const SizedBox(height: 8),
                    Text(
                      'Published: ${_formatDate(ann.publishedAt)}  •  Automatic Expiration: ${_formatDate(ann.expiresAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Inspect Minimized JSON DTO (Week 14 IA5 Data Minimization Evidence)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0369A1),
                        ),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            minimizedJson,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ==========================================================================
  // TAB 4: Security & Negative-Path Verification Lab (Weeks 14 & 15)
  // ==========================================================================
  Widget _buildSecurityLabTab(bool isWide) {
    final probes = [
      (
        id: 'tampered_token',
        title: '1. Altered / Forged HMAC Signature',
        subtitle:
            'Sends a bearer token whose payload was modified to escalate role without the server HMAC key (Expect HTTP 401 AUTH_INVALID_SIGNATURE).',
        icon: Icons.gpp_bad_outlined,
      ),
      (
        id: 'expired_token',
        title: '2. Expired Session Token',
        subtitle:
            'Sends a cryptographically valid token whose exp claim is in the past (Expect HTTP 401 AUTH_TOKEN_EXPIRED).',
        icon: Icons.history_toggle_off,
      ),
      (
        id: 'unauthorized_role',
        title: '3. Unauthorized Role Violation (RBAC)',
        subtitle:
            'Authenticates as Content Author and attempts to invoke Publisher-only /schedule endpoint (Expect HTTP 403 RBAC_FORBIDDEN).',
        icon: Icons.lock_person_outlined,
      ),
      (
        id: 'xss_injection',
        title: '4. Script / XSS Injection Payload',
        subtitle:
            'Submits <script> and javascript: URI payload to draft creation endpoint (Expect HTTP 400 VALIDATION_ERROR).',
        icon: Icons.code_off,
      ),
      (
        id: 'schedule_conflict',
        title: '5. Pinned Channel Slot Schedule Conflict',
        subtitle:
            'Attempts to schedule a second Pinned Academic announcement overlapping ANN-101 (Expect HTTP 409 SCHEDULE_CONFLICT).',
        icon: Icons.event_busy_outlined,
      ),
      (
        id: 'illegal_state',
        title: '6. Illegal Workflow State Jump',
        subtitle:
            'Attempts to schedule unapproved draft ANN-107 bypassing Reviewer approval (Expect HTTP 400 INVALID_STATE_TRANSITION).',
        icon: Icons.rule_folder_outlined,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Week 14 Secure Integration (SA8/IA5) & Week 15 Hardening (IA6) — Live Negative-Path Lab',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Execute deterministic security, boundary, conflict, and state-machine negative paths against the backend API and inspect the resulting HTTP status and audit trail.',
          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: probes.map((p) {
            return SizedBox(
              width: isWide ? 380 : double.infinity,
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(p.icon, color: const Color(0xFF0F2942)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          key: Key('probe_btn_${p.id}'),
                          onPressed: () => state.executeSecurityProbe(p.id),
                          icon: const Icon(Icons.science_outlined, size: 16),
                          label: const Text('Execute Probe'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'Executed Probe Evidence Log',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (state.probeHistory.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Click any "Execute Probe" button above to capture live negative-path response evidence.',
              ),
            ),
          )
        else
          ...state.probeHistory.map((res) {
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'HTTP ${res.statusCode} • ${res.errorCode}',
                            style: const TextStyle(
                              color: Color(0xFFB91C1C),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            res.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      res.message,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(res.rawResponse),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ==========================================================================
  // TAB 5: Structured Audit Logs, Health Telemetry & Snapshot Rollback
  // ==========================================================================
  Widget _buildAuditAndTelemetryTab(bool isWide) {
    final httpMetrics =
        state.metricsData['http'] as Map<String, dynamic>? ?? const {};
    final latency =
        httpMetrics['latencyMs'] as Map<String, dynamic>? ?? const {};
    final secMetrics =
        state.metricsData['security'] as Map<String, dynamic>? ?? const {};
    final autoMetrics =
        state.metricsData['automation'] as Map<String, dynamic>? ?? const {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Week 16 Health, Telemetry & Rollback Recovery Console',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('create_snapshot_btn'),
                          onPressed: state.createSnapshot,
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: const Text('Create Snapshot'),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('restore_snapshot_btn'),
                          onPressed: state.restoreSnapshot,
                          icon: const Icon(Icons.restore, size: 16),
                          label: const Text('Rollback to Snapshot'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _metricTile(
                      'Health Status',
                      '${state.healthData['status'] ?? 'HEALTHY'}',
                    ),
                    _metricTile(
                      'Total Requests',
                      '${httpMetrics['totalRequests'] ?? 0}',
                    ),
                    _metricTile(
                      'Latency p50 / p95',
                      '${latency['p50'] ?? 0}ms / ${latency['p95'] ?? 0}ms',
                    ),
                    _metricTile(
                      'Auth / RBAC Rejections',
                      '${secMetrics['authFailureCount'] ?? 0} / ${secMetrics['rbacDeniedCount'] ?? 0}',
                    ),
                    _metricTile(
                      'Published / Expired',
                      '${autoMetrics['publishedTotal'] ?? 0} / ${autoMetrics['autoExpirationsTotal'] ?? 0}',
                    ),
                    _metricTile(
                      'Transient Recovered / Escalated',
                      '${autoMetrics['transientRecoveriesTotal'] ?? 0} / ${autoMetrics['permanentEscalationsTotal'] ?? 0}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Structured JSON Audit Trail (Safe Logging Redaction Verified)',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (state.currentRole != UserRole.publisher &&
            state.currentRole != UserRole.reviewer)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Audit logs are restricted to Reviewer and Publisher roles (RBAC Least Privilege). Switch to Publisher or Reviewer to inspect structured logs.',
              ),
            ),
          )
        else
          ...state.auditLogs.take(40).map((log) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        Text(
                          '${log.id} • ${log.action}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '[${log.outcome}]',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: log.outcome == 'SUCCESS'
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB91C1C),
                          ),
                        ),
                        Text(
                          'Actor: ${log.actorId} (${log.actorRole}) • CorrID: ${log.correlationId}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    if (log.previousStatus != null || log.newStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Announcement: ${log.announcementId ?? "—"}  |  Transition: ${log.previousStatus ?? "none"} → ${log.newStatus ?? "none"}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    SelectableText(
                      jsonEncode(log.details),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _metricTile(String label, String value) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(AnnouncementStatus s) {
    switch (s) {
      case AnnouncementStatus.draft:
        return const Color(0xFF475569);
      case AnnouncementStatus.inReview:
        return const Color(0xFF0284C7);
      case AnnouncementStatus.rejected:
        return const Color(0xFFD97706);
      case AnnouncementStatus.approved:
        return const Color(0xFF0D9488);
      case AnnouncementStatus.scheduled:
        return const Color(0xFF4F46E5);
      case AnnouncementStatus.publishFailedTransient:
        return const Color(0xFFD97706);
      case AnnouncementStatus.publishFailedPermanent:
        return const Color(0xFFDC2626);
      case AnnouncementStatus.published:
        return const Color(0xFF15803D);
      case AnnouncementStatus.expired:
        return const Color(0xFF64748B);
      case AnnouncementStatus.archived:
        return const Color(0xFF334155);
    }
  }

  // ==========================================================================
  // Interactive Modal Dialogs (Create Draft, Reject, Schedule, Recover)
  // ==========================================================================

  Future<void> _showCreateDraftDialog() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final audienceCtrl = TextEditingController(text: 'All Campus');
    var category = AnnouncementCategory.academic;
    var pinned = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Create Announcement Draft'),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        key: const Key('draft_title_input'),
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Title (5–120 chars)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('draft_body_input'),
                        controller: bodyCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Announcement Body (10–2000 chars)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AnnouncementCategory>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: AnnouncementCategory.values
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => category = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: audienceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Target Audience',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Request Pinned Channel Slot'),
                        value: pinned,
                        onChanged: (v) => setDialogState(() => pinned = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('save_draft_submit_btn'),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await state.createDraft(
                      title: titleCtrl.text,
                      body: bodyCtrl.text,
                      category: category,
                      targetAudience: audienceCtrl.text,
                      pinned: pinned,
                    );
                  },
                  child: const Text('Save Draft'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRejectDialog(Announcement ann) async {
    final notesCtrl = TextEditingController(
      text: 'Please clarify the building room numbers and effective dates.',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Request Changes for ${ann.id}'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Required Reviewer Feedback',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await state.reviewAnnouncement(
                id: ann.id,
                approve: false,
                reviewNotes: notesCtrl.text,
              );
            },
            child: const Text('Return to Author'),
          ),
        ],
      ),
    );
  }

  Future<void> _showScheduleDialog(Announcement ann) async {
    var pinned = ann.pinned;
    var simMode = FailureSimulationMode.none;
    var windowHours = 24;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Schedule ${ann.id} for Publication'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ann.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: windowHours,
                    decoration: const InputDecoration(
                      labelText: 'Publication Duration Before Auto-Expiry',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 6, child: Text('6 Hours')),
                      DropdownMenuItem(value: 24, child: Text('24 Hours')),
                      DropdownMenuItem(value: 72, child: Text('72 Hours')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => windowHours = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<FailureSimulationMode>(
                    initialValue: simMode,
                    decoration: const InputDecoration(
                      labelText: 'Week 13 Delivery / Fault Simulation Mode',
                      border: OutlineInputBorder(),
                    ),
                    items: FailureSimulationMode.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => simMode = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text(
                      'Pinned Slot (Enforces Channel Conflict Check)',
                    ),
                    value: pinned,
                    onChanged: (v) => setDialogState(() => pinned = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm_schedule_btn'),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await state.scheduleAnnouncement(
                    id: ann.id,
                    publishAt: state.virtualTime,
                    expiresAt: state.virtualTime.add(
                      Duration(hours: windowHours),
                    ),
                    pinned: pinned,
                    simulateFailure: simMode,
                  );
                },
                child: const Text('Confirm & Run Conflict Check'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showHumanRecoveryDialog(Announcement ann) async {
    final noteCtrl = TextEditingController(
      text:
          'Verified emergency broadcast endpoint configuration, corrected schema mapping, and authorized manual recovery override.',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Human Recovery Action — ${ann.id}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escalated Failure: ${ann.lastError ?? "Unrecoverable downstream error"}',
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Audit Resolution Note (Recorded in Audit Log)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_human_recovery_btn'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await state.recoverPermanentFailure(
                id: ann.id,
                resolutionNote: noteCtrl.text,
                publishImmediately: true,
              );
            },
            child: const Text('Resolve & Publish Immediately'),
          ),
        ],
      ),
    );
  }
}

