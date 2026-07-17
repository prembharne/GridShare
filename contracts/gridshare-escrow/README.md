# GridShare Escrow Contract (Soroban)

Vault-grade smart contract for the GridShare EV-charging escrow flow.

## Trust model

| Party | Trusted for | NOT trusted for |
|-------|-------------|-----------------|
| **Relayer** (backend key) | Submitting telemetry readings; triggering lock/settle/refund | Lying about the *fund split* — the contract recomputes it and enforces conservation |
| **Rider/Host** | Providing custodial destination addresses | Moving escrowed funds (no `require_auth` on value paths) |
| **Admin** | Role rotation, pause, upgrade veto | Moving escrowed funds |
| **Token** | Honest `transfer` semantics | — (a malicious token can still re-enter; mitigated by checks-effects-interactions) |

## Security properties

1. **Single trusted mover** — only `Relayer` can lock/settle/refund.
2. **Checks-effects-interactions** — session status is persisted to storage
   *before* any token transfer, so a re-entering hostile token cannot
   double-settle or double-refund.
3. **On-chain settlement math** — `settle_session` takes only `energy_wh`;
   the contract computes `host_share`, `platform_fee`, `refund` and asserts
   `host_share + platform_fee + refund == deposit`. A relayer cannot
   over-allocate to the treasury.
4. **Strict state machine** — `Created → Locked → (Settled | Refunded)`.
   Idempotent on duplicate lock/settle within the same state.
5. **Circuit breaker** — `pause()` halts all value movement.
6. **Timelocked upgrade** — `propose_upgrade` + 14-day window + `execute_upgrade`;
   admin can veto by pausing.
7. **Overflow protection** — `overflow-checks = true` + explicit `checked_*`
   arithmetic in `settle.rs`.

## Functions

| Function | Caller | Effect |
|----------|--------|--------|
| `initialize(admin, relayer, upgrader, treasury)` | anyone (once) | bootstrap roles |
| `init_session(...)` | Relayer | register metadata (optional pre-step) |
| `lock_deposit(session, rider, host, outlet, token, deposit, price, fee_bps)` | Relayer | pull `deposit` from relayer → contract; `Created→Locked` |
| `settle_session(session, energy_wh, telemetry_hash, reason)` | Relayer | recompute split; `Locked→Settled`; distribute |
| `refund_deposit(session, reason)` | Relayer | `Locked→Refunded`; full refund to rider |
| `get_session(session)` | anyone | view |
| `set_relayer / set_treasury / set_upgrader / pause / unpause` | Admin | config |
| `propose_upgrade / cancel_upgrade / execute_upgrade` | Upgrader/Admin | upgrade |

## Build & deploy

```bash
rustup target add wasm32-unknown-unknown
./build.sh
NETWORK=testnet ADMIN_SECRET=S... TREASURY_ADDRESS=G... ./deploy.sh
```

The printed `CONTRACT_ID` goes into the backend's `SOROBAN_CONTRACT_ID`.

## Fund flow (custodial model)

1. Platform pre-funds the **relayer reserve** address with stablecoin.
2. On payment captured, backend calls `lock_deposit` — funds move
   relayer → contract.
3. On stop, backend calls `settle_session(energy)` — contract splits to
   host / treasury / rider.
4. On hardware-activation failure, backend calls `refund_deposit` — full
   refund to rider.

## Unit conversion note

All on-chain amounts are in the **token's raw smallest unit** (e.g. 1 USDC =
`1_000_000`). The backend is responsible for converting fiat "paise" to
token units before calling. The contract only ever verifies integer
conservation, never fiat semantics.
