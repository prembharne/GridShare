# Phase 6 — End-to-End Test with a Real Wipro/Tuya Plug

This is the runbook for the final phase of the per-minute IoT workflow: proving
the full charging lifecycle against a **physical** smart plug, not a mock. It
verifies that a rider's per-minute session actually switches the plug ON, streams
live telemetry, auto/user-stops, switches the plug OFF, and settles credits with
the conservation invariant intact.

The automated harness lives at [`scripts/e2e-real-plug.js`](../scripts/e2e-real-plug.js)
and is run with:

```bash
npm run e2e:plug
```

> It is intentionally **not** part of `npm test` — the unit suite must stay
> hardware-free and deterministic. Run this manually with a plug connected.

---

## 1. Prerequisites (one-time)

### Tuya Cloud project
1. Create a Cloud project in the [Tuya IoT console](https://iot.tuya.com/).
2. **Link App Account** → link the Smart Life account that owns the Wipro plug.
3. Subscribe the project to the **Device Status Notification** + **Device Control** APIs.
4. Copy the project's **Client ID** and **Client Secret**.
5. In *Devices*, copy the plug's **Device ID**.
6. Confirm the data-point (DP) codes in *Device → Debug* match what the bridge
   parses (Wipro 16A plug):

   | Meaning        | DP code       | Scaling            |
   |----------------|---------------|--------------------|
   | Relay switch   | `switch_1`    | bool               |
   | Power          | `cur_power`   | deciwatts (÷10)    |
   | Current        | `cur_current` | mA (÷1000 → A)     |
   | Voltage        | `cur_voltage` | decivolts (÷10)    |
   | Energy (cum.)  | `add_ele`     | Wh                 |

   If your unit uses different codes, adjust `getLiveStatus()` /
   `parseTelemetry()` in `src/adapters/real-hardware-bridge.js`.

### Data-center region
Pick the endpoint matching the linked account's region:
- India: `https://openapi.tuyain.com`
- China: `https://openapi.tuyacn.com` (default)
- Other DCs per Tuya docs.

---

## 2. Configure the server for real hardware

Set these in `.env` (or the process environment) before starting the server:

```bash
GRIDSHARE_USE_REAL_ADAPTERS=true

TUYA_CLIENT_ID=xxxxxxxx
TUYA_CLIENT_SECRET=xxxxxxxx
TUYA_ENDPOINT=https://openapi.tuyain.com
TUYA_DEVICE_ID=xxxxxxxxxxxxxxxx      # the plug you'll charge with

# Real adapters also require these (see src/config.js):
DATABASE_URL=postgres://...
SOROBAN_CONTRACT_ID=...
STELLAR_RELAYER_SECRET_KEY=...
RAZORPAY_KEY_ID=...
RAZORPAY_KEY_SECRET=...

# Optional: speed up the meter clock for a short test
GRIDSHARE_METER_INTERVAL_MS=5000
```

Per-outlet routing: the outlet you charge (`E2E_OUTLET_ID`) must resolve to the
plug's `providerDeviceId`. Register it via `POST /outlets` (host "Add Listing"
flow) with `providerDeviceId` set, or seed it so
`RealHardwareBridge.resolveDevice(outletId)` returns the right device. If it
can't resolve, it falls back to `TUYA_DEVICE_ID`, which is fine for a
single-plug test.

Start the server:

```bash
npm start
# → GridShare difficult core listening on http://localhost:8080
# → websocket: live dashboard stream at /ws
# → real adapters: true
```

---

## 3. Run the harness

With the plug **switched OFF** and idle:

```bash
# fast 1-minute run against the default outlet
npm run e2e:plug

# or fully parameterized
E2E_BASE_URL=http://localhost:8080 \
E2E_OUTLET_ID=outlet_1 \
E2E_RATE_PER_MIN=2 \
E2E_DURATION_MIN=1 \
E2E_OBSERVE_SEC=75 \
npm run e2e:plug
```

### What it checks

| Step | Endpoint | Assertion |
|------|----------|-----------|
| 1 | `GET /health` | server ready |
| 2 | `GET /outlets/:id/live` | plug reachable, starts OFF |
| 3 | `POST /sessions/intent` | per-minute intent, rate recorded |
| 4 | `POST /sessions/:id/start` | session `active`, deposit locked |
| 5 | `GET /outlets/:id/live` (poll) | **plug physically ON**, drawing power |
| 6 | `WS /ws?sessionId=…` | live meter/telemetry events received |
| 7 | `POST /sessions/:id/stop` | settlement returned |
| 8 | `GET /outlets/:id/live` | **plug physically OFF** |
| 9 | `GET /sessions/:id/audit` | `hostShare + serviceFee + refund === deposit` |

**During step 5 you should see the plug's LED/relay click ON** and a real load
(e.g. a lamp or charger) draw power. **During step 8 it clicks OFF.** That
physical confirmation is the point of Phase 6 — the software assertions ride
along with it.

The WebSocket observer (step 6) is a dependency-free RFC 6455 client. For a `wss`
(TLS) target it auto-skips; force-skip anywhere with `E2E_SKIP_WS=true`.

Exit code is `0` when every assertion passes, non-zero otherwise — so it can gate
a manual release checklist.

---

## 4. Auto-stop variants

- **Timer auto-stop:** set `E2E_DURATION_MIN=1` and `E2E_OBSERVE_SEC=90`. The
  `SessionMeter` clock stops the session at ~60s on its own; the plug goes OFF
  before step 7 even runs, and the stop call is idempotent.
- **Threshold auto-stop:** set `E2E_DEPOSIT` low (e.g. equal to one minute's
  charge) so accrued credits hit the deposit cap and trigger an auto-stop.

Both paths converge on the same settlement and the same conservation invariant.

---

## 5. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Step 2 → `501 NOT_IMPLEMENTED` | server running in mock mode | set `GRIDSHARE_USE_REAL_ADAPTERS=true` and restart |
| Step 2 → `HARDWARE_DEVICE_UNRESOLVED` | outlet has no device id | register outlet with `providerDeviceId` or set `TUYA_DEVICE_ID` |
| Token / 401 from Tuya | wrong client id/secret or DC region | verify creds and `TUYA_ENDPOINT` region |
| Plug never reports ON (step 5) | wrong `switch_1` DP code | confirm DP code in Tuya Debug, adjust bridge |
| No WS events (step 6) | meter interval too slow for the run | lower `GRIDSHARE_METER_INTERVAL_MS`, raise `E2E_OBSERVE_SEC` |
| Invariant fails (step 9) | settlement field names differ | check `settlement` shape from `stopSession`; harness reads `hostShareCredits/serviceFeeCredits/refundCredits` with fallbacks |

---

## 6. Sign-off

Phase 6 is complete when a single `npm run e2e:plug` run:
- prints `Phase 6 E2E: N passed, 0 failed`, **and**
- you visually confirmed the plug switched ON at start and OFF at stop.

Record the run (terminal output + a short clip of the plug toggling) alongside
the demo runbook as the hardware acceptance evidence.
