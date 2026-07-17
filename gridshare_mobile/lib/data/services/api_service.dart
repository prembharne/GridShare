import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Base URL for the GridShare backend API.
/// Override via `--dart-define=API_BASE_URL=https://your-backend.example.com`
/// Default points to Android emulator localhost (10.0.2.2:3000).
const String _defaultBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000');

/// Centralised HTTP client with auth, idempotency keys, and error mapping.
class ApiService {
  ApiService({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? _defaultBaseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  String? _accessToken;

  void setAuth({required String userId, required String accessToken}) {
    _accessToken = accessToken;
  }

  void clearAuth() {
    _accessToken = null;
  }

  Map<String, String> _headers({String? idempotencyKey}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null) h['Authorization'] = 'Bearer $_accessToken';
    if (idempotencyKey != null) h['Idempotency-Key'] = idempotencyKey;
    return h;
  }

  dynamic _check(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    final code = body['error']?['code'] ?? 'HTTP_${res.statusCode}';
    final msg = body['error']?['message'] ?? res.reasonPhrase ?? 'Request failed';
    throw ApiException(code: code, message: msg, statusCode: res.statusCode, details: body['error']?['details']);
  }

  // ============================ AUTH ============================

  /// POST /api/auth/send-otp — Send OTP to phone number.
  Future<AuthResponse> sendOtp({
    required String phone,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/api/auth/send-otp'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode({'phone': phone}),
    );
    return AuthResponse.fromJson(_check(res));
  }

  /// POST /api/auth/verify-otp — Verify OTP and return JWT + user.
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String otp,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/api/auth/verify-otp'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode({'phone': phone, 'otp': otp}),
    );
    return AuthResponse.fromJson(_check(res));
  }

  // ============================ WALLET ============================

  /// POST /wallet/topup — Create a Razorpay order for UPI top-up.
  /// Returns { orderId, amountCredits, currency: 'INR', keyId } for Razorpay checkout.
  Future<TopUpOrder> createTopUpOrder({
    required int amountCredits,
    required String userId,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/wallet/topup'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode({'userId': userId, 'amountCredits': amountCredits}),
    );
    return TopUpOrder.fromJson(_check(res));
  }

  /// GET /wallet/:userId/balance — Current credit balance from contract.
  Future<WalletBalance> getBalance({required String userId}) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/wallet/$userId/balance'),
      headers: _headers(),
    );
    return WalletBalance.fromJson(_check(res));
  }

  // ============================ SESSIONS ============================

  /// POST /sessions/intent — Register intent to charge (status: created).
  /// Requires rider to have sufficient wallet balance for deposit (checked at start).
  Future<Session> createIntent({
    required String riderId,
    required String hostId,
    required String outletId,
    required int depositCredits,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/sessions/intent'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode({
        'riderId': riderId,
        'hostId': hostId,
        'outletId': outletId,
        'depositCredits': depositCredits,
      }),
    );
    final data = _check(res);
    return Session.fromJson(data['session']);
  }

  /// POST /sessions/:id/start — Lock deposit from wallet + turn hardware ON.
  /// Idempotent on sessionId.
  Future<SessionStartResponse> startSession({
    required String sessionId,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/sessions/$sessionId/start'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode({'idempotencyKey': idempotencyKey}),
    );
    return SessionStartResponse.fromJson(_check(res));
  }

  /// POST /sessions/:id/activate — Legacy endpoint alias for startSession.
  /// Some backends may use /activate instead of /start.
  Future<SessionStartResponse> activateSession({
    required String sessionId,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/sessions/$sessionId/activate'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode({'idempotencyKey': idempotencyKey}),
    );
    return SessionStartResponse.fromJson(_check(res));
  }

  /// POST /sessions/:id/telemetry — Push live telemetry (energy, current, voltage, temp).
  /// Backend evaluates safety + auto-stop threshold.
  Future<TelemetryResult> ingestTelemetry({
    required String sessionId,
    required Telemetry telemetry,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/sessions/$sessionId/telemetry'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode(telemetry.toJson()),
    );
    return TelemetryResult.fromJson(_check(res));
  }

  /// POST /sessions/:id/stop — Turn hardware OFF + settle on-chain (transfer credits).
  /// Idempotent on sessionId.
  Future<SessionStopResponse> stopSession({
    required String sessionId,
    String reason = 'user_stop',
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/sessions/$sessionId/stop'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode({'reason': reason, 'idempotencyKey': idempotencyKey}),
    );
    return SessionStopResponse.fromJson(_check(res));
  }

  /// GET /sessions/:id/audit — Full session audit bundle (telemetry, hardware commands, events).
  Future<SessionAudit> getSessionAudit({required String sessionId}) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/sessions/$sessionId/audit'),
      headers: _headers(),
    );
    return SessionAudit.fromJson(_check(res));
  }

  // ============================ OUTLETS ============================

  /// GET /outlets/nearby?lat=&lng=&radiusKm= — List nearby available outlets.
  Future<List<Outlet>> getNearbyOutlets({
    required double lat,
    required double lng,
    double radiusKm = 10,
  }) async {
    final uri = Uri.parse('$_baseUrl/outlets/nearby').replace(
      queryParameters: {'lat': lat.toString(), 'lng': lng.toString(), 'radiusKm': radiusKm.toString()},
    );
    final res = await _client.get(uri, headers: _headers());
    final data = _check(res);
    return (data['outlets'] as List).map((e) => Outlet.fromJson(e)).toList();
  }

  // ============================ ADMIN / HOST ============================

  /// GET /admin/hosts/earnings — List all hosts with on-chain earned credits.
  Future<List<HostEarnings>> getHostEarnings() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/admin/hosts/earnings'),
      headers: _headers(),
    );
    final data = _check(res);
    return (data['hosts'] as List).map((e) => HostEarnings.fromJson(e)).toList();
  }

  /// POST /admin/hosts/:id/payout — Create pending payout row (credits snapshotted).
  Future<HostPayout> createHostPayout({
    required String hostId,
    required int credits,
    required String method, // 'upi' | 'bank'
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/admin/hosts/$hostId/payout'),
      headers: _headers(),
      body: jsonEncode({'credits': credits, 'method': method}),
    );
    return HostPayout.fromJson(_check(res));
  }

  /// POST /admin/payouts/:id/confirm — Confirm off-chain UPI/bank paid, then burn credits on-chain.
  Future<HostPayout> confirmHostPayout({
    required String payoutId,
    required String reference, // UPI txn id / bank UTR
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/admin/payouts/$payoutId/confirm'),
      headers: _headers(),
      body: jsonEncode({'reference': reference}),
    );
    return HostPayout.fromJson(_check(res));
  }

  void dispose() => _client.close();

  /// Generic POST request for custom endpoints (e.g., Clerk token exchange)
  Future<Map<String, dynamic>> post({
    required String path,
    required Map<String, dynamic> body,
    String? idempotencyKey,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode(body),
    );
    return _check(res) as Map<String, dynamic>;
  }
}

