/// Week 14 Secure Integration (SA8 & IA5):
/// Authentication, Salted Password Hashing, HMAC-SHA256 Signed Bearer Tokens,
/// and Role-Based Authorization (RBAC).
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../shared/models/announcement.dart';

class UserAccount {
  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String salt;
  final String passwordHash;

  const UserAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.salt,
    required this.passwordHash,
  });

  Map<String, dynamic> toPublicJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'role': role.wireName,
    'roleLabel': role.label,
  };
}

class TokenVerificationResult {
  final bool isValid;
  final String? errorCode;
  final String? errorMessage;
  final String? userId;
  final String? email;
  final String? displayName;
  final UserRole? role;

  const TokenVerificationResult.valid({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
  }) : isValid = true,
       errorCode = null,
       errorMessage = null;

  const TokenVerificationResult.invalid({
    required this.errorCode,
    required this.errorMessage,
  }) : isValid = false,
       userId = null,
       email = null,
       displayName = null,
       role = null;
}

class AuthService {
  final String _hmacSecret;
  final Duration _defaultTtl;
  late final Map<String, UserAccount> _usersByEmail;

  AuthService({
    String hmacSecret = 'campus-scheduler-hmac-sha256-default-dev-key-2026',
    Duration defaultTtl = const Duration(minutes: 60),
  }) : _hmacSecret = hmacSecret,
       _defaultTtl = defaultTtl {
    _usersByEmail = _seedDefaultUsers();
  }

  /// Iterative salted SHA-256 password key derivation (1,000 rounds)
  /// justified to protect stored credentials against rainbow table attacks.
  static String hashPassword(String password, String salt) {
    List<int> digest = utf8.encode('$salt:$password');
    for (int i = 0; i < 1000; i++) {
      digest = sha256.convert([...digest, ...utf8.encode(salt)]).bytes;
    }
    return base64UrlEncode(digest);
  }

  Map<String, UserAccount> _seedDefaultUsers() {
    final accounts = <UserAccount>[
      UserAccount(
        id: 'usr-author-01',
        email: 'author@campus.edu',
        displayName: 'Prof. Elena Vance (Author)',
        role: UserRole.author,
        salt: 'salt-author-01',
        passwordHash: hashPassword('AuthorPass!26', 'salt-author-01'),
      ),
      UserAccount(
        id: 'usr-reviewer-01',
        email: 'reviewer@campus.edu',
        displayName: 'Dean Marcus Sterling (Reviewer)',
        role: UserRole.reviewer,
        salt: 'salt-reviewer-01',
        passwordHash: hashPassword('ReviewerPass!26', 'salt-reviewer-01'),
      ),
      UserAccount(
        id: 'usr-publisher-01',
        email: 'publisher@campus.edu',
        displayName: 'Hannah Cho (Publisher Ops)',
        role: UserRole.publisher,
        salt: 'salt-publisher-01',
        passwordHash: hashPassword('PublisherPass!26', 'salt-publisher-01'),
      ),
      UserAccount(
        id: 'usr-student-01',
        email: 'student@campus.edu',
        displayName: 'Alex Rivera (Campus User)',
        role: UserRole.campusUser,
        salt: 'salt-student-01',
        passwordHash: hashPassword('StudentPass!26', 'salt-student-01'),
      ),
    ];
    return {for (final u in accounts) u.email.toLowerCase(): u};
  }

  List<UserAccount> get demoAccounts => _usersByEmail.values.toList();

  UserAccount? authenticatePassword(String email, String password) {
    final account = _usersByEmail[email.trim().toLowerCase()];
    if (account == null) return null;
    final computed = hashPassword(password, account.salt);
    if (!_constantTimeEquals(computed, account.passwordHash)) {
      return null;
    }
    return account;
  }

