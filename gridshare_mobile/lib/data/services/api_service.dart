import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Canonical production backend. Used as the default and as the guaranteed
/// fallback host so a physical phone never ends up pointing at `localhost`.
const String kProductionBaseUrl = 'https://gridshare-production.up.railway.app';

String get _defaultBaseUrl {
  const envUrl = String.fromEnvironment('API_BASE_URL');
  if (envUrl.isNotEmpty) return envUrl;
  return kProductionBaseUrl;
}

/// Free-tier hosts (Render) sleep after inactivity and can take 20–50s to wake.
/// These generous timeouts + a warm-up ping stop the app from giving up early
/// with a `TimeoutException` while the server is still spinning up.
const Duration _kColdStartTimeout = Duration(seconds: 75);
const Duration _kWarmTimeout = Duration(seconds: 30);

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
    final msg =
        body['error']?['message'] ?? res.reasonPhrase ?? 'Request failed';
    throw ApiException(
        code: code,
        message: msg,
        statusCode: res.statusCode,
        details: body['error']?['details']);
  }

  // ==================== COLD-START / WARM-UP ====================

  bool _isWarm = false;

  /// Whether the backend has already responded successfully this session.
  /// UI can use this to decide whether to show a "connecting…" hint.
  bool get isWarm => _isWarm;

  /// Pings the backend health endpoint to wake a sleeping free-tier host

  /// (Render spins down after ~15 min idle and takes 20–50s to boot).
  /// Safe to call repeatedly; it becomes a cheap no-op once warm.
  /// Returns true if the server responded 2xx within [timeout].
  Future<bool> warmUp({Duration timeout = _kColdStartTimeout}) async {
    if (_isWarm) return true;
    for (final path in const ['/health', '/']) {
      try {
        final res = await _client
            .get(Uri.parse('$_baseUrl$path'), headers: _headers())
            .timeout(timeout);
        if (res.statusCode >= 200 && res.statusCode < 500) {
          _isWarm = true;
          return true;
        }
      } catch (_) {
        // try next path / fall through
      }
    }
    return false;
  }

  /// Sends a POST that tolerates cold starts: it warms the server first, then
  /// tries the primary URL with a long timeout, and finally the canonical
  /// production host. Never falls back to `localhost` (meaningless on a phone).
  Future<dynamic> _postResilient(
    String path, {
    required Map<String, dynamic> body,
    String? idempotencyKey,
    Duration timeout = _kColdStartTimeout,
  }) async {
    await warmUp(timeout: timeout);
    final urls = <String>{
      '$_baseUrl$path',
      '$kProductionBaseUrl$path',
    }.toList();

    Object? lastError;
    for (final urlStr in urls) {
      try {
        final res = await _client
            .post(
              Uri.parse(urlStr),
              headers: _headers(idempotencyKey: idempotencyKey),
              body: jsonEncode(body),
            )
            .timeout(timeout);
        _isWarm = true;
        return _check(res);
      } on ApiException {
        rethrow; // a real backend error — don't mask it by retrying blindly
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ??
        Exception('Could not reach the GridShare server. Please try again.');
  }

  /// GET variant of [_postResilient].
  Future<dynamic> _getResilient(
    String path, {
    Duration timeout = _kWarmTimeout,
  }) async {
    final urls = <String>{
      '$_baseUrl$path',
      '$kProductionBaseUrl$path',
    }.toList();

    Object? lastError;
    for (final urlStr in urls) {
      try {
        final res = await _client
            .get(Uri.parse(urlStr), headers: _headers())
            .timeout(timeout);
        _isWarm = true;
        return _check(res);
      } on ApiException {
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ??
        Exception('Could not reach the GridShare server. Please try again.');
  }

  // ============================ AUTH ============================

  /// POST /api/auth/send-otp — Send OTP to phone number.
  Future<AuthResponse> sendOtp({
    required String phone,
    String? idempotencyKey,
  }) async {
    final urls = [
      '$_baseUrl/api/auth/send-otp',
      if (!_baseUrl.contains('gridshare-production.up.railway.app'))
        'https://gridshare-production.up.railway.app/api/auth/send-otp',
    ];

    Object? lastError;
    for (final urlStr in urls) {
      try {
        final res = await _client
            .post(
              Uri.parse(urlStr),
              headers: _headers(idempotencyKey: idempotencyKey),
              body: jsonEncode({'phone': phone}),
            )
            .timeout(const Duration(seconds: 15));
        return AuthResponse.fromJson(_check(res));
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Failed to send OTP.');
  }

  /// POST /api/auth/verify-otp — Verify OTP and return JWT + user.
  Future<AuthResponse> verifyOtp({
    required String phone,
    required String otp,
    String? idempotencyKey,
  }) async {
    final urls = [
      '$_baseUrl/api/auth/verify-otp',
      if (!_baseUrl.contains('gridshare-production.up.railway.app'))
        'https://gridshare-production.up.railway.app/api/auth/verify-otp',
    ];

    Object? lastError;
    for (final urlStr in urls) {
      try {
        final res = await _client
            .post(
              Uri.parse(urlStr),
              headers: _headers(idempotencyKey: idempotencyKey),
              body: jsonEncode({'phone': phone, 'otp': otp}),
            )
            .timeout(const Duration(seconds: 15));
        return AuthResponse.fromJson(_check(res));
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Failed to verify OTP.');
  }

  // ============================ WALLET ============================

  /// POST /wallet/topup/instamojo — Create Instamojo payment request for UPI top-up.
  Future<InstamojoOrder> createInstamojoOrder({
    required int amountCredits,
    required String userId,
    String? phone,
    String? name,
    String? email,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/wallet/topup/instamojo'),
      headers: _headers(),
      body: jsonEncode({
        'userId': userId,
        'amountCredits': amountCredits,
        'phone': phone ?? '',
        'name': name ?? '',
        'email': email ?? '',
      }),
    );
    final data = _check(res);
    return InstamojoOrder.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /wallet/topup/instamojo/verify — Verify Instamojo payment and mint credits.
  Future<bool> verifyInstamojoPayment({
    required String paymentRequestId,
    required String paymentId,
    required String userId,
    required int amountCredits,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/wallet/topup/instamojo/verify'),
      headers: _headers(),
      body: jsonEncode({
        'paymentRequestId': paymentRequestId,
        'paymentId': paymentId,
        'userId': userId,
        'amountCredits': amountCredits,
      }),
    );
    final data = _check(res);
    return data['data']?['verified'] == true;
  }

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

  /// POST /wallet/topup/verify — Verify a Razorpay Checkout payment and mint
  /// credits. The backend re-checks the signature AND re-fetches the payment
  /// amount from Razorpay, so the client cannot forge or inflate a top-up.
  /// Returns the new wallet balance (credits).
  Future<int> verifyTopUp({
    required String orderId,
    required String paymentId,
    required String signature,
    required String userId,
    required int amountCredits,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl/wallet/topup/verify'),
      headers: _headers(),
      body: jsonEncode({
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
        'userId': userId,
        'amountCredits': amountCredits,
      }),
    );
    final body = _check(res);
    final data = (body['data'] as Map<String, dynamic>?) ?? const {};
    if (data['verified'] != true) {
      throw ApiException(
          code: 'VERIFICATION_FAILED',
          message: 'Payment could not be verified.',
          statusCode: res.statusCode);
    }
    return (data['balanceCredits'] as num?)?.toInt() ?? 0;
  }

  /// GET /wallet/:userId/balance — Current credit balance from contract.
  Future<WalletBalance> getBalance({required String userId}) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/wallet/$userId/balance'),
      headers: _headers(),
    );
    final body = _check(res);
    // Backend wraps response in { ok: true, data: { userId, balanceCredits } }
    final data =
        (body['data'] as Map<String, dynamic>?) ?? body as Map<String, dynamic>;
    return WalletBalance.fromJson(data);
  }

  /// GET /fx/usd-inr — Live USD→INR exchange rate (cached on backend).
  Future<FxRate> getFxRate() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/fx/usd-inr'),
      headers: _headers(),
    );
    final data = _check(res);
    return FxRate.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /wallet/topup/usdc — Create a USDC deposit intent.
  /// Returns memo + deposit address + SEP-0007 QR URI.
  Future<UsdcIntent> createUsdcIntent({
    required String userId,
    required int amountCredits,
    String assetCode = 'XLM',
  }) async {
    final data = await _postResilient('/wallet/topup/usdc', body: {
      'userId': userId,
      'amountCredits': amountCredits,
      'assetCode': assetCode,
    });
    return UsdcIntent.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// GET /wallet/topup/usdc/:memo — Poll intent status (pending → confirmed).
  Future<UsdcIntentStatus> pollUsdcIntent({required String memo}) async {
    final data = await _getResilient('/wallet/topup/usdc/$memo',
        timeout: const Duration(seconds: 15));
    return UsdcIntentStatus.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// POST /wallet/topup/usdc/:memo/verify — Actively verify & confirm USDC payment.
  /// NOTE: Horizon testnet can take 8-15s to respond, so we allow a long timeout.
  Future<UsdcIntentStatus> verifyUsdcIntent({required String memo}) async {
    final data = await _postResilient(
      '/wallet/topup/usdc/$memo/verify',
      body: const {},
      timeout: const Duration(seconds: 45),
    );
    return UsdcIntentStatus.fromJson(data['data'] as Map<String, dynamic>);
  }

  /// GET /wallet/:userId/source-ledger — UPI vs USDC earnings buckets.
  Future<HostSourceLedger> getSourceLedger({required String userId}) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/wallet/$userId/source-ledger'),
      headers: _headers(),
    );
    final data = _check(res);
    return HostSourceLedger.fromJson(data['data'] as Map<String, dynamic>);
  }

  // ============================ SESSIONS ============================

  /// POST /sessions/intent — Register intent to charge (status: created).
  /// Requires rider to have sufficient wallet balance for deposit (checked at start).
  Future<Session> createIntent({
    required String riderId,
    required String hostId,
    required String outletId,
    required int depositCredits,
    int? ratePerMinuteCredits,
    int? selectedDurationMinutes,
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
        // Per-minute billing (omitted → backend falls back to energy billing).
        if (ratePerMinuteCredits != null)
          'ratePerMinuteCredits': ratePerMinuteCredits,
        if (selectedDurationMinutes != null)
          'selectedDurationMinutes': selectedDurationMinutes,
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
      queryParameters: {
        'lat': lat.toString(),
        'lng': lng.toString(),
        'radiusKm': radiusKm.toString()
      },
    );
    final res = await _client.get(uri, headers: _headers());
    final data = _check(res);
    return (data['outlets'] as List).map((e) => Outlet.fromJson(e)).toList();
  }

  /// POST /outlets — Register dynamic IoT Smart Plug charger from mobile app.
  Future<Outlet> addOutlet({
    required String name,
    required String providerDeviceId,
    required double ratePerKwh,
    String? address,
    String? connectorType,
    double? lat,
    double? lng,
  }) async {
    final data = await _postResilient('/outlets', body: {
      'name': name,
      'providerDeviceId': providerDeviceId,
      'ratePerKwh': ratePerKwh,
      'address': address ?? 'Host Registered Station',
      'connectorType': connectorType ?? '16A Socket',
      'lat': lat ?? 19.0760,
      'lng': lng ?? 72.8777,
    });
    return Outlet.fromJson(data['data']['outlet'] as Map<String, dynamic>);
  }

  // ============================ ADMIN / HOST ============================

  /// GET /admin/hosts/earnings — List all hosts with on-chain earned credits.
  Future<List<HostEarnings>> getHostEarnings() async {
    final res = await _client.get(
      Uri.parse('$_baseUrl/admin/hosts/earnings'),
      headers: _headers(),
    );
    final data = _check(res);
    return (data['hosts'] as List)
        .map((e) => HostEarnings.fromJson(e))
        .toList();
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

  /// Generic POST request for custom endpoints (e.g., Clerk token exchange / Google sign-in)
  Future<Map<String, dynamic>> post({
    required String path,
    required Map<String, dynamic> body,
    String? idempotencyKey,
  }) async {
    final urls = [
      '$_baseUrl$path',
      if (!_baseUrl.contains('gridshare-production.up.railway.app'))
        'https://gridshare-production.up.railway.app$path',
    ];

    Object? lastError;
    for (final urlStr in urls) {
      try {
        final res = await _client
            .post(
              Uri.parse(urlStr),
              headers: _headers(idempotencyKey: idempotencyKey),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));
        return _check(res) as Map<String, dynamic>;
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('Failed request to $path.');
  }
}

/// Typed exception carrying backend error code + details.
class ApiException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;

  const ApiException(
      {required this.code,
      required this.message,
      required this.statusCode,
      this.details});

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

  AuthResponse(
      {this.accessToken,
      this.refreshToken,
      this.user,
      this.otpSent = false,
      this.message});

  factory AuthResponse.fromJson(Map<String, dynamic> j) => AuthResponse(
        accessToken: j['accessToken'] as String?,
        refreshToken: j['refreshToken'] as String?,
        user: j['user'] != null
            ? User.fromJson(j['user'] as Map<String, dynamic>)
            : null,
        otpSent: j['otpSent'] as bool? ?? false,
        message: j['message'] as String?,
      );
}

class TopUpOrder {
  final String orderId;
  final int amountCredits;
  final String currency;
  final String keyId; // Razorpay key_id for checkout

  TopUpOrder(
      {required this.orderId,
      required this.amountCredits,
      required this.currency,
      required this.keyId});

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

  const SessionStartResponse(
      {required this.session, required this.chain, required this.hardware});

  factory SessionStartResponse.fromJson(Map<String, dynamic> j) =>
      SessionStartResponse(
        session: Session.fromJson(j['session'] as Map<String, dynamic>),
        chain: j['chain'] as Map<String, dynamic>,
        hardware:
            HardwareCommand.fromJson(j['hardware'] as Map<String, dynamic>),
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
            ? SettlementPreview.fromJson(
                j['settlementPreview'] as Map<String, dynamic>)
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

  factory SettlementPreview.fromJson(Map<String, dynamic> j) =>
      SettlementPreview(
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

  factory SessionStopResponse.fromJson(Map<String, dynamic> j) =>
      SessionStopResponse(
        session: Session.fromJson(j['session'] as Map<String, dynamic>),
        telemetry: j['telemetry'] != null
            ? Telemetry.fromJson(j['telemetry'] as Map<String, dynamic>)
            : null,
        settlement: j['settlement'] != null
            ? SettlementPreview.fromJson(
                j['settlement'] as Map<String, dynamic>)
            : null,
        chain: j['chain'] as Map<String, dynamic>,
        hardware: j['hardware'] != null
            ? HardwareCommand.fromJson(j['hardware'] as Map<String, dynamic>)
            : null,
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
        telemetry: (j['telemetry'] as List)
            .map((e) => Telemetry.fromJson(e as Map<String, dynamic>))
            .toList(),
        contract: j['contract'] as Map<String, dynamic>?,
        hardwareCommands: (j['hardwareCommands'] as List? ?? [])
            .map((e) => HardwareCommand.fromJson(e as Map<String, dynamic>))
            .toList(),
        events: (j['events'] as List? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList(),
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
        periodStart: j['periodStart'] != null
            ? DateTime.parse(j['periodStart'] as String)
            : null,
        periodEnd: j['periodEnd'] != null
            ? DateTime.parse(j['periodEnd'] as String)
            : null,
        createdAt: DateTime.parse(j['createdAt'] as String),
        paidAt:
            j['paidAt'] != null ? DateTime.parse(j['paidAt'] as String) : null,
      );
}

class BalanceResponse {
  final String userId;
  final int balanceCredits;

  const BalanceResponse({required this.userId, required this.balanceCredits});

  factory BalanceResponse.fromJson(Map<String, dynamic> j) => BalanceResponse(
        userId: j['userId'] as String? ?? '',
        balanceCredits: (j['balanceCredits'] as num?)?.toInt() ?? 0,
      );
}

// ── USDC top-up models ─────────────────────────────────────────────────────

/// Live USD→INR rate returned by GET /fx/usd-inr.
class FxRate {
  final double rate;
  final String source; // 'live' | 'cache' | 'stale-cache' | 'fallback'
  final String? fetchedAt;

  const FxRate({required this.rate, required this.source, this.fetchedAt});

  factory FxRate.fromJson(Map<String, dynamic> j) => FxRate(
        rate: (j['rate'] as num?)?.toDouble() ?? 95.0,
        source: j['source'] as String? ?? 'live',
        fetchedAt: j['fetchedAt'] as String?,
      );
}

/// USDC deposit intent returned by POST /wallet/topup/usdc.
class UsdcIntent {
  final String memo;
  final String depositAddress;
  final String assetCode;
  final String assetIssuer;
  final String assetType;
  final double expectedUsdc;
  final int amountCredits;
  final double lockedRate;
  final String qrUri; // SEP-0007 web+stellar:pay URI
  final int expiresInSeconds;

  const UsdcIntent({
    required this.memo,
    required this.depositAddress,
    required this.assetCode,
    required this.assetIssuer,
    required this.assetType,
    required this.expectedUsdc,
    required this.amountCredits,
    required this.lockedRate,
    required this.qrUri,
    required this.expiresInSeconds,
  });

  factory UsdcIntent.fromJson(Map<String, dynamic> j) => UsdcIntent(
        memo: j['memo'] as String? ?? '',
        depositAddress: j['depositAddress'] as String? ?? '',
        assetCode: j['assetCode'] as String? ?? 'USDC',
        assetIssuer: j['assetIssuer'] as String? ?? '',
        assetType: j['assetType'] as String? ?? 'credit_alphanum4',
        expectedUsdc: (j['expectedUsdc'] as num?)?.toDouble() ?? 0,
        amountCredits: (j['amountCredits'] as num?)?.toInt() ?? 0,
        lockedRate: (j['lockedRate'] as num?)?.toDouble() ?? 95,
        qrUri: j['qrUri'] as String? ?? j['depositAddress'] as String? ?? '',
        expiresInSeconds: (j['expiresInSeconds'] as num?)?.toInt() ?? 900,
      );
}

/// Polled intent status returned by GET /wallet/topup/usdc/:memo.
class UsdcIntentStatus {
  final String memo;
  final String status; // 'pending' | 'confirmed' | 'expired'
  final int amountCredits;
  final double expectedUsdc;
  final String assetCode;
  final String? txHash;

  const UsdcIntentStatus({
    required this.memo,
    required this.status,
    required this.amountCredits,
    required this.expectedUsdc,
    required this.assetCode,
    this.txHash,
  });

  factory UsdcIntentStatus.fromJson(Map<String, dynamic> j) => UsdcIntentStatus(
        memo: j['memo'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        amountCredits: (j['amountCredits'] as num?)?.toInt() ?? 0,
        expectedUsdc: (j['expectedUsdc'] as num?)?.toDouble() ?? 0,
        assetCode: j['assetCode'] as String? ?? 'USDC',
        txHash: j['txHash'] as String?,
      );

  bool get isConfirmed => status == 'confirmed';
  bool get isExpired => status == 'expired';
}

/// Source ledger buckets for a user — UPI vs USDC earnings.
class HostSourceLedger {
  final String userId;
  final int upi;
  final int usdc;

  const HostSourceLedger({
    required this.userId,
    required this.upi,
    required this.usdc,
  });

  factory HostSourceLedger.fromJson(Map<String, dynamic> j) => HostSourceLedger(
        userId: j['userId'] as String? ?? '',
        upi: (j['upi'] as num?)?.toInt() ?? 0,
        usdc: (j['usdc'] as num?)?.toInt() ?? 0,
      );

  int get total => upi + usdc;
}

class InstamojoOrder {
  final String paymentUrl;
  final String requestId;
  final int amountCredits;

  const InstamojoOrder({
    required this.paymentUrl,
    required this.requestId,
    required this.amountCredits,
  });

  factory InstamojoOrder.fromJson(Map<String, dynamic> j) => InstamojoOrder(
        paymentUrl: j['paymentUrl'] as String? ?? '',
        requestId: j['requestId'] as String? ?? '',
        amountCredits: (j['amountCredits'] as num?)?.toInt() ?? 0,
      );
}
