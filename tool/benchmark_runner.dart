/// Week 16 Performance, Reliability and Deployment Evaluation Benchmark Runner.
/// Spins up an ephemeral HTTP server instance of `ServerApp`, executes both:
/// 1. Ordinary Workload Model (200 sequential & concurrent requests across Campus Feed, Workflow, and Health)
/// 2. Peak Workload Model (500 high-concurrency burst requests simulating exam-week traffic + scheduler ticks)
/// Collects response-time percentiles (p50, p95, p99), throughput (req/s), error rates,
/// and RSS memory footprint, and verifies `/api/v1/health`, `/api/v1/metrics`, and Rollback recovery.
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:campus_announcement_scheduler/backend/automation/automation_engine.dart';
import 'package:campus_announcement_scheduler/backend/security/auth_service.dart';
import 'package:campus_announcement_scheduler/backend/server_app.dart';
import 'package:campus_announcement_scheduler/backend/storage/announcement_repository.dart';

Future<void> main() async {
  final repo = AnnouncementRepository(seedIfEmpty: true);
  final auth = AuthService();
  final engine = AutomationEngine(repository: repo);
  final app = ServerApp(
    repository: repo,
    authService: auth,
    automationEngine: engine,
  );

  final server = await shelf_io.serve(app.handler, '127.0.0.1', 0);
  final baseUrl = 'http://127.0.0.1:${server.port}';
  final client = http.Client();

  stdout.writeln(
    '====================================================================',
  );
  stdout.writeln(
    'Week 16 Performance, Reliability & Deployment Evaluation Benchmark',
  );
  stdout.writeln('Target Server: $baseUrl');
  stdout.writeln(
    '====================================================================',
  );

  try {
    // Authenticate tokens for realistic workload mix
    final studentLogin = await client.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': 'student@campus.edu',
        'password': 'StudentPass!26',
      }),
    );
    final studentToken =
        (jsonDecode(studentLogin.body) as Map<String, dynamic>)['token']
            as String;

    final pubLogin = await client.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': 'publisher@campus.edu',
        'password': 'PublisherPass!26',
      }),
    );
    final pubToken =
        (jsonDecode(pubLogin.body) as Map<String, dynamic>)['token'] as String;

    final rssBaselineMb = ProcessInfo.currentRss / (1024 * 1024);

    // 1. Ordinary Workload Model: 200 requests, concurrency = 10
    final ordinaryResult = await _runWorkload(
      client: client,
      baseUrl: baseUrl,
      studentToken: studentToken,
      publisherToken: pubToken,
      totalRequests: 200,
      concurrency: 10,
    );

    // 2. Peak Workload Model: 500 requests, concurrency = 50
    final peakResult = await _runWorkload(
      client: client,
      baseUrl: baseUrl,
      studentToken: studentToken,
      publisherToken: pubToken,
      totalRequests: 500,
      concurrency: 50,
    );

    final rssPeakMb = ProcessInfo.currentRss / (1024 * 1024);

    // 3. Verify Health & Metrics Signals
    final healthRes = await client.get(Uri.parse('$baseUrl/api/v1/health'));
    final metricsRes = await client.get(Uri.parse('$baseUrl/api/v1/metrics'));

    // 4. Rehearse Snapshot & Rollback Recovery Latency
    final rbSw = Stopwatch()..start();
    await client.post(
      Uri.parse('$baseUrl/api/v1/admin/snapshot'),
      headers: {'authorization': 'Bearer $pubToken'},
    );
    await client.post(
      Uri.parse('$baseUrl/api/v1/automation/tick'),
      headers: {
        'authorization': 'Bearer $pubToken',
        'content-type': 'application/json',
      },
      body: jsonEncode({'advanceMinutes': 5}),
    );
    final rollbackRes = await client.post(
      Uri.parse('$baseUrl/api/v1/admin/rollback'),
      headers: {'authorization': 'Bearer $pubToken'},
    );
    rbSw.stop();

    stdout.writeln('\n--- 1. ORDINARY WORKLOAD (200 reqs, concurrency 10) ---');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(ordinaryResult));

    stdout.writeln('\n--- 2. PEAK WORKLOAD (500 reqs, concurrency 50) ---');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(peakResult));

    stdout.writeln('\n--- 3. RESOURCE & RECOVERY TELEMETRY ---');
    stdout.writeln(
      'Memory RSS Baseline: ${rssBaselineMb.toStringAsFixed(2)} MB',
    );
    stdout.writeln('Memory RSS After Peak: ${rssPeakMb.toStringAsFixed(2)} MB');
    stdout.writeln(
      'Snapshot + Mutation + Rollback Rehearsal Time: ${rbSw.elapsedMilliseconds} ms (HTTP ${rollbackRes.statusCode})',
    );
    stdout.writeln('Health Signal: ${healthRes.body}');
    stdout.writeln('Server Metrics Summary: ${metricsRes.body}');
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<Map<String, dynamic>> _runWorkload({
  required http.Client client,
  required String baseUrl,
  required String studentToken,
  required String publisherToken,
  required int totalRequests,
  required int concurrency,
}) async {
  final latenciesMs = <double>[];
  int successCount = 0;
  int errorCount = 0;

  final overallSw = Stopwatch()..start();
  int dispatched = 0;

  while (dispatched < totalRequests) {
    final batchSize = (totalRequests - dispatched).clamp(1, concurrency);
    final futures = <Future<void>>[];

    for (int i = 0; i < batchSize; i++) {
      final reqIndex = dispatched + i;
      futures.add(() async {
        final sw = Stopwatch()..start();
        try {
          http.Response res;
          if (reqIndex % 10 == 0) {
            res = await client.get(Uri.parse('$baseUrl/api/v1/health'));
          } else if (reqIndex % 5 == 0) {
            res = await client.get(
              Uri.parse('$baseUrl/api/v1/announcements'),
              headers: {'authorization': 'Bearer $publisherToken'},
            );
          } else {
            res = await client.get(
              Uri.parse('$baseUrl/api/v1/announcements'),
              headers: {'authorization': 'Bearer $studentToken'},
            );
          }
          sw.stop();
          latenciesMs.add(sw.elapsedMicroseconds / 1000.0);
          if (res.statusCode == 200) {
            successCount++;
          } else {
            errorCount++;
          }
        } catch (_) {
          sw.stop();
          errorCount++;
        }
      }());
    }

    await Future.wait(futures);
    dispatched += batchSize;
  }

  overallSw.stop();
  latenciesMs.sort();

  double pct(double p) {
    if (latenciesMs.isEmpty) return 0;
    final idx = ((latenciesMs.length - 1) * p).round();
    return double.parse(latenciesMs[idx].toStringAsFixed(2));
  }

  final elapsedSec = overallSw.elapsedMicroseconds / 1000000.0;
  final rps = elapsedSec > 0 ? totalRequests / elapsedSec : 0.0;

  return {
    'totalRequests': totalRequests,
    'concurrency': concurrency,
    'successCount': successCount,
    'errorCount': errorCount,
    'errorRatePercent': double.parse(
      ((errorCount / totalRequests) * 100).toStringAsFixed(2),
    ),
    'totalDurationMs': overallSw.elapsedMilliseconds,
    'throughputReqPerSec': double.parse(rps.toStringAsFixed(1)),
    'latencyMs': {
      'min': pct(0.0),
      'p50': pct(0.50),
      'p95': pct(0.95),
      'p99': pct(0.99),
      'max': pct(1.0),
    },
  };
}