  /// Issues an HMAC-SHA256 signed JWT-style token (`header.payload.signature`).
  String issueToken(
    UserAccount user, {
    DateTime? now,
    Duration? customTtl,
  }) {
    final issuedAt = (now ?? DateTime.now()).toUtc();
    final expiresAt = issuedAt.add(customTtl ?? _defaultTtl);

    final headerJson = jsonEncode({'alg': 'HS256', 'typ': 'CAS-JWT'});
    final payloadJson = jsonEncode({
      'sub': user.id,
      'email': user.email,
      'name': user.displayName,
      'role': user.role.wireName,
      'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
      'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
    });

    final encodedHeader = base64UrlEncode(utf8.encode(headerJson));
    final encodedPayload = base64UrlEncode(utf8.encode(payloadJson));
    final signingInput = '$encodedHeader.$encodedPayload';
    final signature = _sign(signingInput);
    return '$signingInput.$signature';
  }

  /// Helper to produce an already-expired token for Week 14 negative-path demos.
  String issueExpiredToken(UserAccount user, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    return issueToken(
      user,
      now: reference.subtract(const Duration(hours: 2)),
      customTtl: const Duration(hours: 1),
    );
  }

  /// Helper to produce an altered/tampered token (payload role escalated to
  /// publisher without valid HMAC key) for Week 14 negative-path demos.
  String issueTamperedToken(UserAccount user, {DateTime? now}) {
    final validToken = issueToken(user, now: now);
    final parts = validToken.split('.');
    final forgedPayload = jsonEncode({
      'sub': user.id,
      'email': user.email,
      'name': user.displayName,
      'role': UserRole.publisher.wireName,
      'iat': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      'exp':
          DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
    });
    final tamperedEncodedPayload = base64UrlEncode(utf8.encode(forgedPayload));
    return '${parts[0]}.$tamperedEncodedPayload.${parts[2]}';
  }

  /// Verifies token structure, HMAC-SHA256 signature integrity, and expiration.
  TokenVerificationResult verifyToken(String? rawAuthHeader, {DateTime? now}) {
    if (rawAuthHeader == null || rawAuthHeader.trim().isEmpty) {
      return const TokenVerificationResult.invalid(
        errorCode: 'AUTH_MISSING_TOKEN',
        errorMessage: 'Missing Authorization Bearer token.',
      );
    }

    final clean = rawAuthHeader.trim();
    final token = clean.toLowerCase().startsWith('bearer ')
        ? clean.substring(7).trim()
        : clean;

    final parts = token.split('.');
    if (parts.length != 3) {
      return const TokenVerificationResult.invalid(
        errorCode: 'AUTH_MALFORMED_TOKEN',
        errorMessage: 'Malformed authentication token structure.',
      );
    }

    final signingInput = '${parts[0]}.${parts[1]}';
    final expectedSig = _sign(signingInput);
    if (!_constantTimeEquals(parts[2], expectedSig)) {
      return const TokenVerificationResult.invalid(
        errorCode: 'AUTH_INVALID_SIGNATURE',
        errorMessage:
            'Token HMAC-SHA256 signature verification failed (altered or forged token).',
      );
    }

    try {
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      final expSeconds = (payload['exp'] as num?)?.toInt() ?? 0;
      final currentSeconds =
          (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;

      if (currentSeconds >= expSeconds) {
        return const TokenVerificationResult.invalid(
          errorCode: 'AUTH_TOKEN_EXPIRED',
          errorMessage: 'Authentication token has expired.',
        );
      }

      return TokenVerificationResult.valid(
        userId: payload['sub'] as String,
        email: payload['email'] as String,
        displayName: (payload['name'] as String?) ?? 'Campus User',
        role: UserRole.fromWire(payload['role'] as String),
      );
    } catch (_) {
      return const TokenVerificationResult.invalid(
        errorCode: 'AUTH_CORRUPT_PAYLOAD',
        errorMessage: 'Unable to decode token claims.',
      );
    }
  }

  String _sign(String input) {
    final hmac = Hmac(sha256, utf8.encode(_hmacSecret));
    final digest = hmac.convert(utf8.encode(input));
    return base64UrlEncode(digest.bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

