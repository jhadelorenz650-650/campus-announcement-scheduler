/// Main entrypoint for Project 26: Campus Announcement Scheduler (Flutter Web).
library;

import 'package:flutter/material.dart';
import 'frontend/screens/dashboard_screen.dart';
import 'frontend/state/app_state.dart';

void main() {
  runApp(const CampusAnnouncementSchedulerApp());
}

class CampusAnnouncementSchedulerApp extends StatefulWidget {
  final AppState? customState;

  const CampusAnnouncementSchedulerApp({super.key, this.customState});

  @override
  State<CampusAnnouncementSchedulerApp> createState() =>
      _CampusAnnouncementSchedulerAppState();
}

class _CampusAnnouncementSchedulerAppState
    extends State<CampusAnnouncementSchedulerApp> {
  late final AppState _appState = widget.customState ?? AppState();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Announcement Scheduler — Project 26',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F2942),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: DashboardScreen(appState: _appState),
    );
  }
}
