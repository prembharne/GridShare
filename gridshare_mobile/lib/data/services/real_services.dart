import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import '../models/models.dart';

/// Real HTTP-backed service implementations.
/// These wrap ApiService and expose the same interface the UI expects.

class OutletService {
  OutletService(this._api);
  final ApiService _api;

  Future<List<Outlet>> nearby({double lat = 12.9716, double lng = 77.5946, double radiusKm = 10}) {
    return _api.getNearbyOutlets(lat: lat, lng: lng, radiusKm: radiusKm);
  }
}

class SessionService {
  SessionService(this._api);
  final ApiService _api;

  /// Create session intent (status: created). User must have wallet balance for deposit.
  Future<Session> createIntent({
    required String outletId,
    required int depositCredits,
    required String riderId,
    required String hostId,
    String? idempotencyKey,
  }) async {
    final result = await _api.createIntent(
      riderId: riderId,
      hostId: hostId,
      outletId: outletId,
      depositCredits: depositCredits,
      idempotencyKey: idempotencyKey,
    );
    return result;
  }

  /// Start session: lock deposit from wallet + turn hardware ON.
  Future<Session> startSession({
    required String sessionId,
    String? idempotencyKey,
  }) async {
    final result = await _api.startSession(sessionId: sessionId, idempotencyKey: idempotencyKey);
    return result.session;
  }

  /// Activate session (legacy endpoint alias for /start).
  Future<Session> activateSession({
    required String sessionId,
    String? idempotencyKey,
  }) async {
    final result = await _api.activateSession(sessionId: sessionId, idempotencyKey: idempotencyKey);
    return result.session;
  }

  /// Push telemetry from IoT device.
  Future<TelemetryResult> ingestTelemetry({
    required String sessionId,
    required Telemetry telemetry,
    String? idempotencyKey,
  }) {
    return _api.ingestTelemetry(sessionId: sessionId, telemetry: telemetry, idempotencyKey: idempotencyKey);
  }

  /// Stop session: turn hardware OFF + settle on-chain.
  Future<Session> stopSession({
    required String sessionId,
    String reason = 'user_stop',
    String? idempotencyKey,
  }) async {
    final result = await _api.stopSession(sessionId: sessionId, reason: reason, idempotencyKey: idempotencyKey);
    return result.session;
  }

  /// Get full audit bundle.
  Future<SessionAudit> getAudit({required String sessionId}) {
    return _api.getSessionAudit(sessionId: sessionId);
  }
}

class TelemetryService {
  TelemetryService();

  /// Stream telemetry via WebSocket (production).
  /// Connects to `wss://<host>/api/sessions/:id/telemetry` and yields real-time Telemetry.
  Stream<Telemetry> streamWebSocket(Session session) async* {
    final wsUrl = _buildWebSocketUrl(session.id);
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    try {
      await for (final event in channel.stream) {
        if (event is String) {
          try {
            final json = jsonDecode(event);
            // Backend sends telemetry in the same format as HTTP POST
            yield Telemetry.fromJson(json as Map<String, dynamic>);
          } catch (_) {
            // Ignore malformed messages
          }
        }
      }
    } finally {
      channel.sink.close();
    }
  }

  /// Fallback: HTTP polling for telemetry (if WebSocket not available).
  Stream<Telemetry> streamPolling(Session session, {Duration interval = const Duration(seconds: 2)}) async* {
    while (true) {
      await Future.delayed(interval);
      // Note: This would need a GET /sessions/:id/telemetry/latest endpoint
      // which doesn't exist yet. Kept for future implementation.
    }
  }

  String _buildWebSocketUrl(String sessionId) {
    // Build WebSocket URL from the API base URL
    const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');
    final wsBase = baseUrl.replaceFirst('http', 'ws');
    return '$wsBase/api/sessions/$sessionId/telemetry';
  }
}

class AuthService {
  AuthService(this._api, this._storage);
  final ApiService _api;
  final SecureStorage _storage;

  /// Send OTP to phone (backend: POST /api/auth/send-otp)
  Future<AuthResponse> sendOtp(String phone) async {
    return _api.sendOtp(phone: phone, idempotencyKey: 'send_otp_$phone');
  }

  /// Verify OTP (backend: POST /api/auth/verify-otp)
  /// Returns JWT tokens and user profile on success.
  Future<AuthResponse> verifyOtp(String phone, String otp) async {
    final response = await _api.verifyOtp(phone: phone, otp: otp, idempotencyKey: 'verify_otp_$phone');

    // Store tokens if login successful
    if (response.accessToken != null) {
      await _storage.saveTokens(
        accessToken: response.accessToken!,
        refreshToken: response.refreshToken ?? '',
      );
      if (response.user != null) {
        await _storage.saveUserId(response.user!.id);
        await _storage.saveUserData(response.user!);
      }
    }
    return response;
  }

