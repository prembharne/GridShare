# GridShare IoT Workflow — Full Real Path (Per-Minute Billing)

Design blueprint for the end-to-end Tuya smart-plug charging flow with
per-minute credit settlement and real-time host/rider dashboards.

Status legend: ✅ already exists · 🟡 partial, needs change · 🔴 to build

---

## 1. Actors & goals

**Host**
- Add a new Tuya smart plug from their account. 🟡 (`/outlets` + `iot_config_screen` exist; needs real per-device binding)
- See real-time energy consumption + remaining time on dashboard. 🔴
- See sessions: who charged, how long, credits earned. 🟡 (`/admin/sessions` exists; needs host-scoped view)
- Earn credits to their GridShare wallet on settlement. ✅ (`completePendingSettlement` transfers host share)
- Receive weekly payouts via admin dashboard. ✅ (`/admin/hosts/:id/payout` + `confirm`)

**Rider**
- See nearby charging slots + book. 🟡 (`/outlets/nearby` + home map exist)
- Get directions to the slot. 🔴 (add maps deep-link)
- Top up via Freighter (XLM) → credits minted. ✅ (fixed today; SEP-0007 launch added)
- Charge using credits; **credits deducted per minute** rider→host. 🔴 (currently energy-based)

**Admin**
- Weekly payout release based on host credit balances. ✅

---

## 2. The core change: energy-based → per-minute billing

Today `settlement-math.js` computes `amountDue = energyWh * pricePerKwh / 1000`.
The new model bills **elapsed active minutes × ratePerMinuteCredits**, capped by
the rider's locked deposit.

New module `src/domain/time-settlement-math.js` (implemented in Phase 1):

```
billedMinutes   = ceil(activeSeconds / 60)              // partial minute rounds up
rawAmountDue    = billedMinutes * ratePerMinuteCredits
amountDue       = min(depositCredits, rawAmountDue)
serviceFee      = floor(amountDue * serviceFeeBps / 10000)
hostShare       = amountDue - serviceFee
refund          = depositCredits - amountDue
```

Invariant (unchanged): `hostShare + serviceFee + refund == depositCredits`.

`ratePerMinuteCredits` is derived from the outlet's `rate_per_kwh` and an assumed
plug power, OR set directly per outlet. Decision: store an explicit
`rate_per_minute_credits` on each outlet so hosts price by time.

---

## 3. Session lifecycle (per-minute)

```
intent  → start (lock deposit, Tuya switch_1=ON, record activeAt)
        → meter tick every 60s:
              elapsed = now - activeAt
              due     = elapsed_minutes * ratePerMinute
              if due >= deposit  → auto-stop (threshold)
              if now >= activeAt + selectedDurationMinutes → auto-stop (timer)
        → stop (Tuya switch_1=OFF, settle by minutes, refund remainder)
```

Changes to `session-saga.js`:
- `createIntent` accepts `selectedDurationMinutes` (rider picks duration).
- `startSession` stamps `activeAt` (already does) and schedules the meter.
- New `tickSession(sessionId)` → recomputes time-based preview, auto-stops on
  timer or threshold. Driven by a scheduler (Phase 3).
- `stopAndSettle` uses `computeTimeSettlement` with `activeAt`/`stoppedAt`.

---

## 4. Per-outlet Tuya device binding

Today `RealHardwareBridge` is bound to ONE `TUYA_DEVICE_ID` from env. For hosts
to add their own plugs we need per-outlet device IDs.

- `outlets` table already stores `providerDeviceId` (postgres-store seeds it).
- Change `RealHardwareBridge.setSwitch/getDeviceStatus` to take the outlet's
  `providerDeviceId` instead of the single env device id. The saga already
  passes `outletId`; we resolve `outletId → providerDeviceId` via the store.
- New endpoint `GET /outlets/:id/live` → calls Tuya `/v1.0/devices/:devId/status`
  and returns normalized `{ switchOn, powerW, energyWh, currentA, voltageV }`.

**Tuya Cloud prerequisites (your side):**
1. Cloud project → *Link Tuya App Account* → link the Smart Life account that
   owns the Wipro plug.
2. Note the plug's **Device ID** (Tuya IoT console → Devices).
3. Ensure project has *Device Status Notification* + *Device Control* APIs
   subscribed.
4. Set env: `TUYA_CLIENT_ID`, `TUYA_CLIENT_SECRET`, `TUYA_ENDPOINT`
   (`https://openapi.tuyain.com` for India DC), and per-outlet device IDs stored
   at registration.

The Wipro 16A plug data-point codes (verify in console → Device → Debug):
`switch_1` (bool), `cur_power` (W ×10), `cur_current` (mA), `cur_voltage`
(V ×10), `add_ele` (kWh cumulative ×1000). Parser already handles most.

---

## 5. Real-time dashboards

Two options; recommended **WebSocket** since `web_socket_channel` is already a
mobile dependency and the backend can broadcast the existing `eventBus`.

- Backend: add a `/ws` endpoint that streams `telemetry.received`,
  `session.activated`, `session.settled`, and a new `session.tick` event.
- A **poller** (Phase 3) calls Tuya `/status` every ~10–15s per active outlet,
  feeds it through `ingestTelemetry` (which already publishes to eventBus), so
  dashboards update live without waiting on Tuya webhooks.
- Host dashboard subscribes filtered by `hostId`; rider charging screen by
  `sessionId`.

---

## 6. Phased delivery

| Phase | Scope | Files |
|-------|-------|-------|
| 1 ✅ now | Per-minute settlement math + tests | `time-settlement-math.js`, test |
| 2 | Per-outlet Tuya routing + `/outlets/:id/live` | `real-hardware-bridge.js`, `http-server.js`, store |
| 3 | Meter/scheduler: per-minute tick + timer auto-stop | `session-saga.js`, new `session-meter.js` |
| 4 | WebSocket broadcast of eventBus | `http-server.js`, new `ws-hub.js` |
| 5 ✅ | Mobile: duration picker, live host dashboard, rider directions | mobile `features/*` |
| 6 ✅ | End-to-end test with real Wipro plug | `scripts/e2e-real-plug.js`, `docs/phase6-real-plug-e2e.md` |


Each phase is independently testable and leaves the system runnable.

---

## 7. Open decisions

- **Pricing unit**: expose `rate_per_minute_credits` per outlet (recommended) vs.
  derive from `rate_per_kwh` × assumed kW. → default: explicit per-minute.
- **Tuya DC region**: India (`openapi.tuyain.com`) vs China (`tuyacn.com`). The
  linked Smart Life account's region must match.
- **Meter cadence**: 60s billing tick + 15s status poll for UI.
