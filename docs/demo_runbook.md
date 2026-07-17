# Judge Demo Runbook

This is the fastest safe way to show the full GridShare story while keeping the architecture production-shaped.

## Frontend Flow

1. Open an event stream:

```http
GET /events/stream
```

2. Trigger the full demo:

```http
POST /demo/judge-flow
Content-Type: application/json

{
  "demoId": "final_judge_demo",
  "outletId": "outlet_stage_1",
  "stepDelayMs": 500
}
```

3. Animate the UI from events.

Important event types for the demo screen:

- `demo.started`
- `session.intent_created`
- `payment.captured`
- `chain.escrow_locked`
- `hardware.switch_changed`
- `session.activated`
- `telemetry.received`
- `safety.trip`
- `chain.session_settled`
- `session.settled`
- `demo.completed`

## What The Demo Proves

The demo endpoint calls the same hard-core saga methods used by normal integration:

- creates session intent
- captures mock payment
- locks mock escrow
- turns mock hardware on
- streams normal telemetry
- sends unsafe telemetry spike
- cuts hardware off
- settles session
- calculates host/platform/refund split
- returns audit bundle

## Response Shape

```json
{
  "ok": true,
  "data": {
    "summary": {
      "demoId": "final_judge_demo",
      "sessionId": "sess_...",
      "finalStatus": "settled",
      "settlement": {
        "amountDuePaise": 2700,
        "platformFeePaise": 270,
        "hostSharePaise": 2430,
        "refundPaise": 2300
      },
      "invoiceDescription": "Infrastructure Facility & Leasing Service Fee"
    },
    "audit": {}
  }
}
```

## Safety Guard

Demo endpoints are controlled by:

```text
GRIDSHARE_DEMO_MODE=true
```

In production, set it to `false` or run with `NODE_ENV=production` and no explicit demo override.
