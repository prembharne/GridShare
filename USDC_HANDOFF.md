# GridShare — USDC-on-Stellar Top-Up Feature: Handoff Context

## Project
GridShare is a DePIN EV-charging network.
- **Backend**: Node.js, ESM (`"type": "module"`), hexagonal ports/adapters architecture.
- **Contract**: Soroban/Rust credit-wallet escrow (`contracts/gridshare-escrow`). 1 credit = 1 INR, held on-chain. No external token.
- **Mobile**: Flutter (`gridshare_mobile`), dark theme design system (AppColors navy #0B0F19, cyan #00F5D4 rider accent, emerald #2ECC71 host accent, GlassCard/AppButton/AppSpacing tokens).
- **Persistence**: Postgres (optional; in-memory store for tests).
- Stellar SDK: `@stellar/stellar-sdk ^12.1.0`. `axios ^1.6.2`. Node v24.

## Feature being built
An OPTIONAL second top-up rail: **USDC on Stellar (testnet only)** alongside existing UPI (Razorpay).
- Rider tops up USDC exactly like UPI. Backend mints the SAME credit token.
- Conversion: **1 USDC = 1 USD; credits = floor(usdc × usdInrRate)**, live rate from `open.er-api.com`, cached, fallback ~95 INR/USD.
- Credits transfer to host during charging (existing settlement path, unchanged).
- Host UI must show **2 separate earnings sections: UPI and USDC** (source attribution).
- UX: deposit address + QR (SEP-0007 URI) + text memo for correlation.
- Idempotency key downstream = Stellar tx hash. Correlation key = memo.
- USDC is a CLASSIC Stellar asset (not Soroban), watched via Horizon payments SSE stream with a persisted cursor. It converges on the same `saga.topUpWallet()` → `chain.mint()` path as UPI.

## Architecture note (source ledger / provenance)
On-chain credits are fungible, so an OFF-CHAIN "source ledger" tracks funding buckets `{upi, usdc}` per user. At settlement, host earnings are split proportionally across the rider's buckets so the host's earnings can be shown per-source.

---

## ✅ DONE (backend, verified)

### Config — `src/config.js`
Added `numberFromEnv` helper + USDC/FX block:
```
usdcEnabled (STELLAR_USDC_ENABLED, default false)
stellarHorizonUrl (default https://horizon-testnet.stellar.org)
usdcIssuer (STELLAR_USDC_ISSUER, default testnet USDC issuer GBBD47IF...)
usdcAssetCode (default USDC)
usdcReceivePublic / usdcReceiveSecret
usdcIntentTtlSeconds (default 900)
usdInrFallbackRate (default 95)
fxRateUrl (default open.er-api.com/v6/latest/USD)
fxCacheTtlSeconds (default 3600)
```
Plus validation: when `usdcEnabled`, requires usdcReceivePublic/Secret/Issuer.

### FX adapter — `src/adapters/fx-rate-adapter.js` (NEW, working)
`FxRateAdapter.getUsdInr()` → `{rate, source, fetchedAt}` where source ∈ cache/live/stale-cache/fallback. Never throws. Parses `body.rates.INR`.

### In-memory store — `src/adapters/in-memory-store.js`
Added maps `usdcIntents`, `sourceLedger`, `kv` and methods:
`createUsdcIntent`, `getUsdcIntentByMemo`, `updateUsdcIntent`, `getSourceLedger`, `addSourceCredits(userId, source, amount)`, `transferSourceCredits(fromUserId, toUserId, amount)` (proportional bucket split), `getKv`, `setKv`.

### Saga — `src/domain/session-saga.js`
- `topUpWallet` accepts `source` ("upi"|"usdc"), records it in the source ledger via `addSourceCredits`, includes it in the emitted event.
- `completePendingSettlement` does a proportional bucket split via `transferSourceCredits(riderId, hostId, hostShareCredits)`, publishing `wallet.earnings_attributed` / `wallet.earnings_attribution_failed`.
- **Fixed a pre-existing non-reentrant LockManager deadlock**: extracted `_startSessionLocked` from `startSession`; `reconcileSession` now calls the locked body directly (it already holds `withSessionLock`).
- **Fixed `reconcileAll()`** to return `{ scanned, recovered, failed, results }` (was missing recovered/failed).

### HTTP routes — `src/http-server.js`
- `GET /fx/usd-inr`
- `POST /wallet/topup/usdc` — creates intent, quotes at live rate locked into intent
- `GET /wallet/topup/usdc/:memo` — poll intent status

### App wiring — `src/app.js`
Creates `fxRate` (always) and `usdcAdapter` (when `config.usdcEnabled`). Exposes `app.startUsdcWatcher` (module fn `startUsdcWatcher` with cursor key `usdc:horizon:cursor`, underpayment guard, calls `saga.topUpWallet({..., paymentId: txHash, source: "usdc"})`).

### Server boot — `src/server.js`
Starts the watcher on boot (non-fatal) + USDC log line.

### Tests
**Backend suite: `node --test test/difficult-core.test.js` → 28/28 PASS, exit 0.** (Confirmed just now.)

---

## ❌ REMAINING / BROKEN — must fix before USDC works end-to-end

### 1. Adapter ↔ caller mismatches (CRITICAL — USDC path cannot run)
`src/adapters/stellar-usdc-adapter.js` defines a DIFFERENT interface than its callers use:

| Callers expect | Adapter actually has |
|---|---|
| `app.js` passes constructor `receivePublicKey` / `receiveSecretKey` | constructor reads `receivePublic` / `receiveSecret` → adapter throws "requires receivePublic" |
| `http-server.js` calls `usdcAdapter.buildIntent({ amountCredits, expectedUsdc })` returning `{memo, ...}` | adapter only has `buildDepositUri({memo, amount})` + static `generateMemo()` — no `buildIntent` |
| `app.js` calls `watchPayments({ cursor, onCursor, onPayment })` | adapter signature is `watchPayments(onPayment)` (single callback) |
| `app.js` watcher persists cursor via `store.getKv/setKv` with key `usdc:horizon:cursor` | adapter reads/writes cursor via `store.getUsdcCursor?.()` / `store.setUsdcCursor?.()` (methods that don't exist on the store) |

**Also**: `src/app.js` line ~186 uses `const { StellarUsdcAdapter } = require("./adapters/stellar-usdc-adapter.js");` — **`require` is not defined in ESM**. Must be a static `import` at top of file (or dynamic `await import()`).

**Fix approach**: pick ONE contract and align both sides. Recommended — make the adapter authoritative and standardize on:
- constructor `{ receivePublic, receiveSecret }` (update app.js to pass these names)
- add `buildIntent({ amountCredits, expectedUsdc })` to adapter that generates memo + returns `{ memo, destination, amount, uri }`
- `watchPayments({ onPayment, onCursor })`, reading start cursor from an arg or store.getKv
- unify cursor persistence on `store.getKv/setKv` (drop getUsdcCursor/setUsdcCursor)
- convert app.js `require` → `import`

### 2. `.env.example` — add USDC/FX vars (not yet done)
Add all the config keys listed above with placeholder/testnet values.

### 3. Mobile UI (not started)
- `topup_sheet.dart`: UPI/USDC toggle + USDC view (live rate display, QR of SEP-0007 URI, receiving address, memo, copy buttons, status polling of `GET /wallet/topup/usdc/:memo`).
- Host profile: 2 earnings sections (UPI / USDC) from source-ledger data.
- Must match dark design system (AppColors, GlassCard, AppButton, smooth motion).

### 4. Testnet setup script + USDC tests (not started)
- Script: Friendbot-fund the receiving account + establish USDC trustline to the issuer.
- Unit tests: watcher matches memo/asset/destination, underpayment guard, tx-hash idempotency, proportional host attribution split.
- Optional testnet E2E.

---

## Key files
- `src/config.js`, `src/app.js`, `src/server.js`, `src/http-server.js`
- `src/domain/session-saga.js`
- `src/adapters/fx-rate-adapter.js`, `src/adapters/stellar-usdc-adapter.js`, `src/adapters/in-memory-store.js`
- `test/difficult-core.test.js`
- Contract: `contracts/gridshare-escrow/src/{lib,storage,settle,types,errors}.rs`
- Mobile: `gridshare_mobile/lib/features/{auth,home,profile}/*.dart`

## How to run
- Backend tests: `node --test test/difficult-core.test.js` (Windows/Node 24; do NOT pass a directory arg — use the file path).
- Flutter analyze: `cd gridshare_mobile && flutter analyze`.
