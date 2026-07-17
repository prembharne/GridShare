# GridShare Difficult Core

This package builds the difficult half from the planning files:

- Soroban-style escrow state machine through a swappable chain relayer adapter
- Payment to escrow to hardware activation saga
- Idempotency for webhook and stop operations, including concurrent duplicate webhook handling
- Per-session locks so telemetry, stop requests, and payment events cannot double-settle a session
- Telemetry ingestion with live event fan-out
- Safety-trip rule engine that cuts hardware before settlement
- Settlement math for host share, platform fee, and rider refund
- Compliance-safe invoice wording
- Optional Razorpay HMAC webhook verification
- Optional append-only JSONL event audit log
- Optional bounded retries for transient chain and hardware adapter failures
- Session audit bundle for support, judging, and compliance review
- Reconciliation paths for escrow-lock failures and pending settlements

It is dependency-free so it can run immediately in this workspace. The current chain and hardware adapters are deterministic mocks with the same boundaries the real Soroban/Tuya adapters should keep.

## Run

```powershell
npm.cmd test
npm.cmd run demo
npm.cmd start
```

The service starts on `http://localhost:8080` by default.

## Main Endpoints

- `GET /health`
- `GET /events`
- `GET /events/stream` for server-sent events
- `POST /demo/judge-flow` for the one-button judge demo flow
- `POST /sessions/intent`
- `POST /payments/webhook/razorpay`
- `POST /sessions/{sessionId}/telemetry`
- `POST /sessions/{sessionId}/stop`
- `GET /sessions/{sessionId}`
- `GET /sessions/{sessionId}/audit`
- `POST /sessions/{sessionId}/reconcile`
- `POST /reconcile`

See [docs/integration_contract.md](docs/integration_contract.md) for payloads your friend's frontend/backend work can integrate against.

## Production-Readiness Boundary

This is a hardened local core, not yet a live production deployment. It has the correct seams and tested behavior for the risky business flow. The remaining production work is to replace these adapters:

- `MockChainRelayer` -> Soroban/Stellar SDK relayer with real key custody and retry handling
- `MockHardwareBridge` -> Tuya Cloud/Pulsar bridge with real device command acknowledgements
- `InMemoryStore` -> Postgres plus TimescaleDB telemetry storage
- `JsonlEventSink` -> transactional database outbox/audit log

Keep the HTTP contract stable while replacing adapters.

## What Is Verified

The tests check the exact risks called out in `gridshare_difficulty_split.md`:

- no double activation on repeated payment webhooks
- no duplicate settlement under session races
- no idempotency key reuse with different payloads
- hardware turns on only after escrow lock
- hardware command failure refunds escrow instead of leaving a limbo session
- settlement math handles refund/host/platform split
- safety trip cuts the plug and then settles
- threshold auto-stop settles when prepaid amount is consumed
- bad telemetry is rejected before storage
- signed Razorpay webhooks are enforced when a secret is configured
- oversized HTTP payloads are rejected
- event log audit entries are written when configured
- transient chain and hardware failures recover through bounded retries
- audit endpoint returns session evidence bundle
- failed escrow locks and pending settlements can be reconciled safely
- invoice copy avoids forbidden electricity resale wording



## Production Scaffolding

Added production target files:

- `migrations/001_initial_schema.sql` for Postgres, TimescaleDB, and PostGIS
- `docker-compose.yml` for local Postgres/Redis infrastructure
- `ops/local_stack.md` for local infra notes
- `ops/security_checklist.md` for pre-pilot security checks
- `docs/inputs_needed.md` for exactly when user credentials/decisions are required

## Judge Demo Endpoint

For the frontend demo button, call:

```http
POST /demo/judge-flow
```

Then listen to `GET /events/stream` to show the flow step by step. See `docs/demo_runbook.md`.
