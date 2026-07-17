# GridShare Mobile — Premium 2.5D UI (Flutter)

A beautiful, smooth, dark-mode-first mobile UI for **GridShare** — a DePIN EV
charging network. Built in **Flutter** so it runs on **Android + iOS** from a
single codebase, with **2.5D motion** via custom **shaders** + a Rive-ready
hero animation.

> This repo covers the **Moderate / client** slice. The backend (Soroban
> contract, Chain Relayer, Safety-Trip engine, telemetry pipeline, payments
> saga) is built by the other teammate and is mocked here behind clean DTO
> contracts, so swapping in real APIs touches only the service layer.

## What's inside

| Area | Notes |
|---|---|
| Design system | `lib/core/theme` — tokens (`#0B0E11` base, `#39FF88` accent), 4px grid, radii, typography. Mirrors the web dashboard's tokens. |
| 2.5D motion | `lib/core/shaders` — GLSL `.frag` files (aurora, ripple, pulse) + a reusable `ShaderCanvas`. Rive hero is wired (`EnergyFlow2_5D`) and degrades to the shader if `.riv` is absent. |
| Smooth counter | `AnimatedCounter` interpolates between telemetry ticks (no janky jumps). |
| Screens | Auth (phone→OTP), Home (stylized map + pins + bottom sheet), Scan (QR), Payment (UPI amount picker), **Charging hero** (ring + orb + live ₹ counter + safety-trip alert), Profile. |
| States | Loading skeletons, empty / error / offline views, and the red-only **Safety Trip** banner. |
| Mock data | `lib/data` — DTOs match the backend's `GET /outlets/nearby`, `POST /sessions/intent`, telemetry WS, etc. |

## Run it

```bash
flutter pub get
flutter analyze          # should be clean
flutter run              # iOS sim / Android emulator
```

Minimum SDK: Flutter ≥ 3.19, Dart ≥ 3.3.

## Where the real backend plugs in

Replace the bodies in `lib/data/services/mock_services.dart` with `http` /
`web_socket_channel` calls — the screen layer depends only on the DTOs in
`lib/data/models/models.dart`, so nothing else changes.

- `GET  /outlets/nearby`         → `MockOutletService.nearby`
- `POST /sessions/intent`        → `MockSessionService.createIntent`
- Razorpay webhook → `session.paid` → `markPaid`
- `WS   /sessions/:id/telemetry` → `MockTelemetryService.stream`
- `POST /sessions/:id/stop`      → `MockSessionService.stop`

## Upgrading to real 3D / Rive

1. Drop `energy.riv` into `assets/rive/`.
2. In `lib/features/charging/energy_flow.dart` set `EnergyFlow2_5D._useRive = true`
   and bind a Rive StateMachine input `charge` to the session progress.

## Compliance note

Invoicing language is centralized in `lib/core/utils/currency.dart` and never
says "electricity" — it bills the **Infrastructure Facility & Leasing Service
Fee**, consistent across mobile, web, and PDF receipts.
