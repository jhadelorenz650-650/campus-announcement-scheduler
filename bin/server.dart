/// Standalone Backend REST API Server entrypoint for Project 26.
/// Run with: `dart run bin/server.dart`
library;

import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:campus_announcement_scheduler/backend/automation/automation_engine.dart';
import 'package:campus_announcement_scheduler/backend/security/auth_service.dart';
import 'package:campus_announcement_scheduler/backend/server_app.dart';
import 'package:campus_announcement_scheduler/backend/storage/announcement_repository.dart';
import 'package:campus_announcement_scheduler/backend/storage/file_persistence_adapter.dart';

Future<void> main(List<String> args) async {
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final hmacSecret =
      Platform.environment['JWT_HMAC_SECRET'] ??
      'campus-scheduler-hmac-sha256-default-dev-key-2026';
  final storagePath =
      Platform.environment['STORAGE_PATH'] ?? 'data/announcements_db.json';
  final snapshotPath =
      Platform.environment['SNAPSHOT_PATH'] ??
      'data/announcements_snapshot.json';
  final enableTls =
      (Platform.environment['ENABLE_TLS'] ?? 'false').toLowerCase() == 'true' ||
      args.contains('--tls');

  final persistence = FilePersistenceAdapter(
    storagePath: storagePath,
    snapshotPath: snapshotPath,
  );
  final repository = AnnouncementRepository(persistence: persistence);
  final authService = AuthService(hmacSecret: hmacSecret);
  final automationEngine = AutomationEngine(repository: repository);

  final serverApp = ServerApp(
    repository: repository,
    authService: authService,
    automationEngine: automationEngine,
  );

  // Background periodic scheduler worker (every 30 seconds)
  final timer = Timer.periodic(const Duration(seconds: 30), (_) {
    automationEngine.runTick(
      correlationId: 'corr-bg-worker-${DateTime.now().millisecondsSinceEpoch}',
      triggeredBy: 'background-timer',
      ignoreRetryBackoff: false,
    );
  });

  SecurityContext? securityContext;
  if (enableTls) {
    final certPath =
        Platform.environment['TLS_CERT_PATH'] ?? 'certs/server_cert.pem';
    final keyPath =
        Platform.environment['TLS_KEY_PATH'] ?? 'certs/server_key.pem';
    if (File(certPath).existsSync() && File(keyPath).existsSync()) {
      securityContext = SecurityContext()
        ..useCertificateChain(certPath)
        ..usePrivateKey(keyPath);
    } else {
      stdout.writeln(
        '[WARN] TLS requested but certificate files not found at $certPath / $keyPath. Falling back to HTTP with HSTS headers.',
      );
    }
  }

  final server = await shelf_io.serve(
    serverApp.handler,
    host,
    port,
    securityContext: securityContext,
  );

  final scheme = securityContext != null ? 'https' : 'http';
  stdout.writeln(
    '====================================================================',
  );
  stdout.writeln(
    'Project 26: Campus Announcement Scheduler Backend API Running',
  );
  stdout.writeln('Listening on: $scheme://${server.address.host}:${server.port}');
  stdout.writeln('Health Check: $scheme://${server.address.host}:${server.port}/api/v1/health');
  stdout.writeln('Metrics:      $scheme://${server.address.host}:${server.port}/api/v1/metrics');
  stdout.writeln(
    '====================================================================',
  );

  ProcessSignal.sigint.watch().listen((_) async {
    timer.cancel();
    await server.close(force: true);
    exit(0);
  });
}

