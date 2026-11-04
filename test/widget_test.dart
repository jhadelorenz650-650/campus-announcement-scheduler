/// Week 15 Flutter Web Widget & State Tests (IA6).
/// Verifies responsive UI rendering, role switching, workflow tabs,
/// automation tick execution, and security negative-path probe feedback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_announcement_scheduler/frontend/services/api_client.dart';
import 'package:campus_announcement_scheduler/frontend/state/app_state.dart';
import 'package:campus_announcement_scheduler/main.dart';

void main() {
  testWidgets(
    'T-UI-01: Flutter Web UI renders workflow pipeline, switches roles, executes scheduler tick, and runs negative-path probes',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final appState = AppState(
        apiClient: ApiClient(forcePreparedFallback: true),
      );

      await tester.pumpWidget(
        CampusAnnouncementSchedulerApp(customState: appState),
      );
      await tester.pumpAndSettle();

      // Verify initial title and seeded announcements appear
      expect(
        find.textContaining('Campus Announcement Scheduler'),
        findsOneWidget,
      );
      expect(appState.announcements.length, equals(7));
      expect(
        find.textContaining('Emergency Severed Fiber Line'),
        findsOneWidget,
      );

      // Trigger Scheduler Tick from quick button as Publisher
      final tickBtn = find.byKey(const Key('quick_tick_button'));
      expect(tickBtn, findsOneWidget);
      await tester.tap(tickBtn);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Scheduler Tick Complete'),
        findsOneWidget,
      );

      // Switch to Campus User role and verify Data Minimization banner
      await tester.tap(find.byKey(const Key('role_chip_campus_user')));
      await tester.pumpAndSettle();
      expect(appState.isDataMinimizedView, isTrue);

      // Navigate to Tab 4 (Security & Negative Lab) and execute Tampered Token probe
      await tester.tap(find.byKey(const Key('nav_tab_3')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('probe_btn_tampered_token')));
      await tester.pumpAndSettle();

      expect(find.textContaining('AUTH_INVALID_SIGNATURE'), findsWidgets);
    },
  );
}
