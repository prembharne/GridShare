# GridShare ⚡

**Peer-to-peer EV charging on a decentralized physical infrastructure (DePIN) rail.**
Hosts share their smart plugs; riders pay per-kWh or per-minute in on-ledger credits
settled on Stellar/Soroban. A hardened Node.js core orchestrates the risky
payment → escrow → hardware → settlement saga, and a premium Flutter app is the
rider/host client.

<p align="left">
  <img alt="Node" src="https://img.shields.io/badge/node-%3E%3D18-339933?logo=node.js&logoColor=white" />
  <img alt="Flutter" src="https://img.shields.io/badge/flutter-3.19%2B-02569B?logo=flutter&logoColor=white" />
  <img alt="Stellar" src="https://img.shields.io/badge/settlement-Stellar%2FSoroban-000?logo=stellar&logoColor=white" />
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue" />
</p>

---

## Table of contents

- [Why GridShare](#why-gridshare)
- [Architecture](#architecture)
- [Payment rails](#payment-rails)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [HTTP API](#http-api)
- [Wallet top-up flow (Razorpay UPI)](#wallet-top-up-flow-razorpay-upi)
- [Mobile app](#mobile-app)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Roadmap](#roadmap)
- [License](#license)

---

## Why GridShare

Public EV charging is sparse, while millions of homes and shops already have a
16A socket sitting idle. GridShare turns any smart plug into a monetizable
charge point:

- **Hosts** list a Tuya-compatible smart plug and earn credits per session.
- **Riders** discover nearby plugs, prepay into escrow, charge, and are refunded
  the unused balance automatically.
- **Settlement** is on-ledger (Stellar/Soroban), so host earnings and platform
  fees are transparent and auditable.

The hard part is not the UI — it is guaranteeing that *money moves exactly once*,
*hardware turns on only after funds are escrowed*, and *a failure anywhere
refunds instead of stranding funds or energy*. That correctness core is the
heart of this repository.

## Architecture

```
                 ┌──────────────────────────┐
   Flutter app   │      HTTP / SSE API       │   Admin dashboard
  (rider/host) ──▶  src/http-server.js       ◀── (users, hosts, sessions)
                 └───────────┬──────────────┘
                             │
                   ┌─────────▼──────────┐
                   │   SessionSaga      │  escrow → activate → settle
                   │  domain/*.js       │  idempotency + per-session locks
                   └───┬───────┬────┬───┘
        chain relayer  │       │    │  hardware bridge
        (Stellar/      │       │    │  (Tuya Cloud)
         Soroban)      ▼       ▼    ▼
                  ┌────────┐ ┌────┐ ┌────────────┐
                  │ chain  │ │store│ │  hardware  │
                  │ adapter│ │ +KV │ │  adapter   │
                  └────────┘ └────┘ └────────────┘
```

**Design principle — swappable adapters behind stable seams.** Every external
dependency (chain, hardware, payments, persistence) sits behind an adapter
interface. Mocks run the full flow in-process with zero external services; real
adapters (Soroban SDK, Tuya Cloud, Razorpay, Postgres) drop in without touching
the domain logic or the HTTP contract.

| Concern       | Mock adapter            | Production adapter               |
| ------------- | ----------------------- | -------------------------------- |
| Chain / ledger| `MockChainRelayer`      | `RealChainRelayer` (Stellar SDK) |
| Hardware      | `MockHardwareBridge`    | `RealHardwareBridge` (Tuya)      |
| Payments      | `RealPaymentAdapter`*   | Razorpay Orders + webhooks       |
| Persistence   | `InMemoryStore`         | `PostgresStore` (Prisma)         |
| Event audit   | `JsonlEventSink`        | DB outbox / audit log            |

`*` The payment adapter talks to Razorpay directly and is used in both modes;
mock mode ships with test keys so the flow is fully exercisable offline.

## Payment rails

GridShare supports three funding rails into the same idempotent
`topUpWallet` credit-minting path:

1. **Razorpay UPI (recommended)** — server creates a Razorpay **Order** bound to
   the `userId`; the app opens Razorpay Checkout; on success the backend
   re-verifies the signature, re-fetches the authoritative amount from Razorpay,
   and mints credits. The client is never trusted to self-report a payment.
2. **USDC / XLM on Stellar** — server issues a deposit intent (address + memo +
   SEP-0007 QR) at a locked FX rate; a Horizon watcher confirms the payment and
   mints credits idempotently on the tx hash.
3. **Instamojo UPI (legacy)** — hosted payment page + server-side verification.

> 1 credit = ₹1. Credits are the in-app unit of account; settlement to hosts is
> 1:1 INR off-ramp or on-ledger, depending on configuration.

## Repository layout

```
src/
  http-server.js        HTTP + SSE API surface (the stable contract)
  app.js                Composition root: wires adapters from config
  config.js             Env-driven configuration with validation
  domain/               Pure business logic (saga, settlement math, safety)
  adapters/             Chain, hardware, payment, persistence, SMS, FX, USDC
  core/                 Event bus, idempotency, locks, retry, hashing
  security/             Razorpay HMAC verification
gridshare_mobile/       Flutter app (rider + host client)
migrations/             Postgres / TimescaleDB / PostGIS schema
docs/                   Integration contract, runbooks, workflows
test/                   Node test suite for the correctness core
```

## Quick start

### Backend

```bash
npm install
npm test            # run the correctness suite
npm run demo        # scripted judge/demo flow
npm start           # serve on http://localhost:8080
```

By default the backend runs fully mocked — no database, chain, or hardware
required — so `npm start` gives you a working API immediately.

### Mobile app

```bash
cd gridshare_mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080   # emulator -> localhost
```

Release APKs default to the hosted backend so a physical phone works without
any `--dart-define`.

## Configuration

All configuration is environment-driven and validated at boot (`src/config.js`).
Key variables:

| Variable                     | Purpose                                   | Default            |
| ---------------------------- | ----------------------------------------- | ------------------ |
| `PORT`                       | HTTP port                                 | `8080`             |
| `GRIDSHARE_USE_REAL_ADAPTERS`| Use real chain/hardware/payment adapters  | `false`            |
| `GRIDSHARE_PERSIST`          | Persist to Postgres via Prisma            | `false`            |
| `DATABASE_URL`               | Postgres connection string                | –                  |
| `RAZORPAY_KEY_ID`            | Razorpay public key (safe to expose)      | test key           |
| `RAZORPAY_KEY_SECRET`        | Razorpay secret (server-only)             | test key           |
| `RAZORPAY_WEBHOOK_SECRET`    | HMAC secret for webhook verification      | –                  |
| `STELLAR_RPC_URL`            | Soroban RPC endpoint                      | –                  |
| `SOROBAN_CONTRACT_ID` | Soroban contract ID for GridShare escrow (mainnet) | `CAGOKMQMKALEIQFVVTQVLI7GLDC2PZDZGC2UZTZR4E3K74DDGWS3VZ7Q` |
| `ADMIN_API_KEY`              | Guards `/admin/*` endpoints               | open in dev        |

> **Never commit real secrets.** Set production keys as environment variables on
> your host (e.g. Render dashboard), not in source. The bundled Razorpay test
> keys are for local development only.

## HTTP API

| Method | Path                                | Description                          |
| ------ | ----------------------------------- | ------------------------------------ |
| GET    | `/health`                           | Liveness + adapter status            |
| POST   | `/api/auth/send-otp`                | Request phone OTP                    |
| POST   | `/api/auth/verify-otp`              | Verify OTP → user + token            |
| GET    | `/outlets/nearby`                   | Discover nearby plugs                |
| GET    | `/outlets/{id}/live`                | Live plug telemetry snapshot         |
| POST   | `/wallet/topup`                     | Create Razorpay Order for top-up     |
| POST   | `/wallet/topup/verify`              | Verify Razorpay payment + mint       |
| POST   | `/wallet/topup/usdc`                | Create USDC/XLM deposit intent       |
| GET    | `/wallet/{userId}/balance`          | Wallet credit balance                |
| POST   | `/sessions/intent`                  | Create a charging session (escrow)   |
| POST   | `/sessions/{id}/start`              | Start a session (activates hardware) |
| POST   | `/sessions/{id}/telemetry`          | Ingest telemetry sample              |
| POST   | `/sessions/{id}/stop`               | Stop + settle                        |
| GET    | `/sessions/{id}/audit`              | Session evidence bundle              |
| POST   | `/payments/webhook/razorpay`        | Signed Razorpay webhook              |
| GET    | `/events/stream`                    | Server-sent live event stream        |
| GET    | `/admin/overview`                   | Admin metrics (key-guarded)          |

See [docs/integration_contract.md](docs/integration_contract.md) for full
request/response payloads.

## Wallet top-up flow (Razorpay UPI)

```
App                         Backend                     Razorpay
 │  POST /wallet/topup ───────▶ createOrder(notes.user_id)
 │                              └───────────────────────▶ Order
 │  ◀── { orderId, keyId } ─────┘
 │
 │  Razorpay Checkout (order_id, key) ──────────────────▶ user pays via UPI
 │  ◀── { payment_id, signature } ──────────────────────┘
 │
 │  POST /wallet/topup/verify ─▶ verify HMAC signature
 │                              re-fetch amount (getPayment)
 │                              topUpWallet(paymentId as idem key)
 │  ◀── { verified, balanceCredits } ─┘
```

**Why this is safe:** the amount is taken authoritatively from Razorpay, the
signature is verified with the server-only secret, and the Razorpay
`payment_id` is used as the idempotency key — so replays and the parallel
webhook never double-credit.

## Mobile app

The Flutter client (`gridshare_mobile/`) provides:

- Phone-OTP and Google sign-in
- Map-based plug discovery with live availability
- QR scan to start a session
- Real-time charging screen driven by the SSE event stream
- Wallet top-up (Razorpay UPI / USDC-XLM) and balance
- Host dashboard with per-source earnings

Premium UI: custom fragment shaders, Rive-ready hero animations, glassmorphism
design system.

## Testing

```bash
npm test
```

The suite exercises the exact risks in the design brief:

- no double activation on repeated payment webhooks
- no duplicate settlement under session races
- idempotency keys reject reuse with a different payload
- hardware turns on only after escrow lock succeeds
- hardware failure refunds escrow instead of stranding the session
- settlement math: host share / platform fee / rider refund
- safety trip cuts the plug *before* settling
- prepaid threshold auto-stop settles correctly
- malformed telemetry rejected before storage
- signed Razorpay webhooks enforced when a secret is set
- oversized HTTP payloads rejected
- bounded retries recover transient chain/hardware failures
- audit endpoint returns a complete evidence bundle
- failed locks and pending settlements reconcile safely

## Deployment

1. **Backend** — deploy `src/` to any Node host (Render, Fly, Railway, a VM).
   Set the environment variables above. Enable `GRIDSHARE_PERSIST=true` with a
   `DATABASE_URL` for durable storage; run `migrations/001_initial_schema.sql`.
2. **Razorpay** — set `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` (live keys for
   production) and configure the webhook to `/payments/webhook/razorpay` with
   `RAZORPAY_WEBHOOK_SECRET`.
3. **Mobile** — build with the production API URL:
   `flutter build apk --dart-define=API_BASE_URL=https://your-backend`.

Local infra (Postgres/Redis) is provided via `docker-compose.yml`; see
`ops/local_stack.md`.

## Security

- Razorpay webhooks and Checkout callbacks are verified with HMAC-SHA256 using a
  timing-safe comparison (`src/security/razorpay-webhook.js`).
- Payment amounts are always re-derived server-side; the client cannot inflate a
  top-up.
- `/admin/*` endpoints are guarded by `ADMIN_API_KEY`.
- Request bodies are size-limited; malformed JSON is rejected.
- Secrets are read from the environment only. See `ops/security_checklist.md`
  before any pilot.

## Roadmap

- [ ] Migrate remaining mock adapters to production (Soroban relayer, Tuya bridge)
- [ ] TimescaleDB for high-frequency telemetry
- [ ] Transactional DB outbox for the event audit log
- [ ] Host payout off-ramp automation
- [ ] iOS release + App Store / Play Store submission

## License

MIT © GridShare contributors
