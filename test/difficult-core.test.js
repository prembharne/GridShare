import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createApp } from "../src/app.js";
import { assertComplianceCopy, INVOICE_DESCRIPTION } from "../src/domain/compliance.js";
import { computeSettlement } from "../src/domain/settlement-math.js";

async function activeSession(app, overrides = {}) {
  // Top up wallet first
  await app.saga.topUpWallet({
    userId: "rider_1",
    amountCredits: 50,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: `topup-${crypto.randomUUID()}`
  });

  const intent = await app.saga.createIntent({
    riderId: "rider_1",
    hostId: "host_1",
    outletId: "outlet_1",
    depositCredits: 50,
    idempotencyKey: `intent-${crypto.randomUUID()}`,
    ...overrides
  });

  // Start session (locks credits, turns hardware ON)
  await app.saga.startSession({
    sessionId: intent.session.id,
    idempotencyKey: `start-${intent.session.id}`
  });

  return intent.session.id;
}

// ============================ Settlement Math ============================

test("computeSettlement calculates host share and service fee correctly", () => {
  // deposit=50, energy=12.5kWh @ 18 credits/kWh = 225 credits due
  // service fee = 225 * 300/10000 = 6 (3%)
  // host = 225 - 6 = 219
  // refund = 50 - 225 = -175 -> min 0, so refund = 0 (capped at deposit)
  const result = computeSettlement({
    depositCredits: 50,
    energyWh: 12500,
    pricePerKwhCredits: 18,
    serviceFeeBps: 300
  });

  assert.equal(result.amountDueCredits, 50); // capped at deposit
  assert.equal(result.serviceFeeCredits, 1); // 50 * 300 / 10000 = 1.5 -> floor 1
  assert.equal(result.hostShareCredits, 49);
  assert.equal(result.refundCredits, 0);
  assert.equal(result.hostShareCredits + result.serviceFeeCredits + result.refundCredits, 50);
});

test("computeSettlement respects deposit cap and refunds unused", () => {
  // deposit=100, energy=1000Wh @ 18 = 18 due
  // fee = 18 * 300/10000 = 0 (floor)
  // host = 18, refund = 82
  const result = computeSettlement({
    depositCredits: 100,
    energyWh: 1000,
    pricePerKwhCredits: 18,
    serviceFeeBps: 300
  });

  assert.equal(result.amountDueCredits, 18);
  assert.equal(result.serviceFeeCredits, 0);
  assert.equal(result.hostShareCredits, 18);
  assert.equal(result.refundCredits, 82);
  assert.equal(result.hostShareCredits + result.serviceFeeCredits + result.refundCredits, 100);
});

// ============================ Compliance ============================

test("assertComplianceCopy passes when invoice description is set", () => {
  assertComplianceCopy(INVOICE_DESCRIPTION);
});

test("assertComplianceCopy throws on missing description", () => {
  assert.throws(
    () => assertComplianceCopy(undefined),
    { code: "COMPLIANCE_COPY_MISSING" }
  );
});

// ============================ Core Flow ============================

test("wallet top-up mints credits and updates balance", async () => {
  const app = createApp();

  const result = await app.saga.topUpWallet({
    userId: "rider_wallet",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: `topup-${crypto.randomUUID()}`
  });

  assert.equal(result.userId, "rider_wallet");
  assert.equal(result.amountCredits, 100);

  const balance = await app.saga.getWalletBalance("rider_wallet");
  assert.equal(balance.balanceCredits, 100);
});

test("start session locks credits from wallet and activates hardware", async () => {
  const app = createApp();

  await app.saga.topUpWallet({
    userId: "rider_start",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: `topup-${crypto.randomUUID()}`
  });

  const intent = await app.saga.createIntent({
    riderId: "rider_start",
    hostId: "host_start",
    outletId: "outlet_start",
    depositCredits: 50,
    idempotencyKey: "intent-start"
  });

  const start = await app.saga.startSession({
    sessionId: intent.session.id,
    idempotencyKey: `start-${intent.session.id}`
  });

  assert.equal(start.session.status, "active");
  assert.ok(start.session.escrowLockTxHash);
  assert.ok(start.hardware);

  const balance = await app.saga.getWalletBalance("rider_start");
  assert.equal(balance.balanceCredits, 50); // 100 - 50 locked
});

