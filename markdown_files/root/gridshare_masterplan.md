# GridShare — Production-Ready Master Blueprint
### DePIN EV Charging Network | 21-Day Builder Program Execution Plan

---

## 1. Full System Architecture

Think of GridShare as **five decoupled layers** glued by two integration bridges (Payment↔Chain, Chain↔Hardware). Decoupling is what lets a 2-person team ship this in 21 days without one broken piece blocking everything else.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT LAYER                                    │
│  ┌────────────────────────┐        ┌─────────────────────────────────┐      │
│  │  Android App (Rider &   │        │  Web App (Host onboarding,      │      │
│  │  Host) — Kotlin/Compose │        │  Admin ops, Landing) — Next.js  │      │
│  └────────────┬────────────┘        └────────────────┬────────────────┘      │
└───────────────┼──────────────────────────────────────┼───────────────────────┘
                │ REST/gRPC + WebSocket (live telemetry)│
                ▼                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        BFF / API GATEWAY LAYER                              │
│   NestJS Gateway — Auth (JWT+refresh), rate limiting, request routing       │
└───────┬───────────────┬────────────────┬────────────────┬───────────────────┘
        ▼               ▼                ▼                ▼
┌───────────────┐ ┌─────────────┐ ┌──────────────┐ ┌────────────────────┐
│ Session &     │ │ Payment     │ │ Chain Relayer│ │ IoT Bridge Service │
│ Booking Svc   │ │ Svc         │ │ / Oracle Svc │ │ (Go/Node, low-lat) │
│ (Node/Nest)   │ │ (Node/Nest) │ │ (Node/Rust)  │ │                    │
└──────┬────────┘ └──────┬──────┘ └──────┬───────┘ └─────────┬──────────┘
       │                 │                │                   │
       │                 ▼                ▼                   ▼
       │         ┌───────────────┐ ┌──────────────┐  ┌──────────────────┐
       │         │ Razorpay/     │ │ Soroban Smart│  │ Tuya Cloud API /  │
       │         │ Cashfree PA   │ │ Contract     │  │ MQTT Webhooks     │
       │         │ (UPI collect) │ │ (Stellar     │  │ (switch, add_ele, │
       │         │               │ │  Testnet)    │  │  temp/current)    │
       │         └───────────────┘ └──────────────┘  └─────────┬──────────┘
       │                                                        ▼
       │                                              ┌──────────────────────┐
       │                                              │ 16A BIS-certified     │
       │                                              │ Tuya Smart Plug (edge)│
       │                                              └──────────────────────┘
       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATA LAYER                                      │
│  Postgres (users, sessions, ledger) · Redis (cache/session/pubsub)          │
│  TimescaleDB (telemetry time-series: add_ele, voltage, temp)                │
│  S3/Cloudflare R2 (QR assets, host KYC docs, invoices)                      │
└─────────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ metrics, logs, traces
┌─────────────────────────────────────────────────────────────────────────────┐
│              OBSERVABILITY & SAFETY LAYER                                   │
│  Prometheus + Grafana · Sentry · Safety-Trip Rule Engine (current/temp     │
│  spike → auto switch_1:false + alert) · Audit log for regulatory proof     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 End-to-end request flow (detailed)

