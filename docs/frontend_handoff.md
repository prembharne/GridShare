# Frontend Handoff

This is the minimum contract your friend needs for the demo UI.

## Start Backend

```powershell
npm.cmd start
```

Default URL:

```text
http://localhost:8080
```

## Recommended Demo Screen Flow

1. Open the event stream as soon as the demo screen loads.

```http
GET /events/stream
```

2. When the presenter taps the demo button, call:

```http
POST /demo/judge-flow
Content-Type: application/json

{
  "demoId": "judge_demo_1",
  "outletId": "stage_plug_1",
  "stepDelayMs": 500
}
```

3. Render UI states from event types.

## Event To UI Mapping

| Event | UI State |
|---|---|
| `demo.started` | Reset demo timeline |
| `session.intent_created` | Show session created / QR scanned |
| `payment.captured` | Show payment success |
| `chain.escrow_locked` | Show escrow locked on Stellar |
| `hardware.switch_changed` with `desiredState: true` | Show plug ON |
| `telemetry.received` | Update live charging meter |
| `safety.trip` | Show safety alert |
| `hardware.switch_changed` with `desiredState: false` | Show plug OFF |
| `chain.session_settled` | Show settlement tx |
| `session.settled` | Show receipt/refund |
| `demo.completed` | Show final audit-ready state |

## Admin/Audit View

For a selected session:

```http
GET /sessions/{sessionId}/audit
```

Use this to show evidence: session state, telemetry, contract state, hardware commands, and event timeline.

## Important Demo Guard

The one-button endpoint works only when:

```text
GRIDSHARE_DEMO_MODE=true
```

For real production, set it to false.