test("start session rejects when wallet balance insufficient", async () => {
  const app = createApp();

  await app.saga.topUpWallet({
    userId: "rider_poor",
    amountCredits: 10,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: "topup-poor"
  });

  const intent = await app.saga.createIntent({
    riderId: "rider_poor",
    hostId: "host_poor",
    outletId: "outlet_poor",
    depositCredits: 50,
    idempotencyKey: "intent-poor"
  });

  try {
    await app.saga.startSession({
      sessionId: intent.session.id,
      idempotencyKey: `start-${intent.session.id}`
    });
    assert.fail("Expected startSession to throw");
  } catch (error) {
    // Error may be a plain Error with message containing the code
    assert.ok(error.message.includes("INSUFFICIENT_BALANCE") || error.code === "INSUFFICIENT_BALANCE");
  }
});

test("hardware activation failure refunds locked credits to wallet", async () => {
  const app = createApp();
  app.hardware.simulateNextOnFailure();

  await app.saga.topUpWallet({
    userId: "rider_fail",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: "topup-fail"
  });

  const intent = await app.saga.createIntent({
    riderId: "rider_fail",
    hostId: "host_fail",
    outletId: "outlet_fail",
    depositCredits: 50,
    idempotencyKey: "intent-fail"
  });

  const result = await app.saga.startSession({
    sessionId: intent.session.id,
    idempotencyKey: `start-${intent.session.id}`
  });

  assert.equal(result.session.status, "refunded_after_activation_failure");
  assert.ok(result.refund);

  // Credits should be back in wallet
  const balance = await app.saga.getWalletBalance("rider_fail");
  assert.equal(balance.balanceCredits, 100);
});

test("telemetry ingestion accepts cumulative energy", async () => {
  const app = createApp();
  const sessionId = await activeSession(app);

  const t1 = await app.saga.ingestTelemetry(sessionId, {
    energyWh: 500,
    currentAmp: 8,
    voltageV: 231,
    tempC: 41
  });
  assert.equal(t1.telemetry.energyWh, 500);

  const t2 = await app.saga.ingestTelemetry(sessionId, {
    energyWh: 1500,
    currentAmp: 12,
    voltageV: 230,
    tempC: 43
  });
  assert.equal(t2.telemetry.energyWh, 1500);
});

test("safety trip stops session and settles", async () => {
  const app = createApp();
  const sessionId = await activeSession(app);

  const safety = await app.saga.ingestTelemetry(sessionId, {
    energyWh: 1500,
    currentAmp: 18,
    voltageV: 231,
    tempC: 75 // exceeds max 70
  });

  assert.equal(safety.session.status, "settled");
  assert.equal(safety.session.stopKind, "safety_trip");
  assert.ok(safety.settlement.hostShareCredits >= 0);
});

test("auto-threshold stop when amount due reaches deposit", async () => {
  const app = createApp();
  const sessionId = await activeSession(app);

  // Energy that would make amount_due >= deposit (50 credits @ 18 credits/kWh)
  // 50 * 1000 / 18 = ~2778 Wh
  const auto = await app.saga.ingestTelemetry(sessionId, {
    energyWh: 3000,
    currentAmp: 16,
    voltageV: 230,
    tempC: 40
  });

  assert.equal(auto.session.status, "settled");
  assert.equal(auto.session.stopKind, "auto_threshold");
});

test("user stop settles session", async () => {
  const app = createApp();
  const sessionId = await activeSession(app);

  const stopped = await app.saga.stopSession({
    sessionId,
    reason: "user_stop",
    idempotencyKey: "stop-user"
  });

  assert.equal(stopped.session.status, "settled");
  assert.equal(stopped.session.stopKind, "manual");
});