1. **Discovery** — Rider app queries `GET /outlets/nearby` (PostGIS geo query) → renders pins on Mapbox.
2. **Intent** — Rider scans QR (CameraX + ML Kit) → app resolves `outlet_id` → calls `POST /sessions/intent` with target amount.
3. **Payment capture** — Session Svc creates a `pending` session row, calls Payment Svc → Razorpay order created → UPI intent/collect triggered on rider's phone.
4. **Payment webhook** — Razorpay fires webhook → Payment Svc verifies signature → marks session `paid` → publishes `session.paid` event (Redis pub/sub or a lightweight queue).
5. **Escrow lock (invisible Web3)** — Chain Relayer Svc consumes `session.paid`, builds a Soroban transaction (fee-bumped, backend-sponsored key) that locks the equivalent stable-token value under a unique `session_id` in the contract. Confirms ledger close.
6. **Hardware ON** — On contract confirmation, IoT Bridge Svc calls Tuya Cloud API `POST /v1.0/devices/{id}/commands` with `{"switch_1": true}`. Plug relay closes.
7. **Telemetry stream** — Plug reports `add_ele`, current, voltage, temperature via Tuya Pulsar/MQTT webhook every few seconds → IoT Bridge writes to TimescaleDB and republishes over WebSocket to the rider app (live ₹/kWh counter).
8. **Cutoff triggers** — Whichever happens first stops the session: (a) prepaid amount reached, (b) user taps "Stop" in-app, (c) Safety-Trip Rule Engine detects abnormal current/temp → IoT Bridge sends `{"switch_1": false}` immediately, before waiting on-chain.
9. **Settlement** — IoT Bridge sends final telemetry to Chain Relayer (acting as trusted oracle) → Soroban contract computes exact cost, releases host's share to the distribution pool wallet, refunds delta to rider's custodial balance.
10. **Reconciliation** — Session Svc marks session `settled`, generates invoice (billed as "Infrastructure Facility & Leasing Service Fee", never "electricity"), pushes receipt + push notification.
11. **Payout** — Host payouts run on a T+1 batch via Razorpay Route/Payouts API, referencing the on-chain ledger as the audit trail, not as the money-movement rail (this is what keeps you outside RBI PA-PG licensing scope).

### 1.2 Why this shape wins judges' technical scrutiny
- **Separation of concerns** proves you understood the RBI escrow hurdle (fiat rail ≠ settlement ledger).
- **Oracle pattern** (backend feeding real-world telemetry to Soroban) is a legitimate, explainable Web3 design — not "blockchain for the sake of it."
- **Safety-Trip Rule Engine** run at the IoT Bridge (not inside the smart contract) means power gets cut in milliseconds, not after a ledger close — this is the single most convincing demo moment for judges.

---

## 2. 21-Day Master Execution Schedule

Team of 2. Split as:
- **Builder A (Frontend Owner):** Android (Kotlin/Compose) + Web (Next.js) + UI system
- **Builder B (Backend/Chain Owner):** NestJS services, Soroban contract, IoT Bridge, Payment integration

Both converge daily for a 15-min sync + a nightly integration merge. Work in **6 modules**, looping build → integrate → harden every ~5 days so you always have *something demoable*, never a "big bang" integration on day 20.

### Module A — Foundation & Skeleton (Days 1–3)

| Day | Builder A | Builder B | Joint Deliverable |
|---|---|---|---|
| 1 | Design tokens (color/type/spacing), Figma wireframes for 6 core screens, repo + CI skeleton for Android/Web | Repo skeleton for NestJS monorepo (Nx/Turborepo), Postgres schema v1, Soroban project scaffold (`soroban contract new`) | Architecture doc signed off, repos live, CI green on empty builds |
| 2 | Compose project setup: navigation graph, theming (Material 3 dynamic color), Hilt DI wiring | Auth Svc (JWT + refresh, OTP via MSG91/Twilio), Session Svc skeleton with mock endpoints | Login/OTP flow working end-to-end (mobile ↔ backend) |
| 3 | Next.js project: routing, shadcn/ui base install + custom theme override, landing page shell | Soroban contract v1: `init_session`, `lock_deposit`, `settle_session` stub functions; local testnet deploy | Contract deployed to Stellar Futurenet/Testnet; first test tx signed via backend key |

### Module B — Core Build Sprint (Days 4–9)

| Day | Builder A | Builder B | Joint Deliverable |
|---|---|---|---|
| 4 | Rider Home screen: Mapbox Android SDK, nearby-outlets pin rendering | `GET /outlets/nearby` PostGIS query, seed 15 mock outlets | Map shows real pins from backend |
| 5 | QR scan screen (CameraX + ML Kit barcode), outlet detail bottom sheet | `POST /sessions/intent`, session state machine (pending→paid→active→settled) | Scan → intent creation working |
| 6 | Payment sheet UI (amount picker, UPI intent trigger) | Razorpay order creation + webhook receiver + signature verification | Real ₹1 test payment completes and updates session state |
| 7 | Host onboarding web flow: KYC upload, plug pairing wizard UI | Tuya Cloud API integration: device pairing, `switch_1` command, IoT Bridge Svc scaffold | One physical/simulated 16A plug controllable from web dashboard |
| 8 | Live charging screen: real-time ₹ counter, animated energy-flow visual (Lottie), Stop button | Chain Relayer Svc: `lock_deposit` call wired to `session.paid` event; fee-bump relayer key setup | Payment → escrow lock happens automatically, visible on Stellar Expert testnet explorer |
| 9 | Web admin dashboard: sessions table, host earnings view, TimescaleDB chart (Recharts) | Telemetry ingestion: Tuya webhook → TimescaleDB writer, WebSocket relay to clients | End of Module B demo: full loop — scan → pay → escrow lock → plug ON (manually simulated telemetry) |

