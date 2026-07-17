import 'dart:async';
import 'dart:math';

import '../models/models.dart';

/// Mock backend. Each method mirrors a future REST/WebSocket call so the real
/// service can be dropped in without touching the UI.
///
/// Replace these with `http`/`web_socket_channel` calls to:
///   GET  /outlets/nearby      → MockOutletService.nearby
///   POST /sessions/intent     → MockSessionService.createIntent
///   (Razorpay webhook →) session.paid event
///   WS   /sessions/:id/telemetry → MockTelemetryService.stream
///   POST /sessions/:id/stop   → MockSessionService.stop

class MockOutletService {
  Future<List<Outlet>> nearby({double lat = 12.9716, double lng = 77.5946}) async {
    await Future.delayed(const Duration(milliseconds: 900)); // simulate network
    return [
      Outlet(
        id: 'outlet_1',
        name: 'Lakeview Plug',
        hostName: 'Host A',
        lat: 12.9716,
        lng: 77.5946,
        distanceKm: 0.8,
        ratePerKwh: 18,
        available: true,
        connectorType: '16A BIS Smart Plug',
      ),
      Outlet(
        id: 'outlet_2',
        name: 'Metro Station Charger',
        hostName: 'Host B',
        lat: 12.9784,
        lng: 77.6408,
        distanceKm: 1.2,
        ratePerKwh: 18,
        available: true,
        connectorType: 'Type-2 AC',
      ),
      Outlet(
        id: 'outlet_3',
        name: 'Mall Parking Bay 3',
        hostName: 'Host C',
        lat: 12.9352,
        lng: 77.6245,
        distanceKm: 2.1,
        ratePerKwh: 18,
        available: false,
        connectorType: 'CCS2',
      ),
    ];
  }
}

class MockSessionService {
  Future<Session> createIntent({
    required String outletId,
    required int depositCredits,
    required String riderId,
    required String hostId,
    String? idempotencyKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return Session(
      id: 'sess_${DateTime.now().microsecondsSinceEpoch}',
      outletId: outletId,
      status: SessionStatus.created,
      depositCredits: depositCredits,
      spentCredits: 0,
      energyKwh: 0,
      startedAt: null,
      settledAt: null,
    );
  }

  Future<Session> markPaid(Session s) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return Session(
      id: s.id,
      outletId: s.outletId,
      status: SessionStatus.active,
      depositCredits: s.depositCredits,
      spentCredits: 0,
      energyKwh: 0,
      startedAt: DateTime.now(),
      settledAt: null,
    );
  }

  Future<Session> activate(Session s) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Session(
      id: s.id,
      outletId: s.outletId,
      status: SessionStatus.active,
      depositCredits: s.depositCredits,
      spentCredits: 0,
      energyKwh: 0,
      startedAt: DateTime.now(),
      settledAt: null,
    );
  }

  Future<Session> stop(Session s) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Session(
      id: s.id,
      outletId: s.outletId,
      status: SessionStatus.settled,
      depositCredits: s.depositCredits,
      spentCredits: s.spentCredits ?? 0,
      energyKwh: s.energyKwh,
      startedAt: s.startedAt,
      settledAt: DateTime.now(),
    );
  }
}

/// Simulated telemetry stream — Tuya → TimescaleDB → WebSocket → this.
/// Emits ticks every ~1.5s with smoothly increasing spend.
class MockTelemetryService {
  Stream<Telemetry> stream(Session session) async* {
    final rnd = Random();
    int energyWh = 0;
    double temp = 28;
    while (energyWh < session.depositCredits * 1000 / 18) { // rough estimate
      await Future.delayed(const Duration(milliseconds: 1500));
      final tickWh = 400 + rnd.nextInt(500); // 0.4-0.9 kWh per tick
      energyWh += tickWh;
      temp = 28 + rnd.nextDouble() * 6;
      yield Telemetry(
        energyWh: energyWh,
        currentAmp: 10 + rnd.nextDouble() * 4,
        voltageV: 228 + rnd.nextDouble() * 6,
        tempC: temp,
        sampledAt: DateTime.now(),
      );
      if (energyWh >= session.depositCredits * 1000) break;
    }
  }
}

class MockAuthService {
  Future<User> sendOtp(String phone) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return User(id: 'user_1', name: 'Rider', phone: phone, walletBalanceCredits: 120);
  }

  Future<User> verifyOtp(String phone, String otp) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return User(id: 'user_1', name: 'Rider', phone: phone, walletBalanceCredits: 120);
  }
}