/// Typed exception carrying backend error code + details.
class ApiException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;

  const ApiException({required this.code, required this.message, required this.statusCode, this.details});

  @override
  String toString() => 'ApiException($code): $message';
}

// ============================ DTOs ============================

class AuthResponse {
  final String? accessToken;
  final String? refreshToken;
  final User? user;
  final bool otpSent;
  final String? message;

  AuthResponse({this.accessToken, this.refreshToken, this.user, this.otpSent = false, this.message});

  factory AuthResponse.fromJson(Map<String, dynamic> j) => AuthResponse(
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        user: j['user'] != null ? User.fromJson(j['user'] as Map<String, dynamic>) : null,
        otpSent: j['otpSent'] as bool? ?? false,
        message: j['message'] as String?,
      );
}

class TopUpOrder {
  final String orderId;
  final int amountCredits;
  final String currency;
  final String keyId; // Razorpay key_id for checkout

  TopUpOrder({required this.orderId, required this.amountCredits, required this.currency, required this.keyId});

  factory TopUpOrder.fromJson(Map<String, dynamic> j) => TopUpOrder(
        orderId: j['orderId'] as String,
        amountCredits: (j['amountCredits'] as num).toInt(),
        currency: j['currency'] as String? ?? 'INR',
        keyId: j['keyId'] as String,
      );
}

