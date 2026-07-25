import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createApp } from "../src/app.js";

// Spin up the app on the default in-process mock path (no DB, no real adapters).
function freshApp() {
    return createApp({ env: {} });
}

async function fundedRider(app, credits = 100) {
    await app.saga.topUpWallet({
        userId: "rider_pm",
        amountCredits: credits,
        paymentId: `pay_${crypto.randomUUID()}`,
        idempotencyKey: `topup-${crypto.randomUUID()}`
    });
}

async function startPerMinute(app, overrides = {}) {
    const intent = await app.saga.createIntent({
        riderId: "rider_pm",
        hostId: "host_1",
        outletId: "outlet_1",
        depositCredits: 50,
        ratePerMinuteCredits: 2,
        idempotencyKey: `intent-${crypto.randomUUID()}`,
        ...overrides
    });
    await app.saga.startSession({
        sessionId: intent.session.id,
        idempotencyKey: `start-${intent.session.id}`
    });
    return intent.session.id;
}

// Rewind a session's activeAt so the meter sees `seconds` of elapsed time.
async function rewindActiveAt(app, sessionId, seconds) {
    const activeAt = new Date(Date.now() - seconds * 1000).toISOString();
    await app.store.updateSession(sessionId, { activeAt });
}

test("per-minute intent records billing mode and rate", async () => {
    const app = freshApp();
    await fundedRider(app);
    const sessionId = await startPerMinute(app, { selectedDurationMinutes: 30 });
    const { session } = await app.saga.getSession(sessionId);
    assert.equal(session.billingMode, "per_minute");
    assert.equal(session.ratePerMinuteCredits, 2);
    assert.equal(session.selectedDurationMinutes, 30);
    assert.equal(session.status, "active");
});

test("tickSession accrues charge without stopping mid-session", async () => {
    const app = freshApp();
    await fundedRider(app);
    const sessionId = await startPerMinute(app);
    await rewindActiveAt(app, sessionId, 90); // 1.5 min → 2 billed min → 4 credits

    const result = await app.saga.tickSession(sessionId);
    assert.equal(result.session.status, "active");
    assert.equal(result.meter.billedMinutes, 2);
    assert.equal(result.meter.amountDueCredits, 4);
});

test("tickSession auto-stops when the selected duration elapses", async () => {
    const app = freshApp();
    await fundedRider(app);
    const sessionId = await startPerMinute(app, { selectedDurationMinutes: 5 });
    await rewindActiveAt(app, sessionId, 5 * 60 + 1); // just past 5 minutes

    const result = await app.saga.tickSession(sessionId);
    assert.equal(result.session.status, "settled");
    assert.equal(result.session.stopReason, "duration_elapsed");
    // 5 min * 2 = 10 credits due, deposit 50 → refund 40
    assert.equal(result.settlement.amountDueCredits, 10);
    assert.equal(result.settlement.refundCredits, 40);
});

test("tickSession auto-stops when accrued charge reaches the deposit", async () => {
    const app = freshApp();
    await fundedRider(app);
    const sessionId = await startPerMinute(app); // deposit 50 @ 2/min → 25 min cap
    await rewindActiveAt(app, sessionId, 30 * 60); // 30 min > 25 min cap

    const result = await app.saga.tickSession(sessionId);
    assert.equal(result.session.status, "settled");
    assert.equal(result.session.stopReason, "prepaid_threshold_reached");
    assert.equal(result.settlement.amountDueCredits, 50);
    assert.equal(result.settlement.refundCredits, 0);
});

test("SessionMeter sweep ticks and settles due sessions", async () => {
    const app = freshApp();
    await fundedRider(app);
    const sessionId = await startPerMinute(app, { selectedDurationMinutes: 3 });
    await rewindActiveAt(app, sessionId, 3 * 60 + 5);

    const summary = await app.sessionMeter.tickOnce();
    assert.equal(summary.ticked, 1);
    assert.equal(summary.stopped, 1);
    const { session } = await app.saga.getSession(sessionId);
    assert.equal(session.status, "settled");
});

test("energy sessions are ignored by the per-minute meter", async () => {
    const app = freshApp();
    await fundedRider(app);
    // No ratePerMinuteCredits → legacy energy billing.
    const intent = await app.saga.createIntent({
        riderId: "rider_pm",
        hostId: "host_1",
        outletId: "outlet_1",
        depositCredits: 50,
        idempotencyKey: `intent-${crypto.randomUUID()}`
    });
    await app.saga.startSession({
        sessionId: intent.session.id,
        idempotencyKey: `start-${intent.session.id}`
    });

    const tick = await app.saga.tickSession(intent.session.id);
    assert.equal(tick.skipped, true);

    const summary = await app.sessionMeter.tickOnce();
    assert.equal(summary.ticked, 0);
});

test("mock hardware exposes a live status snapshot per outlet", async () => {
    const app = freshApp();
    await fundedRider(app);
    const sessionId = await startPerMinute(app);
    const { session } = await app.saga.getSession(sessionId);

    const live = await app.hardware.getLiveStatus(session.outletId);
    assert.equal(live.switchOn, true); // plug is ON during an active session
    assert.ok(live.powerW > 0);
});