**🔁 Loop checkpoint (Day 9 evening):** Run the entire flow start to finish with real hardware. Log every failure point. This is your first "looping" pass — fix before moving on.

### Module C — Integration Sprint (Days 10–15)

| Day | Builder A | Builder B | Joint Deliverable |
|---|---|---|---|
| 10 | Wire live telemetry WebSocket into charging screen (replace mock data) | Cutoff logic: prepaid-threshold auto-stop + manual stop endpoint | Session auto-stops at ₹ threshold |
| 11 | Settlement/receipt screen with itemized "Service Fee" invoice (compliance wording) | `settle_session` Soroban call wired to final telemetry; refund-delta logic | On-chain settlement visible + correct refund math verified |
| 12 | Host payout screen (web): earnings ledger, payout status | Razorpay Payouts/Route batch job (T+1), payout audit log tied to session_id | End-to-end money loop closed (test mode) |
| 13 | Safety UX: in-app alert banner for trip events, push notifications (FCM) | **Safety-Trip Rule Engine**: current/temp threshold watcher on telemetry stream, auto `switch_1:false` + alert event | Simulate current spike → plug cuts in <2s, app shows alert |
| 14 | Polish rider app navigation, error/empty/loading states across all screens | Rate limiting, input validation, structured logging (Pino), Sentry wired | App handles network failures, backend rejects malformed requests gracefully |
| 15 | Web dashboard: real-time device health view (online/offline, temp, last session) | API hardening: idempotency keys on payment webhooks, DB transaction wrapping for session state changes | **Module C demo**: full hardware-in-the-loop run including a forced safety trip |

**🔁 Loop checkpoint (Day 15 evening):** Second full loop test — this time by someone who *isn't* Builder A/B (friend/mentor), to catch UX confusion and hidden assumptions.

### Module D — Hardening & Compliance Proof (Days 16–18)

| Day | Builder A | Builder B | Joint Deliverable |
|---|---|---|---|
| 16 | Accessibility pass (contrast, tap targets, TalkBack), performance profiling (Compose recomposition, Next.js bundle size) | Load test Session/Payment Svc (k6, 100 concurrent sessions), fix N+1 queries | Perf report: p95 latency, no crashes under load |
| 17 | Security pass: certificate pinning, secure storage (EncryptedSharedPreferences/Keystore), no secrets in client | Security pass: secrets in env vault, JWT rotation, webhook signature enforcement everywhere, contract re-entrancy review | Internal "pen-test lite" checklist cleared |
| 18 | One-pager compliance UI element: in-app "How GridShare stays 100% legal" explainer screen | Compile compliance doc: Electricity Act "Service not resale" framing, RBI PA delegation diagram, VDA/fee-bump explainer | Compliance one-pager (PDF) ready to hand judges |

### Module E — Premium Polish (Days 19–20)

| Day | Builder A | Builder B | Joint Deliverable |
|---|---|---|---|
| 19 | Motion pass: shared-element transitions, micro-interactions (button press, QR success haptic + animation), dark mode | Backend: seed realistic demo data (10 hosts, 40 sessions, believable earnings history) | App feels "shipped," not "hackathon" |
| 20 | Web landing page final copy + visuals, pitch-deck screenshots exported at high-res | Failover rehearsal: what happens if Tuya API times out mid-demo (fallback simulated mode toggle) | Demo-day "safety net" mode built and tested |

### Module F — Demo Day (Day 21)
- Morning: full dry run x2 (cold start, no dev tools open) on real hardware + real testnet.
- Have a **recorded backup video** of one perfect end-to-end run — non-negotiable, Wi-Fi/venue networks fail more hackathons than code does.
- Prepare a 90-second version and a 4-minute version of the demo script.
- Submission checklist: repo README with architecture diagram, `.env.example`, contract address + explorer link, compliance one-pager, pitch deck.

---

