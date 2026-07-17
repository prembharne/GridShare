# Production Readiness Notes

The difficult core is now hardened for local MVP integration, but final production readiness still requires real infrastructure adapters and operational controls.

## Completed Locally

- Tested payment to escrow to hardware activation saga
- Idempotent webhook and stop handling
- Concurrent duplicate webhook protection
- Per-session mutation lock to prevent double settlement
- Safety-trip cutoff before settlement
- Settlement/refund math with compliance-safe invoice wording
- Optional Razorpay HMAC webhook verification
- Request body limits and invalid JSON handling
- Optional append-only JSONL event audit log
- HTTP contract for the moderate-side app and dashboard
- Bounded adapter retry wrappers for transient chain/hardware failures
- Session audit bundle for support and compliance review
- Reconciliation for escrow-lock failures and pending settlements

## Still Required Before Live Pilot

- Real Soroban smart contract and relayer adapter
- Real Stellar key custody, rotation, and signing policy
- Real Razorpay webhook event mapping and payment status verification
- Real Tuya Cloud command adapter with device acknowledgement tracking
- Postgres session ledger with transactions and unique constraints
- TimescaleDB telemetry storage
- Transactional outbox for events instead of local JSONL
- Queue/retry policy for chain, payment, payout, and hardware commands beyond the local bounded retry/reconciliation wrapper
- Structured logs, metrics, tracing, and alerting
- Auth and authorization around every rider/host/admin route
- Deployment hardening: TLS, CORS policy, secrets manager, backups, and load testing

## Adapter Replacement Rule

Do not let the frontend depend on mock internals. Keep the HTTP contract stable and replace adapters behind the saga boundary.



## Production Scaffolding Added

- Initial Postgres/Timescale/PostGIS schema
- Docker Compose for local database and Redis
- Security checklist
- Explicit user-input checklist for real provider integration
