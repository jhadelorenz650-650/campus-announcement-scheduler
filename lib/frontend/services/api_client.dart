/// Dual-transport API Client for the Flutter Web frontend.
/// Communicates over HTTP/HTTPS with `bin/server.dart` (`http://127.0.0.1:8080`)
/// and provides an automatic or manual toggle to the Week 18 Prepared
/// Controlled Fallback transport so demonstrations never fail if the external
/// server process is stopped or unreachable.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;

import '../../backend/server_app.dart';

class ApiResponse {
  final int statusCode;
  final Map<String, dynamic> body;
  final Map<String, String> headers;
  final bool usedFallback;

  const ApiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.usedFallback,
  });

  bool get isOk => statusCode >= 200 && statusCode < 300;
}

class ApiClient {
  String baseUrl;
  bool forcePreparedFallback;
  final ServerApp _embeddedFallbackServer = ServerApp();
  late final shelf.Handler _fallbackHandler = _embeddedFallbackServer.handler;

  ApiClient({
    this.baseUrl = 'http://127.0.0.1:8080',
    this.forcePreparedFallback = false,
  });

  Future<ApiResponse> request({
    required String method,
    required String path,
    String? bearerToken,
    Map<String, dynamic>? jsonBody,
  }) async {
    final headers = <String, String>{
      'content-type': 'application/json; charset=utf-8',
      if (bearerToken != null && bearerToken.isNotEmpty)
        'authorization': 'Bearer $bearerToken',
    };

    final encodedBody = jsonBody != null ? jsonEncode(jsonBody) : null;

    if (!forcePreparedFallback) {
      try {
        final uri = Uri.parse('$baseUrl$path');
        late http.Response httpRes;
        final timeout = const Duration(seconds: 2);

        switch (method.toUpperCase()) {
          case 'GET':
            httpRes = await http.get(uri, headers: headers).timeout(timeout);
            break;
          case 'POST':
            httpRes = await http
                .post(uri, headers: headers, body: encodedBody)
                .timeout(timeout);
            break;
          case 'PUT':
            httpRes = await http
                .put(uri, headers: headers, body: encodedBody)
                .timeout(timeout);
            break;
          default:
            httpRes = await http.get(uri, headers: headers).timeout(timeout);
        }

        final decoded = httpRes.body.isNotEmpty
            ? (jsonDecode(httpRes.body) as Map<String, dynamic>)
            : <String, dynamic>{};

        return ApiResponse(
          statusCode: httpRes.statusCode,
          body: decoded,
          headers: httpRes.headers,
          usedFallback: false,
        );
      } catch (_) {
        // Live backend unreachable -> automatically route through Prepared Controlled Fallback
      }
    }

    final shelfReq = shelf.Request(
      method.toUpperCase(),
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: encodedBody,
    );
    final shelfRes = await _fallbackHandler(shelfReq);
    final rawBody = await shelfRes.readAsString();
    final decoded = rawBody.isNotEmpty
        ? (jsonDecode(rawBody) as Map<String, dynamic>)
        : <String, dynamic>{};

    return ApiResponse(
      statusCode: shelfRes.statusCode,
      body: decoded,
      headers: shelfRes.headers,
      usedFallback: true,
    );
  }
}