## 3. Tech Stack (deliberately non-generic, chosen for judge signal + real production viability)

### 3.1 Mobile — Native Kotlin (not Flutter)

| Layer | Choice | Why |
|---|---|---|
| UI | **Jetpack Compose + Material 3 Expressive** | Native rendering, best-in-class animation APIs (no cross-platform jank when you need the "live charging" motion to feel premium) |
| Architecture | **MVI** via plain `ViewModel` + `StateFlow`/`SharedFlow` (or Circuit by Slack if you want opinionated MVI) | Predictable state for a real-time, event-heavy app (payment → escrow → hardware → telemetry) |
| DI | **Hilt** | Standard, fast to wire, judge-recognizable as "production practice" |
| Networking | **Ktor Client** (not Retrofit) | Kotlin-native, coroutine-first, multiplatform-ready if you later want KMP for iOS |
| Realtime | **Ktor WebSocket client** for telemetry stream | Same stack as networking, no extra dependency |
| Serialization | **kotlinx.serialization** | No reflection overhead, pairs naturally with Ktor |
| Local persistence | **Room** + **DataStore** (not SharedPreferences) | Offline session cache, typed preferences |
| Maps | **Mapbox Maps SDK for Android** | Better custom styling than Google Maps for a "premium" dark-mode map look |
| QR/Camera | **CameraX + ML Kit Barcode Scanning** | On-device, fast, no network dependency for scanning |
| Animations | **Lottie for Android** + Compose `Animatable`/`InfiniteTransition** | The energy-flow / charging visual is your emotional "wow" moment |
| Push | **Firebase Cloud Messaging** | Standard, free tier is enough |
| Security | **EncryptedSharedPreferences / Android Keystore** | No token or key material in plaintext |
| Testing | **Turbine** (Flow testing) + **Compose UI Test** | Shows judges you tested state and UI, not just "it works on my phone" |

### 3.2 Web (Landing + Host Onboarding + Admin Dashboard)

| Layer | Choice | Why |
|---|---|---|
| Framework | **Next.js 14 (App Router) + TypeScript** | SSR for landing/SEO, RSC for dashboard perf |
| Styling | **Tailwind CSS + shadcn/ui, heavily re-themed** (not default shadcn look) | Fast to build, but you *must* override tokens — default shadcn is the #1 "looks like every other hackathon project" tell |
| State/data | **TanStack Query** for server state, **Zustand** for client/UI state | Avoids Redux boilerplate, judge-recognized modern choice |
| Realtime | **native WebSocket client** or **Server-Sent Events** for live telemetry charts | Simpler than Socket.IO for one-directional stream, less overhead |
| Charts | **Visx (Airbnb) or Recharts** | Visx if you want a distinctive, non-templated look for earnings/telemetry graphs |
| Maps | **Mapbox GL JS** | Consistent visual language with the mobile app |
| Animation | **Framer Motion** | Page transitions, number "count-up" for live ₹ balances |
| Forms | **React Hook Form + Zod** | Type-safe validation shared with backend DTOs |
| Auth | **NextAuth/Auth.js** wired to backend JWT | Standard, quick |

### 3.3 Backend

| Layer | Choice | Why |
|---|---|---|
| API/BFF | **NestJS (TypeScript)** | Modular, DI-based, matches Angular-style structure judges recognize as "enterprise-serious" |
| IoT Bridge (latency-critical) | **Go microservice** (separate from NestJS) | Sub-100ms reaction time for the Safety-Trip cutoff; Go's goroutines handle concurrent device streams cleanly — this is your strongest "we thought about production" signal |
| DB (relational) | **PostgreSQL + Prisma** (or TypeORM) | Prisma's type-safety pairs well with NestJS DTOs |
| DB (geo) | **PostGIS extension** | `nearby outlets` query, done properly instead of naive lat/lng math |
| DB (time-series) | **TimescaleDB** | Purpose-built for `add_ele`/current/temp telemetry, way better than cramming into Postgres rows |
| Cache/pubsub | **Redis** | Session cache + pub/sub for event fan-out between services |
| Queue | **BullMQ** | Payout batching, retry-safe webhook processing |
| Blockchain | **Rust + Soroban SDK**, deployed on **Stellar Testnet/Futurenet** | As specified in your original design — this stays |
| Chain relayer | **Stellar SDK (JS) + CAP-0015 Fee Bumping** | Backend-sponsored gas, invisible to users |
| Payments | **Razorpay** (Orders + Payouts/Route API) | Most hackathon-judge-familiar PA in India, strong docs |
| IoT | **Tuya Cloud API + Tuya Pulsar (MQTT) for real-time telemetry push** | As specified — keep it, it's the right call for BIS-certified consumer smart plugs |
| Observability | **Prometheus + Grafana + Sentry** | Shows production-readiness in your README, not just code |
| Infra | **Docker Compose for dev**, **Fly.io or Railway for demo deploy** (skip full K8s — not worth the 21-day budget) | Kubernetes is overkill for a hackathon judge; a clean Docker Compose + one-click deploy reads as *more* mature, not less |
| CI/CD | **GitHub Actions** | Lint, test, build on every PR — put the green badge in your README |

---

## 4. Premium UI/UX Direction (Web + Mobile)

A hackathon-winning UI is not "more animations" — it's **restraint + one unforgettable moment**. Here's the system:

### 4.1 Design system foundations
- **Typography:** A single distinctive display font for numbers/headings (e.g., **Clash Display** or **General Sans**) + **Inter** for body text. Judges subconsciously read good type pairing as "funded startup," not "hackathon."
- **Color:** Dark-mode-first. Base near-black (`#0B0E11`), one electric accent (e.g., a charge-green `#39FF88` or voltage-blue `#3D8BFF`) used *sparingly* — only for active/charging states, CTAs, and the live counter. Overusing the accent color is the most common "not premium" mistake.
- **Spacing/radius system:** 4px base grid, consistent 12–16px corner radii across cards, buttons, bottom sheets — mismatched radii is the #2 tell of an unpolished UI.
- **Elevation:** Soft, colored shadows (a faint glow of the accent color under active elements) instead of default Material black shadows.

