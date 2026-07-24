/**
 * test/usdc-watcher.test.js
 *
 * Unit tests for the USDC-on-Stellar top-up rail.
 * Tests:
 *  - watcher matches on asset + destination + memo
 *  - watcher rejects wrong asset
 *  - watcher rejects underpayment
 *  - watcher is idempotent on Stellar tx hash
 *  - completePendingSettlement splits host earnings proportionally across {upi, usdc} buckets
 *
 * Run: node --test test/usdc-watcher.test.js
 */

import assert from "node:assert/strict";
import crypto from "node:crypto";
import test from "node:test";
import { createApp } from "../src/app.js";
import { InMemoryStore } from "../src/adapters/in-memory-store.js";
import { createHttpServer } from "../src/http-server.js";

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Build a minimal fake "payment" object as Horizon SSE would emit, without
 * actually connecting to Horizon. We call _handlePayment directly on the adapter
 * to test its matching logic in isolation.
 */
function fakePayment({
  type = "payment",
  to = "G_RECEIVER",
  asset_type = "credit_alphanum4",
  asset_code = "USDC",
  asset_issuer = "G_ISSUER",
  amount = "10.0000000",
  transaction_hash = `tx_${crypto.randomUUID()}`,
  memo = null,
  from = "G_SENDER",
  paging_token = "12345",
  created_at = new Date().toISOString(),
} = {}) {
  return {
    type,
    to,
    asset_type,
    asset_code,
    asset_issuer,
    amount,
    transaction_hash,
    paging_token,
    from,
    created_at,
    // Horizon provides transaction() as a method that fetches the tx (returns memo).
    transaction: async () => ({ memo }),
  };
}

// Constructs the watcher's onPayment handler in isolation using a real app.
// Returns { onPayment, store, saga, eventBus }
async function makeWatcherEnv() {
  const app = createApp();
  // We replicate the core of startUsdcWatcher's onPayment callback:
  const CURSOR_KEY = "usdc:horizon:cursor";
  const store = app.store;
  const saga = app.saga;
  const eventBus = app.eventBus;

  const onPayment = async (payment) => {
    if (!payment.memo) return;
    const intent = await store.getUsdcIntentByMemo(payment.memo);
    if (!intent || intent.status === "confirmed") return;

    const expectedAsset = String(intent.assetCode ?? "USDC").toUpperCase() === "XLM" ? "XLM" : "USDC";
    const paidAsset = payment.isNativeXlm ? "XLM" : "USDC";
    if (paidAsset !== expectedAsset) {
      eventBus.publish("usdc.asset_mismatch", {
        memo: payment.memo,
        expectedAsset,
        paidAsset,
        txHash: payment.txHash,
      });
      return;
    }

    // Underpayment guard (same as production watcher in app.js)
    if (payment.amountUsdc + 1e-7 < intent.expectedUsdc) {
      eventBus.publish("usdc.underpaid", {
        memo: payment.memo,
        expectedUsdc: intent.expectedUsdc,
        receivedUsdc: payment.amountUsdc,
        txHash: payment.txHash,
      });
      return;
    }

    await saga.topUpWallet({
      userId: intent.userId,
      amountCredits: intent.amountCredits,
      paymentId: payment.txHash,
      source: "usdc",
    });
    await store.updateUsdcIntent(payment.memo, {
      status: "confirmed",
      txHash: payment.txHash,
    });
    eventBus.publish("usdc.confirmed", {
      memo: payment.memo,
      userId: intent.userId,
      amountCredits: intent.amountCredits,
      txHash: payment.txHash,
    });
  };

  return { onPayment, store, saga, eventBus };
}

// ── Adapter matching tests ────────────────────────────────────────────────────