class WalletBalance {
  final String userId;
  final int balanceCredits;

  WalletBalance({required this.userId, required this.balanceCredits});

  factory WalletBalance.fromJson(Map<String, dynamic> j) => WalletBalance(
        userId: j['userId'] as String,
        balanceCredits: (j['balanceCredits'] as num).toInt(),
      );
}

class SessionStartResponse {
  final Session session;
  final Map<String, dynamic> chain;
  final HardwareCommand hardware;

  const SessionStartResponse({required this.session, required this.chain, required this.hardware});

  factory SessionStartResponse.fromJson(Map<String, dynamic> j) => SessionStartResponse(
        session: Session.fromJson(j['session'] as Map<String, dynamic>),
        chain: j['chain'] as Map<String, dynamic>,
        hardware: HardwareCommand.fromJson(j['hardware'] as Map<String, dynamic>),
      );
}

class TelemetryResult {
  final Session session;
  final Telemetry telemetry;
  final SettlementPreview? settlementPreview;
  final bool safetyTripped;
  final String? safetyReason;
  final bool autoStopped;

  TelemetryResult({
    required this.session,
    required this.telemetry,
    this.settlementPreview,
    this.safetyTripped = false,
    this.safetyReason,
    this.autoStopped = false,
  });

  factory TelemetryResult.fromJson(Map<String, dynamic> j) => TelemetryResult(
        session: Session.fromJson(j['session'] as Map<String, dynamic>),
        telemetry: Telemetry.fromJson(j['telemetry'] as Map<String, dynamic>),
        settlementPreview: j['settlementPreview'] != null
            ? SettlementPreview.fromJson(j['settlementPreview'] as Map<String, dynamic>)
            : null,
        safetyTripped: j['safetyTripped'] as bool? ?? false,
        safetyReason: j['safetyReason'] as String?,
        autoStopped: j['autoStopped'] as bool? ?? false,
      );
}

class SettlementPreview {
  final int energyWh;
  final int amountDueCredits;
  final int hostShareCredits;
  final int serviceFeeCredits;
  final int refundCredits;
  final int depositCredits;

  const SettlementPreview({
    required this.energyWh,
    required this.amountDueCredits,
    required this.hostShareCredits,
    required this.serviceFeeCredits,
    required this.refundCredits,
    required this.depositCredits,
  });

  factory SettlementPreview.fromJson(Map<String, dynamic> j) => SettlementPreview(
        energyWh: (j['energyWh'] as num).toInt(),
        amountDueCredits: (j['amountDueCredits'] as num).toInt(),
        hostShareCredits: (j['hostShareCredits'] as num).toInt(),
        serviceFeeCredits: (j['serviceFeeCredits'] as num).toInt(),
        refundCredits: (j['refundCredits'] as num).toInt(),
        depositCredits: (j['depositCredits'] as num).toInt(),
      );

  double get energyKwh => energyWh / 1000;
}

class SessionStopResponse {
  final Session session;
  final Telemetry? telemetry;
  final SettlementPreview? settlement;
  final Map<String, dynamic> chain;
  final HardwareCommand? hardware;

  const SessionStopResponse({
    required this.session,
    this.telemetry,
    this.settlement,
    required this.chain,
    this.hardware,
  });

  factory SessionStopResponse.fromJson(Map<String, dynamic> j) => SessionStopResponse(
        session: Session.fromJson(j['session'] as Map<String, dynamic>),
        telemetry: j['telemetry'] != null ? Telemetry.fromJson(j['telemetry'] as Map<String, dynamic>) : null,
        settlement: j['settlement'] != null ? SettlementPreview.fromJson(j['settlement'] as Map<String, dynamic>) : null,
        chain: j['chain'] as Map<String, dynamic>,
        hardware: j['hardware'] != null ? HardwareCommand.fromJson(j['hardware'] as Map<String, dynamic>) : null,
      );
}

