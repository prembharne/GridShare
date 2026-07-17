# When I Need You

I can continue building local production scaffolding without you for now. I need you only when the work touches real accounts, hardware, money movement, deployment ownership, or legal wording.

## Needed For Real Provider Integration

1. Razorpay
   - Test mode key id and key secret
   - Webhook secret
   - Which payment event should activate the session: usually `payment.captured`
   - Whether payouts use RazorpayX, Route, or a manual pilot process

2. Stellar/Soroban
   - Testnet account for relayer funding
   - Target network: testnet or futurenet
   - Preferred asset for escrow representation
   - Whether users are custodial only for MVP

3. Tuya Hardware
   - Tuya Cloud project credentials
   - One real device id for a paired smart plug
   - Confirmation of telemetry fields for energy, current, voltage, and temperature
   - Safe way to simulate current/temperature spikes during demo

4. Database/Hosting
   - Where to run the backend: Railway, Fly.io, Render, VPS, or another target
   - Whether managed Postgres/Timescale is available
   - Domain name and production URL if there is one

5. Compliance/Business Wording
   - Final invoice wording approved by your mentor/legal reviewer
   - Host payout description
   - Terms shown to rider/host
   - Whether the pilot is demo-only or real paid pilot

## Needed Before Real Money Or Hardware Pilot

- Razorpay account access
- Tuya device physically available and paired
- Stellar funded testnet account
- Deployment target selected
- Admin user list
- Final compliance copy sign-off

## Not Needed Yet

I can keep working without these for:

- Database adapter implementation shape
- Smart contract skeleton and tests
- Provider adapter skeletons
- Admin/reconciliation APIs
- Docker/local stack
- Documentation and checklists
- More test coverage
- One-button demo flow and event stream integration