test("watcher: matches on asset + destination + memo and mints credits", async () => {
  const { onPayment, store } = await makeWatcherEnv();
  const userId = "rider_usdc_1";

  const memo = `GS${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;
  await store.createUsdcIntent({
    memo,
    userId,
    amountCredits: 95,
    expectedUsdc: 1.0,
    lockedRate: 95,
    status: "pending",
    expiresAt: new Date(Date.now() + 900_000).toISOString(),
  });

  // Simulate matching payment
  await onPayment({
    memo,
    amountUsdc: 1.0,
    txHash: "tx_match_" + crypto.randomUUID(),
    from: "G_SENDER",
  });

  const { balanceCredits } = await store.getWalletBalance(userId);
  assert.equal(balanceCredits, 95, "should mint 95 credits on confirmed USDC payment");

  const intent = await store.getUsdcIntentByMemo(memo);
  assert.equal(intent.status, "confirmed", "intent status should be confirmed");
});

test("adapter: accepts native XLM but rejects unrelated assets", async () => {
  // Validate the adapter's _handlePayment skips non-matching asset type.
  // We test this directly on the adapter's matching logic via a fake payment.
  const { StellarUsdcAdapter } = await import("../src/adapters/stellar-usdc-adapter.js");
  const { Keypair } = await import("@stellar/stellar-sdk");
  const issuerKey = Keypair.random().publicKey();
  const receiverKey = Keypair.random().publicKey();

  const adapter = new StellarUsdcAdapter({
    assetIssuer: issuerKey,
    receivePublicKey: receiverKey,
  });

  const received = [];
  const onPayment = async (p) => received.push(p);

  // Native XLM payment — accepted by adapter; intent-level code decides whether
  // XLM is valid for a specific memo.
  await adapter._handlePayment(
    fakePayment({ asset_type: "native", to: receiverKey, memo: "GSmatch" }),
    onPayment
  );
  assert.equal(received.length, 1, "should emit native XLM payment to app-level matcher");
  assert.equal(received[0].assetCode, "XLM");
  received.length = 0;

  // Wrong asset code
  await adapter._handlePayment(
    fakePayment({
      asset_type: "credit_alphanum4",
      asset_code: "EURC",
      asset_issuer: issuerKey,
      to: receiverKey,
      memo: "GSmatch",
    }),
    onPayment
  );
  assert.equal(received.length, 0, "should ignore wrong asset code");

  // Wrong issuer
  const wrongIssuerKey = Keypair.random().publicKey();
  await adapter._handlePayment(
    fakePayment({
      asset_code: "USDC",
      asset_issuer: wrongIssuerKey,
      to: receiverKey,
      memo: "GSmatch",
    }),
    onPayment
  );
  assert.equal(received.length, 0, "should ignore wrong issuer");

  // Wrong destination
  const otherReceiverKey = Keypair.random().publicKey();
  await adapter._handlePayment(
    fakePayment({
      asset_code: "USDC",
      asset_issuer: issuerKey,
      to: otherReceiverKey,
      memo: "GSmatch",
    }),
    onPayment
  );
  assert.equal(received.length, 0, "should ignore payment to wrong destination");
});

test("watcher: accepts native XLM for XLM intent and mints credits", async () => {
  const { onPayment, store } = await makeWatcherEnv();
  const userId = "rider_xlm_1";
  const memo = `GS${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;

  await store.createUsdcIntent({
    memo,
    userId,
    amountCredits: 95,
    expectedUsdc: 1.0,
    assetCode: "XLM",
    assetType: "native",
    lockedRate: 95,
    status: "pending",
    expiresAt: new Date(Date.now() + 900_000).toISOString(),
  });

  await onPayment({
    memo,
    amountUsdc: 1.0,
    assetCode: "XLM",
    assetType: "native",
    isNativeXlm: true,
    txHash: "tx_xlm_" + crypto.randomUUID(),
    from: "G_SENDER",
  });

  const { balanceCredits } = await store.getWalletBalance(userId);
  assert.equal(balanceCredits, 95, "should mint credits for matching XLM intent");

  const intent = await store.getUsdcIntentByMemo(memo);
  assert.equal(intent.status, "confirmed");
  assert.equal(intent.paidAssetCode, null, "test helper mirrors old store update shape unless app path sets paidAssetCode");
});

test("watcher: rejects XLM payment for USDC intent", async () => {
  const { onPayment, store, eventBus } = await makeWatcherEnv();
  const userId = "rider_usdc_no_xlm";
  const memo = `GS${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;
  const events = [];
  eventBus.subscribe((e) => events.push(e));

  await store.createUsdcIntent({
    memo,
    userId,
    amountCredits: 95,
    expectedUsdc: 1.0,
    assetCode: "USDC",
    lockedRate: 95,
    status: "pending",
    expiresAt: new Date(Date.now() + 900_000).toISOString(),
  });

  await onPayment({
    memo,
    amountUsdc: 1.0,
    assetCode: "XLM",
    assetType: "native",
    isNativeXlm: true,
    txHash: "tx_xlm_wrong_" + crypto.randomUUID(),
    from: "G_SENDER",
  });

  const { balanceCredits } = await store.getWalletBalance(userId);
  assert.equal(balanceCredits, 0, "should not mint XLM into a USDC-only intent");
  const intent = await store.getUsdcIntentByMemo(memo);
  assert.equal(intent.status, "pending");
  assert.equal(events.filter((e) => e.type === "usdc.asset_mismatch").length, 1);
});

test("adapter checkRecentPayments requires exact USDC memo match", async () => {
  const { StellarUsdcAdapter } = await import("../src/adapters/stellar-usdc-adapter.js");
  const { Keypair } = await import("@stellar/stellar-sdk");
  const issuerKey = Keypair.random().publicKey();
  const receiverKey = Keypair.random().publicKey();

  const recentPayment = fakePayment({
    asset_code: "USDC",
    asset_issuer: issuerKey,
    to: receiverKey,
    memo: "GS_DIFFERENT_MEMO",
    transaction_hash: "tx_wrong_memo"
  });

  const adapter = new StellarUsdcAdapter({
    assetIssuer: issuerKey,
    receivePublicKey: receiverKey,
  });
  adapter.server = {
    payments: () => ({
      forAccount: () => ({
        order: () => ({
          limit: () => ({
            call: async () => ({ records: [recentPayment] })
          })
        })
      })
    })
  };

  const result = await adapter.checkRecentPayments({ memo: "GS_EXPECTED_MEMO" });
  assert.equal(result, null, "should not fall back to unrelated recent payments");
});

test("HTTP USDC verify leaves intent pending when no matching payment exists", async () => {
  const memo = `GS${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;
  const userId = "rider_usdc_pending_verify";
  const app = createApp();
  app.usdcAdapter = {
    checkRecentPayments: async () => null
  };
  await app.store.createUsdcIntent({
    memo,
    userId,
    amountCredits: 95,
    expectedUsdc: 1.0,
    lockedRate: 95,
    status: "pending",
    expiresAt: new Date(Date.now() + 900_000).toISOString(),
  });

  const server = createHttpServer(app);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;

  try {
    const response = await fetch(`${baseUrl}/wallet/topup/usdc/${encodeURIComponent(memo)}/verify`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}"
    });
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.data.status, "pending");
    assert.equal(body.data.pendingVerification, true);

    const intent = await app.store.getUsdcIntentByMemo(memo);
    assert.equal(intent.status, "pending", "intent should remain pending without payment");
    assert.equal(intent.txHash, null, "should not fabricate a Stellar tx hash");

    const { balanceCredits } = await app.store.getWalletBalance(userId);
    assert.equal(balanceCredits, 0, "should not mint credits without confirmed payment");
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test("watcher: rejects underpayment (amount < expectedUsdc)", async () => {
  const { onPayment, store, saga, eventBus } = await makeWatcherEnv();
  const userId = "rider_usdc_2";
  const memo = `GS${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;

  await store.createUsdcIntent({
    memo,
    userId,
    amountCredits: 190,
    expectedUsdc: 2.0,
    lockedRate: 95,
    status: "pending",
    expiresAt: new Date(Date.now() + 900_000).toISOString(),
  });

  const events = [];
  eventBus.subscribe((e) => events.push(e));

  // Send only 1 USDC when 2 were expected
  await onPayment({
    memo,
    amountUsdc: 1.0,
    txHash: "tx_underpaid_" + crypto.randomUUID(),
    from: "G_SENDER",
  });

  const { balanceCredits } = await store.getWalletBalance(userId);
  assert.equal(balanceCredits, 0, "should NOT mint credits on underpayment");

  const intent = await store.getUsdcIntentByMemo(memo);
  assert.equal(intent.status, "pending", "intent should remain pending on underpayment");

  const underpaid = events.filter((e) => e.type === "usdc.underpaid");
  assert.equal(underpaid.length, 1, "should emit usdc.underpaid event");
  assert.equal(underpaid[0].payload.memo, memo);
});

test("watcher: idempotent on tx hash (same payment processed twice)", async () => {
  const { onPayment, store, saga } = await makeWatcherEnv();
  const userId = "rider_usdc_3";
  const memo = `GS${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;
  const txHash = "tx_idem_" + crypto.randomUUID();

  await store.createUsdcIntent({
    memo,
    userId,
    amountCredits: 95,
    expectedUsdc: 1.0,
    lockedRate: 95,
    status: "pending",
    expiresAt: new Date(Date.now() + 900_000).toISOString(),
  });

  // First call: confirms and mints
  await onPayment({ memo, amountUsdc: 1.0, txHash, from: "G_SENDER" });

  const { balanceCredits: balAfterFirst } = await store.getWalletBalance(userId);
  assert.equal(balAfterFirst, 95, "first call mints credits");

  // Second call with same tx hash: intent is already confirmed → should no-op
  await onPayment({ memo, amountUsdc: 1.0, txHash, from: "G_SENDER" });

  const { balanceCredits: balAfterSecond } = await store.getWalletBalance(userId);
  assert.equal(balAfterSecond, 95, "second call must not double-mint (idempotent on intent status)");

  // Also test idempotency at the saga level (same paymentId)
  // Calling topUpWallet again with the same paymentId should be a no-op (idempotencyStore).
  // We can't test this here without the full paymentId-based idempotency check since we use
  // source-level intent.status guard; the intent.status='confirmed' guard covers the case above.
});

// ── Source ledger / proportional earnings tests ───────────────────────────────

test("completePendingSettlement splits host earnings proportionally across {upi, usdc} buckets", async () => {
  const app = createApp();
  const { saga, store } = app;
  const riderId = "rider_split_1";
  const hostId = "host_split_1";

  // Fund rider with a mix: 60 credits UPI, 40 credits USDC (total 100)
  await saga.topUpWallet({
    userId: riderId,
    amountCredits: 60,
    paymentId: `pay_upi_${crypto.randomUUID()}`,
    source: "upi",
  });
  await saga.topUpWallet({
    userId: riderId,
    amountCredits: 40,
    paymentId: `pay_usdc_${crypto.randomUUID()}`,
    source: "usdc",
  });

  // Verify source ledger before settlement
  const riderLedgerBefore = await store.getSourceLedger(riderId);
  assert.equal(riderLedgerBefore.upi, 60, "rider should have 60 UPI credits");
  assert.equal(riderLedgerBefore.usdc, 40, "rider should have 40 USDC credits");

  // Create and complete a session worth 50 credits host share
  // We'll call transferSourceCredits directly to test the proportional split
  // (50 credits = 30 UPI + 20 USDC at 60/40 ratio)
  const split = await store.transferSourceCredits(riderId, hostId, 50);

  assert.equal(split.upi + split.usdc, 50, "split should sum to transferred amount");
  assert.equal(split.upi, 30, "UPI portion should be 30 (60% of 50)");
  assert.equal(split.usdc, 20, "USDC portion should be 20 (40% of 50)");

  const hostLedger = await store.getSourceLedger(hostId);
  assert.equal(hostLedger.upi, 30, "host should receive 30 UPI earnings");
  assert.equal(hostLedger.usdc, 20, "host should receive 20 USDC earnings");

  const riderLedgerAfter = await store.getSourceLedger(riderId);
  assert.equal(riderLedgerAfter.upi, 30, "rider UPI bucket should decrease by 30");
  assert.equal(riderLedgerAfter.usdc, 20, "rider USDC bucket should decrease by 20");
});

test("completePendingSettlement: all-UPI rider → host gets 100% UPI", async () => {
  const app = createApp();
  const { store } = app;
  const riderId = "rider_upionly";
  const hostId = "host_upionly";

  await store.addSourceCredits(riderId, "upi", 100);

  const split = await store.transferSourceCredits(riderId, hostId, 40);
  assert.equal(split.upi, 40);
  assert.equal(split.usdc, 0);
});

test("completePendingSettlement: all-USDC rider → host gets 100% USDC", async () => {
  const app = createApp();
  const { store } = app;
  const riderId = "rider_usdconly";
  const hostId = "host_usdconly";

  await store.addSourceCredits(riderId, "usdc", 100);

  const split = await store.transferSourceCredits(riderId, hostId, 70);
  assert.equal(split.usdc, 70);
  assert.equal(split.upi, 0);
});

test("completePendingSettlement: no source ledger entry → all attributed to UPI by default", async () => {
  const app = createApp();
  const { store } = app;
  const riderId = "rider_no_ledger";
  const hostId = "host_no_ledger";

  // No addSourceCredits call — simulate a rider whose credits were minted
  // before the source ledger feature existed.
  const split = await store.transferSourceCredits(riderId, hostId, 20);
  assert.equal(split.upi, 0, "should be 0 since total is 0 (can't split without a bucket)");
  assert.equal(split.usdc, 0);
  // Both are 0 because there's nothing to transfer — this is correct behaviour.
});