class SessionAudit {
  final Session session;
  final List<Telemetry> telemetry;
  final Map<String, dynamic>? contract;
  final List<HardwareCommand> hardwareCommands;
  final List<Map<String, dynamic>> events;

  const SessionAudit({
    required this.session,
    required this.telemetry,
    this.contract,
    required this.hardwareCommands,
    required this.events,
  });

  factory SessionAudit.fromJson(Map<String, dynamic> j) => SessionAudit(
        session: Session.fromJson(j['session'] as Map<String, dynamic>),
        telemetry: (j['telemetry'] as List).map((e) => Telemetry.fromJson(e as Map<String, dynamic>)).toList(),
        contract: j['contract'] as Map<String, dynamic>?,
        hardwareCommands: (j['hardwareCommands'] as List? ?? [])
            .map((e) => HardwareCommand.fromJson(e as Map<String, dynamic>))
            .toList(),
        events: (j['events'] as List? ?? []).map((e) => e as Map<String, dynamic>).toList(),
      );
}

class HardwareCommand {
  final String id;
  final String outletId;
  final bool desiredState;
  final String reason;
  final String sessionId;
  final DateTime createdAt;
  final bool success;
  final String? error;

  const HardwareCommand({
    required this.id,
    required this.outletId,
    required this.desiredState,
    required this.reason,
    required this.sessionId,
    required this.createdAt,
    required this.success,
    this.error,
  });

  factory HardwareCommand.fromJson(Map<String, dynamic> j) => HardwareCommand(
        id: j['id'] as String,
        outletId: j['outletId'] as String,
        desiredState: j['desiredState'] as bool,
        reason: j['reason'] as String,
        sessionId: j['sessionId'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        success: j['success'] as bool,
        error: j['error'] as String?,
      );
}

class HostEarnings {
  final String hostId;
  final int earnedCredits;

  const HostEarnings({required this.hostId, required this.earnedCredits});

  factory HostEarnings.fromJson(Map<String, dynamic> j) => HostEarnings(
        hostId: j['hostId'] as String,
        earnedCredits: (j['earnedCredits'] as num).toInt(),
      );
}

class HostPayout {
  final String id;
  final String hostId;
  final int credits;
  final int inrAmount;
  final String method;
  final String? reference;
  final String status; // 'pending' | 'paid'
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime createdAt;
  final DateTime? paidAt;

  const HostPayout({
    required this.id,
    required this.hostId,
    required this.credits,
    required this.inrAmount,
    required this.method,
    this.reference,
    required this.status,
    this.periodStart,
    this.periodEnd,
    required this.createdAt,
    this.paidAt,
  });

  factory HostPayout.fromJson(Map<String, dynamic> j) => HostPayout(
        id: j['id'] as String,
        hostId: j['hostId'] as String,
        credits: (j['credits'] as num).toInt(),
        inrAmount: (j['inrAmount'] as num).toInt(),
        method: j['method'] as String,
        reference: j['reference'] as String?,
        status: j['status'] as String,
        periodStart: j['periodStart'] != null ? DateTime.parse(j['periodStart'] as String) : null,
        periodEnd: j['periodEnd'] != null ? DateTime.parse(j['periodEnd'] as String) : null,
        createdAt: DateTime.parse(j['createdAt'] as String),
        paidAt: j['paidAt'] != null ? DateTime.parse(j['paidAt'] as String) : null,
      );
}

class BalanceResponse {
  final String userId;
  final int balanceCredits;

  const BalanceResponse({required this.userId, required this.balanceCredits});

  factory BalanceResponse.fromJson(Map<String, dynamic> j) => BalanceResponse(
        userId: j['userId'] as String,
        balanceCredits: (j['balanceCredits'] as num).toInt(),
      );
}