### 4.2 The one unforgettable moment
Design the **live charging screen** as your hero interaction:
- A circular progress ring (Compose `Canvas` / SVG) that fills as ₹ spend approaches the cap, with a subtle pulse animation synced to a fake "current flow" rhythm.
- Real digits counting up smoothly (not jumping) as telemetry arrives — use interpolated animation between telemetry ticks, not raw re-renders.
- On successful stop/settlement: a short, tasteful success animation (confetti is overused — prefer a "ring completes → checkmark morph" transition).

### 4.3 Consistency across mobile & web
- Ship a **shared design-token JSON** (colors, spacing, radii, font scale) consumed by both Compose (as a generated Kotlin object) and Tailwind (as `tailwind.config` extension) — this single artifact makes both apps feel like one product, and it's a great thing to point at during Q&A.
- Mirror the exact same map pin style, card shadow, and accent color between the Android app and the Next.js dashboard.

### 4.4 States most teams forget (do these — judges notice)
- Empty states (no outlets nearby, no sessions yet) with a short illustration, not a blank screen.
- Loading skeletons (not spinners) for the outlets list and dashboard tables.
- Explicit offline/error states for when Tuya or Stellar testnet is briefly unreachable — this doubles as your "graceful degradation" demo talking point.
- One clearly designed "Safety Trip" alert state — red accent break from your normal palette, used *only* here, so it registers as serious.

---

## 5. Conclusion — Definition of "Production-Ready" at Day 21

By the end of the program you should be able to check every box below, not just have working code:

- [ ] Real hardware demo: physical 16A Tuya plug controlled end-to-end from a real UPI payment through Soroban settlement.
- [ ] Safety-Trip Rule Engine demonstrably cuts power in under 2 seconds during a simulated spike.
- [ ] Compliance one-pager mapped explicitly to Ministry of Power "Service" classification and RBI PA guidelines, matching your invoicing language exactly.
- [ ] CI green, Sentry wired, load test report available (even if modest numbers).
- [ ] Design system shared between Android and Web with zero visual inconsistency.
- [ ] A recorded backup demo video, because live demos fail on venue Wi-Fi more often than on code.
- [ ] README that a stranger could clone-and-run in under 15 minutes.

If all seven are true, you don't just have a hackathon submission — you have a defensible v1 you could actually pilot with 5–10 real hosts the week after the program ends. That's the difference between "won a hackathon" and "started a company," and it's worth optimizing for both simultaneously.
