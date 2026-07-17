# GridShare Difficult-Core Integration Contract

This contract is intentionally stable for the moderate-side Android, web, auth, payment UI, and admin dashboard work.

## One-Button Judge Demo

`POST /demo/judge-flow` triggers the full demo story using the real saga underneath. Use it for a judge/demo button while the UI listens to `GET /events/stream`.

This endpoint is guarded by `GRIDSHARE_DEMO_MODE` and should be disabled outside demo environments.

## Session Intent

`POST /sessions/intent`

```json
{
  "riderId": "rider_001",
  "hostId": "host_001",
  "outletId": "outlet_001",
  "depositPaise": 5000,
  "idempotencyKey": "intent-rider_001-outlet_001-001"
}
```

Response:

```json
{
  "ok": true,
  "data": {
    "session": {
      "id": "sess_...",
      "status": "pending_payment",
      "depositPaise": 5000
    }
  }
}
```

## Payment Webhook

`POST /payments/webhook/razorpay`

This endpoint represents the hard part after Razorpay says the payment succeeded. It locks escrow first, then turns hardware on.

```json
{
  "sessionId": "sess_...",
  "paymentId": "pay_test_001",
  "amountPaise": 5000,
  "idempotencyKey": "pay_test_001"
}
```

Success response status becomes `active`. Duplicate webhooks with the same idempotency key return the same response and do not trigger duplicate hardware or chain commands.

If `RAZORPAY_WEBHOOK_SECRET` is configured, the request must include `x-razorpay-signature`. The signature is HMAC-SHA256 over the raw request body using the webhook secret. If the secret is empty, signature verification is skipped for local integration.

## Telemetry

`POST /sessions/{sessionId}/telemetry`

```json
{
  "energyWh": 1250,
  "currentAmp": 9.4,
  "voltageV": 231,
  "tempC": 41
}
```

Rules:

- `energyWh` is cumulative for the session.
- It must never decrease.
- Telemetry values must be finite numbers.
- If current/temp/voltage crosses safety limits, the plug is cut off before settlement.
- If computed usage reaches the prepaid deposit, the session auto-stops and settles.

## Manual Stop

`POST /sessions/{sessionId}/stop`

```json
{
  "reason": "user_stop",
  "idempotencyKey": "stop-sess-001"
}
```

Response includes final settlement:

```json
{
  "status": "settled",
  "settlement": {
    "amountDuePaise": 2250,
    "hostSharePaise": 2025,
    "platformFeePaise": 225,
    "refundPaise": 2750
  },
  "invoiceDescription": "Infrastructure Facility & Leasing Service Fee"
}
```

## Reconciliation

`POST /sessions/{sessionId}/reconcile` attempts to recover one stuck session. It currently handles:

- `paid` or `escrow_lock_failed`: retries escrow lock and hardware activation.
- `stopping`: retries final chain settlement using the stored pending settlement and oracle report.

`POST /reconcile` scans all recoverable sessions and returns per-session results. This is intended for admin/manual recovery or a future scheduled worker, not rider-facing UI.

## Session Audit

`GET /sessions/{sessionId}/audit` returns a full evidence bundle for support/admin/compliance screens: session state, telemetry, contract state, hardware commands, and event timeline.

Use this for admin drill-downs and demo judging. It is heavier than `GET /sessions/{sessionId}`, so the rider app should not poll it during live charging.

## Events

`GET /events` returns stored events. `GET /events/stream` streams them as SSE.

If `GRIDSHARE_EVENT_LOG_PATH` is configured, every published event is also written as one JSON object per line to that file.

Important event types:

- `session.intent_created`
- `payment.captured`
- `chain.escrow_locked`
- `hardware.switch_changed`
- `session.activated`
- `telemetry.received`
- `safety.trip`
- `session.auto_stop_threshold`
- `chain.session_settled`
- `session.settled`

The UI should use these for admin timelines and live charging status.

## Error Shape

All errors use the same response shape:

```json
{
  "ok": false,
  "error": {
    "code": "PAYLOAD_TOO_LARGE",
    "message": "Request body is too large."
  }
}
```



