# GridShare Architecture — Split by Build Difficulty

This isn't a frontend/backend split — it's a **risk/complexity split**, so you and your teammate can divide work by what's genuinely hard vs. what's well-documented and mechanical. A good rule for a 2-person team: **whoever is stronger in systems/algorithms takes the Difficult column, the other owns Moderate and floats in to help once their pieces are stable** — because Moderate work finishes faster and that person will have slack later in the sprint.

---

## 🟢 MODERATE — Standard patterns, strong docs/SDKs, low ambiguity

You can start these on Day 1 with confidence — the risk here is just *time*, not *unknowns*.

| # | Component | What it involves | Why it's moderate |
|---|---|---|---|
| 1 | **Android UI shell** | Compose navigation graph, screens (Home, Scan, Payment sheet, Profile), Material 3 theming | Pure UI composition, no business-logic ambiguity |
| 2 | **Web app shell** | Next.js routing, landing page, host onboarding form, shadcn/ui re-theme | Standard React patterns, huge community support |
| 3 | **Auth Service** | JWT issue/refresh, OTP via MSG91/Twilio, login screens on both clients | Boilerplate — dozens of reference implementations exist |
| 4 | **Outlet discovery** | Postgres/PostGIS `nearby outlets` query, Mapbox pin rendering (Android + Web) | Well-documented SDKs; geo-query is a known recipe |
| 5 | **QR scan flow** | CameraX + ML Kit barcode scanning, outlet-detail bottom sheet | ML Kit handles the hard part (detection); you just wire the callback |
| 6 | **Payment collection (happy path)** | Razorpay order creation, UPI intent trigger, webhook signature verification | Razorpay's docs + SDKs cover this end-to-end; it's "follow the guide" work |
| 7 | **Basic Tuya device control** | Pairing a device, sending `switch_1: true/false` via Tuya Cloud REST API | Tuya's API is a simple request/response — no timing pressure yet |
| 8 | **Admin dashboard views** | Sessions table, host earnings table, basic Recharts/Visx charts fed by REST endpoints | Standard CRUD-and-display; no real-time constraint at this stage |
| 9 | **Local persistence** | Room DB for offline session cache, DataStore for preferences | Google's own recommended pattern, low risk |
| 10 | **Push notifications** | FCM setup, session-status notifications | Copy-paste-adjacent with Firebase docs |
| 11 | **Design tokens** | Color/spacing/type system as shared JSON, consumed by Compose + Tailwind | Design decision + mechanical wiring, no algorithmic complexity |
| 12 | **CI/CD + Docker Compose** | GitHub Actions for lint/build/test, docker-compose for local dev | Template-able from thousands of existing configs |

**Time-boxing advice:** none of these should take more than 1–1.5 days each once you're in flow. If one is dragging past that, you've likely wandered into a Difficult-column problem in disguise (e.g., "basic Tuya control" turning into "handling flaky device connectivity" — that's now Difficult).

---

## 🔴 DIFFICULT — Real ambiguity, correctness-critical, or genuinely under-documented

These need design-on-paper *before* code, a working owner who isn't context-switching, and buffer time. Start these Day 1 in parallel with Moderate work — they take longer to *converge*, not necessarily longer to *type*.

| # | Component | What it involves | Why it's hard |
|---|---|---|---|
| 1 | **Soroban smart contract** (`init_session`, `lock_deposit`, `settle_session`) | Rust + Soroban SDK, storage design, escrow state machine, refund math on-chain | Small ecosystem, thinner docs than Ethereum/Solidity tooling; mistakes here are expensive because contract bugs affect money directly |
| 2 | **Chain Relayer / Oracle Service** | Backend-signed, fee-bumped (CAP-0015) transactions; trusted-oracle telemetry submission to the contract | Requires careful key custody design + correct handling of Stellar transaction sequencing/retries — get sequence numbers wrong and transactions silently fail |
| 3 | **Safety-Trip Rule Engine** | Real-time anomaly detection on current/temperature telemetry stream, sub-2-second auto cutoff | This is a genuine real-time systems problem: you're racing a hardware-safety deadline, not just returning an API response |
| 4 | **Telemetry ingestion pipeline** | Tuya MQTT/Pulsar webhook → TimescaleDB writes → WebSocket fan-out to live clients | High-frequency writes + concurrent multi-client streaming; easy to build something that works for 1 device and falls over at 5 |
| 5 | **Settlement math (off-chain ↔ on-chain reconciliation)** | Computing exact usage cost to the second, splitting host payout vs. platform fee vs. refund delta, then getting the contract and the ledger to agree | This is where silent financial bugs live — needs unit tests with edge cases (session stopped at 0 seconds, mid-tick, exactly at threshold) |
| 6 | **Payment → Escrow → Hardware saga** | Making sure a paid session *always* either fully activates the plug or fully refunds — no stuck-in-limbo states | Classic distributed-transaction problem across 3 external systems (Razorpay, Stellar, Tuya) that can each fail independently |
| 7 | **Idempotency across webhooks** | Razorpay/Tuya webhooks can and will fire more than once — must not double-charge, double-lock, or double-toggle | Requires idempotency keys + careful DB transaction boundaries; easy to skip until it breaks live in front of judges |
| 8 | **Key management/security for the relayer** | Where and how the backend's Stellar signing key + Razorpay/Tuya API secrets are stored and rotated | One leaked key = drained escrow; needs actual security design, not just `.env` and hope |
| 9 | **Live counter UI sync** | Interpolating smooth number/ring animation between discrete telemetry ticks (not jumping every 3–5 seconds) | Looks simple, is actually an animation-timing problem — naive implementation looks janky and undermines the "premium" goal |
| 10 | **Compliance-to-code mapping** | Ensuring invoice line items, contract terminology, and payout descriptions *never* say "electricity resale," consistently across mobile, web, and PDF receipts | Not algorithmically hard, but a single inconsistent string across 3 surfaces undermines your entire regulatory defense in front of judges |

---

## Suggested split for a 2-person team

**Option 1 — By strength (recommended if one of you is stronger backend/systems):**
- **Person 1 (Systems-leaning):** Difficult #1–8 (contract, relayer, safety engine, telemetry pipeline, settlement, saga, idempotency, key security)
- **Person 2 (Product/UI-leaning):** All of Moderate + Difficult #9–10 (live counter animation, compliance-copy consistency) once their Moderate backlog is clear

**Option 2 — By layer (recommended if skills are more even):**
- **Person 1:** Everything blockchain + IoT + safety (Moderate #7 and Difficult #1–4, #6–8)
- **Person 2:** Everything client + payments + data display (Moderate #1–6, #8–12, Difficult #5, #9–10)

**Either way, sequence it like this regardless of who owns what:**
1. Get one Moderate item fully working end-to-end first (e.g., Auth) to prove your CI/deploy pipeline works.
2. Attack Difficult #1–2 (contract + relayer) immediately in parallel — they have the longest feedback loop (learning Soroban, debugging testnet transactions), so starting late here is the #1 cause of Day-18 panic in projects like this.
3. Treat Difficult #6–7 (saga + idempotency) as a *design review*, not just code — sketch the state machine on paper/whiteboard together before either of you writes it, since it touches both of your services.