test("double stop is idempotent", async () => {
  const app = createApp();
  const sessionId = await activeSession(app);

  const first = await app.saga.stopSession({
    sessionId,
    reason: "user_stop",
    idempotencyKey: "stop-idem"
  });
  const second = await app.saga.stopSession({
    sessionId,
    reason: "user_stop",
    idempotencyKey: "stop-idem"
  });

  assert.deepEqual(second.session, first.session);
});

test("session audit combines state, telemetry, hardware, contract, events", async () => {
  const app = createApp();
  const sessionId = await activeSession(app);

  await app.saga.ingestTelemetry(sessionId, {
    energyWh: 500,
    currentAmp: 8,
    voltageV: 231,
    tempC: 41
  });

  const audit = await app.saga.getSessionAudit(sessionId);
  assert.equal(audit.session.id, sessionId);
  assert.equal(audit.contract.status, "locked");
  assert.equal(audit.telemetry.length, 1);
  assert.equal(audit.hardwareCommands.length, 1);
  assert.ok(audit.events.some((event) => event.type === "chain.escrow_locked"));
  assert.ok(audit.events.some((event) => event.type === "telemetry.received"));
});

// ============================ Reconciliation ============================

test("escrow lock failure leaves recoverable session and reconciliation activates it", async () => {
  const app = createApp();

  await app.saga.topUpWallet({
    userId: "rider_recover",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: "topup-recover"
  });

  const intent = await app.saga.createIntent({
    riderId: "rider_recover",
    hostId: "host_recover",
    outletId: "outlet_recover",
    depositCredits: 50,
    idempotencyKey: "intent-recover"
  });

  app.chain.simulateNextLockFailure();
  await assert.rejects(
    () => app.saga.startSession({
      sessionId: intent.session.id,
      idempotencyKey: `start-${intent.session.id}`
    }),
    { code: "CHAIN_LOCK_FAILED" }
  );

  const session = await app.saga.getSession(intent.session.id);
  assert.equal(session.session.status, "lock_failed");

  // Simulate reconciliation
  await app.saga.reconcileSession(intent.session.id);
  const recovered = await app.saga.getSession(intent.session.id);
  assert.equal(recovered.session.status, "active");
});

test("settlement failure leaves pending settlement and reconciliation completes it", async () => {
  const app = createApp();
  const sessionId = await activeSession(app);
  app.chain.simulateNextSettleFailure();

  await assert.rejects(
    () => app.saga.stopSession({
      sessionId,
      reason: "user_stop",
      idempotencyKey: "stop-settle-fail"
    }),
    { code: "CHAIN_SETTLE_FAILED" }
  );

  const stuck = await app.saga.getSession(sessionId);
  assert.equal(stuck.session.status, "stopping");

  await app.saga.reconcileSession(sessionId);
  const recovered = await app.saga.getSession(sessionId);
  assert.equal(recovered.session.status, "settled");
});

test("batch reconciliation scans and recovers all recoverable sessions", async () => {
  const app = createApp();

  const riders = ["r1", "r2", "r3"];
  for (const rider of riders) {
    await app.saga.topUpWallet({
      userId: rider,
      amountCredits: 100,
      paymentId: `pay_${rider}`,
      idempotencyKey: `topup-${rider}`
    });

    const intent = await app.saga.createIntent({
      riderId: rider,
      hostId: "h1",
      outletId: "o1",
      depositCredits: 50,
      idempotencyKey: `intent-${rider}`
    });

    // Simulate chain lock failure for each session
    app.chain.simulateNextLockFailure();
    try {
      await app.saga.startSession({
        sessionId: intent.session.id,
        idempotencyKey: `start-${intent.session.id}`
      });
    } catch {}
  }

  const result = await app.saga.reconcileAll();
  assert.equal(result.scanned, 3);
  assert.equal(result.recovered, 3);
});

