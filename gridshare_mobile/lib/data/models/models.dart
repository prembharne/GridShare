/// Core domain models shared by UI. DTOs for API responses live in `api_service.dart`.
library;

export '../services/api_service.dart'
    show
        ApiException,
        TopUpOrder,
        WalletBalance,
        SessionStartResponse,
        TelemetryResult,
        SettlementPreview,
        SessionStopResponse,
        SessionAudit,
        HardwareCommand,
        HostEarnings,
        HostPayout,
        BalanceResponse,
        FxRate,
        UsdcIntent,
        UsdcIntentStatus,
        HostSourceLedger;

class Outlet {
  final String id;
  final String name;
  final String hostName;
  final double lat;
  final double lng;
  final double distanceKm;
  final double ratePerKwh; // billed as service fee, not electricity (credits/kWh)
  final bool available;
  final String? connectorType; // e.g. "16A BIS Smart Plug"
  final double rating;

  const Outlet({
    required this.id,
    required this.name,
    required this.hostName,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.ratePerKwh,
    required this.available,
    this.connectorType,
    this.rating = 4.8,
  });

  factory Outlet.fromJson(Map<String, dynamic> j) => Outlet(
        id: j['id'],
        name: j['name'],
        hostName: j['host_name'],
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        distanceKm: (j['distance_km'] as num).toDouble(),
        ratePerKwh: (j['rate_per_kwh'] as num).toDouble(),
        available: j['available'] as bool,
        connectorType: j['connector_type'],
        rating: (j['rating'] as num?)?.toDouble() ?? 4.8,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host_name': hostName,
        'lat': lat,
        'lng': lng,
        'distance_km': distanceKm,
        'rate_per_kwh': ratePerKwh,
        'available': available,
        'connector_type': connectorType,
        'rating': rating,
      };
}

enum SessionStatus { pending, created, active, stopping, settled, cancelled, tripped, lock_failed, refunded_after_activation_failure }

extension SessionStatusX on SessionStatus {
  String get label {
    switch (this) {
      case SessionStatus.pending:
        return 'Awaiting payment';
      case SessionStatus.created:
        return 'Session created';
      case SessionStatus.active:
        return 'Charging';
      case SessionStatus.stopping:
        return 'Settling…';
      case SessionStatus.settled:
        return 'Settled';
      case SessionStatus.cancelled:
        return 'Cancelled';
      case SessionStatus.tripped:
        return 'Safety trip';
      case SessionStatus.lock_failed:
        return 'Lock failed';
      case SessionStatus.refunded_after_activation_failure:
        return 'Refunded (activation failed)';
    }
  }

  bool get isLive => this == SessionStatus.active;
}

/// Session in the wallet credit model.
/// 1 credit = 1 INR. Deposit is locked at start, settled at end.
class Session {
  final String id;
  final String outletId;
  final SessionStatus status;
  final int depositCredits;       // credits locked at session start
  final int? spentCredits;        // credits consumed so far (from telemetry)
  final double? energyKwh;        // energy delivered so far
  final DateTime? startedAt;      // when hardware turned ON
  final DateTime? settledAt;      // when settled on-chain

  const Session({
    required this.id,
    required this.outletId,
    required this.status,
    required this.depositCredits,
    this.spentCredits,
    this.energyKwh,
    this.startedAt,
    this.settledAt,
  });

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        outletId: j['outletId'] as String,
        status: SessionStatus.values.firstWhere(
          (e) => e.name == (j['status'] as String).toLowerCase(),
          orElse: () => SessionStatus.pending,
        ),
        depositCredits: (j['depositCredits'] as num?)?.toInt() ?? (j['prepaidAmount'] as num?)?.toInt() ?? 0,
        spentCredits: (j['spentCredits'] as num?)?.toInt() ?? (j['spent'] as num?)?.toInt(),
        energyKwh: (j['energyKwh'] as num?)?.toDouble() ?? (j['energy'] as num?)?.toDouble(),
        startedAt: j['startedAt'] != null ? DateTime.parse(j['startedAt'] as String) : null,
        settledAt: j['settledAt'] != null ? DateTime.parse(j['settledAt'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'outletId': outletId,
        'status': status.name,
        'depositCredits': depositCredits,
        'spentCredits': spentCredits,
        'energyKwh': energyKwh,
        'startedAt': startedAt?.toIso8601String(),
        'settledAt': settledAt?.toIso8601String(),
      };

  /// Back-compat for old UI code
  double get prepaidAmount => depositCredits.toDouble();
  double get spent => (spentCredits ?? 0).toDouble();
  DateTime get startedAtOrNow => startedAt ?? DateTime.now();
  double get progress => depositCredits > 0 ? (spentCredits ?? 0) / depositCredits : 0.0;
}

/// Telemetry from IoT device (Tuya smart plug → TimescaleDB).
/// Field names match backend: energyWh, currentAmp, voltageV, tempC.
class Telemetry {
  final int energyWh;      // cumulative energy in Wh
  final double currentAmp; // instantaneous current in A
  final double voltageV;   // instantaneous voltage in V
  final double tempC;      // temperature in °C
  final DateTime sampledAt;

  const Telemetry({
    required this.energyWh,
    required this.currentAmp,
    required this.voltageV,
    required this.tempC,
    required this.sampledAt,
  });

  factory Telemetry.fromJson(Map<String, dynamic> j) {
    // Accept both snake_case (backend) and camelCase (legacy)
    final energyWh = (j['energyWh'] as num?)?.toInt() ?? (j['energy_wh'] as num?)?.toInt() ?? 0;
    final currentAmp = (j['currentAmp'] as num?)?.toDouble() ?? (j['current_amp'] as num?)?.toDouble() ?? (j['current'] as num?)?.toDouble() ?? 0;
    final voltageV = (j['voltageV'] as num?)?.toDouble() ?? (j['voltage_v'] as num?)?.toDouble() ?? (j['voltage'] as num?)?.toDouble() ?? 0;
    final tempC = (j['tempC'] as num?)?.toDouble() ?? (j['temp_c'] as num?)?.toDouble() ?? (j['temp'] as num?)?.toDouble() ?? 0;
    final sampledAt = DateTime.tryParse(j['sampledAt'] as String? ?? j['sampled_at'] as String? ?? j['ts'] as String? ?? '') ?? DateTime.now();

    return Telemetry(
      energyWh: energyWh,
      currentAmp: currentAmp,
      voltageV: voltageV,
      tempC: tempC,
      sampledAt: sampledAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'energyWh': energyWh,
        'currentAmp': currentAmp,
        'voltageV': voltageV,
        'tempC': tempC,
        'sampledAt': sampledAt.toIso8601String(),
      };

  double get energyKwh => energyWh / 1000;
}

class User {
  final String id;
  final String name;
  final String phone;
  final int walletBalanceCredits; // 1 credit = 1 INR

  const User({
    required this.id,
    required this.name,
    required this.phone,
    this.walletBalanceCredits = 0,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        walletBalanceCredits: (j['walletBalanceCredits'] as num?)?.toInt() ?? (j['balanceCredits'] as num?)?.toInt() ?? (j['walletBalance'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'walletBalanceCredits': walletBalanceCredits,
      };

  double get walletBalanceInr => walletBalanceCredits.toDouble();

  User copyWith({String? id, String? name, String? phone, int? walletBalanceCredits}) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      walletBalanceCredits: walletBalanceCredits ?? this.walletBalanceCredits,
    );
  }
}