  /// Sign in with Google ID token — exchanges with backend for session JWT.
  Future<AuthResponse> signInWithGoogle({
    required String googleId,
    required String email,
    required String name,
  }) async {
    final res = await _api.post(
      path: '/api/auth/google',
      body: { 'googleId': googleId, 'email': email, 'name': name },
      idempotencyKey: 'google_$googleId',
    );
    final response = AuthResponse.fromJson(res);
    if (response.accessToken != null) {
      await _storage.saveTokens(
        accessToken: response.accessToken!,
        refreshToken: response.refreshToken ?? '',
      );
      if (response.user != null) {
        await _storage.saveUserId(response.user!.id);
        await _storage.saveUserData(response.user!);
      }
    }
    return response;
  }

  /// Exchange Clerk session token for backend JWT
  /// Call this after successful Clerk authentication
  Future<AuthResponse> exchangeClerkToken({
    required String clerkUserId,
    required String clerkAccessToken,
    required String userName,
    required String userPhone,
  }) async {
    // Call backend to exchange Clerk token for backend JWT
    // Backend should verify the Clerk token and create/return JWT
    final res = await _api.post(
      path: '/api/auth/clerk/exchange',
      body: {
        'clerkUserId': clerkUserId,
        'clerkAccessToken': clerkAccessToken,
        'userName': userName,
        'userPhone': userPhone,
      },
      idempotencyKey: 'clerk_exchange_$clerkUserId',
    );

    final response = AuthResponse.fromJson(res);

    // Store tokens if login successful
    if (response.accessToken != null && response.refreshToken != null) {
      await _storage.saveTokens(
        accessToken: response.accessToken!,
        refreshToken: response.refreshToken!,
      );

      if (response.user != null) {
        await _storage.saveUserId(response.user!.id);
      }
    }

    return response;
  }

  /// Load stored tokens on app start
  Future<AuthTokens?> loadTokens() async {
    final access = await _storage.getAccessToken();
    final refresh = await _storage.getRefreshToken();
    if (access != null && refresh != null) {
      return AuthTokens(accessToken: access, refreshToken: refresh);
    }
    return null;
  }

  /// Clear tokens on logout
  Future<void> clearTokens() async {
    await _storage.clearTokens();
  }

  /// Fetch wallet balance after login
  Future<User> fetchUserWithBalance(String userId) async {
    final balance = await _api.getBalance(userId: userId);
    return User(id: userId, name: 'Rider', phone: '', walletBalanceCredits: balance.balanceCredits);
  }

  /// Try to restore session from secure storage on app startup.
  /// Returns the stored User if valid session exists, otherwise null.
  Future<User?> tryRestoreSession() async {
    try {
      final token = await _storage.getAccessToken();
      final userId = await _storage.getUserId();
      if (token == null || userId == null) return null;
      // Try to load cached user data first (fast path, no network needed)
      final cached = await _storage.getUserData();
      if (cached != null) return cached;
      // Fallback: fetch fresh from backend
      return await fetchUserWithBalance(userId);
    } catch (_) {
      // Token expired or network error — clear and force re-login
      await _storage.clearTokens();
      return null;
    }
  }
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  AuthTokens({required this.accessToken, required this.refreshToken});
}

/// Secure storage wrapper for JWT tokens and user data.
/// Uses flutter_secure_storage to persist across app restarts.
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> write({required String key, required String value}) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read({required String key}) async {
    return _storage.read(key: key);
  }

  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
  }

  // Convenience methods for auth tokens
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await write(key: 'access_token', value: accessToken);
    await write(key: 'refresh_token', value: refreshToken);
  }

  Future<void> saveUserId(String userId) async {
    await write(key: 'user_id', value: userId);
  }

  /// Cache full user data as JSON so we can restore without a network call.
  Future<void> saveUserData(User user) async {
    await write(key: 'cached_user', value: jsonEncode({
      'id': user.id,
      'name': user.name,
      'phone': user.phone,
      'walletBalanceCredits': user.walletBalanceCredits,
    }));
  }

  Future<User?> getUserData() async {
    final raw = await read(key: 'cached_user');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return User(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Rider',
        phone: j['phone'] as String? ?? '',
        walletBalanceCredits: (j['walletBalanceCredits'] as num?)?.toInt() ?? 0,
      );
    } catch (_) { return null; }
  }

  Future<String?> getAccessToken() async => read(key: 'access_token');
  Future<String?> getRefreshToken() async => read(key: 'refresh_token');
  Future<String?> getUserId() async => read(key: 'user_id');

  Future<void> clearTokens() async {
    await _storage.deleteAll();
  }
}

/// Host/admin services
class HostService {
  HostService(this._api);
  final ApiService _api;

  Future<List<HostEarnings>> getAllHostEarnings() => _api.getHostEarnings();

  Future<HostPayout> createPayout({
    required String hostId,
    required int credits,
    required String method,
  }) => _api.createHostPayout(hostId: hostId, credits: credits, method: method);

  Future<HostPayout> confirmPayout({
    required String payoutId,
    required String reference,
  }) => _api.confirmHostPayout(payoutId: payoutId, reference: reference);
}