test("HTTP reconcile endpoint recovers a stuck session", async () => {
  const { createHttpServer } = await import("../src/http-server.js");
  const app = createApp();
  const server = createHttpServer(app);

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    await app.saga.topUpWallet({
      userId: "rider_http",
      amountCredits: 100,
      paymentId: `pay_${crypto.randomUUID()}`,
      idempotencyKey: "topup-http"
    });

    const intent = await app.saga.createIntent({
      riderId: "rider_http",
      hostId: "host_http",
      outletId: "outlet_http",
      depositCredits: 50,
      idempotencyKey: "intent-http"
    });

    app.chain.simulateNextLockFailure();
    try {
      await app.saga.startSession({
        sessionId: intent.session.id,
        idempotencyKey: `start-${intent.session.id}`
      });
    } catch {}

    const reconcileRes = await fetch(`${baseUrl}/sessions/${intent.session.id}/reconcile`, {
      method: "POST"
    });
    const body = await reconcileRes.json();
    assert.equal(body.data.session.status, "active");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

// ============================ Idempotency ============================

test("duplicate intent with same idempotency key is idempotent", async () => {
  const app = createApp();

  await app.saga.topUpWallet({
    userId: "rider_idem",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: "topup-idem"
  });

  const first = await app.saga.createIntent({
    riderId: "rider_idem",
    hostId: "host_idem",
    outletId: "outlet_idem",
    depositCredits: 50,
    idempotencyKey: "intent-idem"
  });

  const second = await app.saga.createIntent({
    riderId: "rider_idem",
    hostId: "host_idem",
    outletId: "outlet_idem",
    depositCredits: 50,
    idempotencyKey: "intent-idem"
  });

  assert.equal(second.session.id, first.session.id);
});

test("idempotency key cannot be reused with different payload", async () => {
  const app = createApp();

  await app.saga.topUpWallet({
    userId: "rider_idem",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: "topup-idem2"
  });

  await app.saga.createIntent({
    riderId: "rider_idem",
    hostId: "host_idem",
    outletId: "outlet_idem",
    depositCredits: 50,
    idempotencyKey: "intent-idem2"
  });

  await assert.rejects(
    () =>
      app.saga.createIntent({
        riderId: "rider_idem",
        hostId: "host_idem",
        outletId: "outlet_idem2",
        depositCredits: 50,
        idempotencyKey: "intent-idem2"
      }),
    { code: "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD" }
  );
});

// ============================ Retry Logic ============================

test("transient chain lock failure is retried and recovers", async () => {
  const app = createApp({
    env: {
      GRIDSHARE_ADAPTER_RETRY_ATTEMPTS: "2",
      GRIDSHARE_ADAPTER_RETRY_BASE_DELAY_MS: "1"
    }
  });
  app.chain.simulateNextLockFailure();

  await app.saga.topUpWallet({
    userId: "rider_retry",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: "topup-retry"
  });

  const intent = await app.saga.createIntent({
    riderId: "rider_retry",
    hostId: "host_retry",
    outletId: "outlet_retry",
    depositCredits: 50,
    idempotencyKey: "intent-retry"
  });

  const result = await app.saga.startSession({
    sessionId: intent.session.id,
    idempotencyKey: `start-${intent.session.id}`
  });

  assert.equal(result.session.status, "active");
  const eventTypes = app.eventBus.list().map((event) => event.type);
  assert.ok(eventTypes.includes("adapter.retry_scheduled"));
  assert.ok(eventTypes.includes("adapter.retry_succeeded"));
  assert.ok(eventTypes.indexOf("adapter.retry_succeeded") < eventTypes.indexOf("hardware.switch_changed"));
});

test("transient hardware activation failure is retried before refund fallback", async () => {
  const app = createApp({
    env: {
      GRIDSHARE_ADAPTER_RETRY_ATTEMPTS: "2",
      GRIDSHARE_ADAPTER_RETRY_BASE_DELAY_MS: "1"
    }
  });
  app.hardware.simulateNextOnFailure();

  await app.saga.topUpWallet({
    userId: "rider_retry_hw",
    amountCredits: 100,
    paymentId: `pay_${crypto.randomUUID()}`,
    idempotencyKey: "topup-retry-hw"
  });

  const intent = await app.saga.createIntent({
    riderId: "rider_retry_hw",
    hostId: "host_retry_hw",
    outletId: "outlet_retry_hw",
    depositCredits: 50,
    idempotencyKey: "intent-retry-hw"
  });

  const result = await app.saga.startSession({
    sessionId: intent.session.id,
    idempotencyKey: `start-${intent.session.id}`
  });

  assert.equal(result.session.status, "active");
  assert.equal(app.hardware.getSwitchState("outlet_retry_hw"), true);
  assert.equal(app.hardware.getCommands({ sessionId: intent.session.id }).length, 1);

  const retryEvents = app.eventBus.list({ type: "adapter.retry_scheduled" });
  assert.equal(retryEvents[0].payload.operation, "hardware.switch_on");
});

test("HTTP audit endpoint returns session evidence bundle", async () => {
  const { createHttpServer } = await import("../src/http-server.js");
  const app = createApp();
  const server = createHttpServer(app);

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    const sessionId = await activeSession(app);
    const response = await fetch(`${baseUrl}/sessions/${sessionId}/audit`);
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.data.session.id, sessionId);
    assert.ok(body.data.hardwareCommands.length >= 1);
    assert.ok(body.data.events.some((event) => event.type === "session.activated"));
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

// ============================ Demo ============================

test("judge demo flow runs the full story and emits demo milestones", async () => {
  const app = createApp({ env: { GRIDSHARE_DEMO_MODE: "true", GRIDSHARE_DEMO_STEP_DELAY_MS: "0" } });
  const data = await app.demo.run({});

  assert.ok(data.summary);
  assert.equal(data.summary.finalStatus, "settled");
  assert.ok(data.summary.settlement);
  assert.ok(data.summary.hostEarnedCredits > 0);
  assert.ok(data.audit);
});

test("judge demo flow is disabled when demo mode is off", async () => {
  const app = createApp({ env: { GRIDSHARE_DEMO_MODE: "false" } });

  await assert.rejects(
    () => app.demo.run({}),
    { code: "DEMO_MODE_DISABLED" }
  );
});

test("HTTP judge demo endpoint returns complete demo summary", async () => {
  const { createHttpServer } = await import("../src/http-server.js");
  const app = createApp({ env: { GRIDSHARE_DEMO_MODE: "true", GRIDSHARE_DEMO_STEP_DELAY_MS: "0" } });
  const server = createHttpServer(app);

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    const response = await fetch(`${baseUrl}/demo/judge-flow`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({})
    });
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.ok(body.data.summary);
    assert.equal(body.data.summary.finalStatus, "settled");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("HTTP judge demo endpoint returns 403 when demo mode is disabled", async () => {
  const { createHttpServer } = await import("../src/http-server.js");
  const app = createApp({ env: { GRIDSHARE_DEMO_MODE: "false" } });
  const server = createHttpServer(app);

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    const response = await fetch(`${baseUrl}/demo/judge-flow`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({})
    });
    assert.equal(response.status, 403);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

// ============================ HTTP Edge Cases ============================

test("HTTP edge rejects oversized request bodies", async () => {
  const { createHttpServer } = await import("../src/http-server.js");
  const app = createApp({ config: { requestBodyLimitBytes: 100 } });
  const server = createHttpServer(app);

  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    const huge = "x".repeat(200);
    const response = await fetch(`${baseUrl}/sessions/intent`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ riderId: "r", hostId: "h", outletId: "o", depositCredits: 10, data: huge })
    });
    assert.equal(response.status, 413);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}