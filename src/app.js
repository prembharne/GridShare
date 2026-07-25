import { createRequire } from "node:module";
import { loadConfig } from "./config.js";
import { JsonlEventSink } from "./adapters/jsonl-event-sink.js";
import { MockChainRelayer } from "./adapters/mock-chain-relayer.js";
import { MockHardwareBridge } from "./adapters/mock-hardware-bridge.js";
import { RetryingChainRelayer } from "./adapters/retrying-chain-relayer.js";
import { RetryingHardwareBridge } from "./adapters/retrying-hardware-bridge.js";
import { EventBus } from "./core/event-bus.js";
import { IdempotencyStore } from "./core/idempotency-store.js";
import { LockManager } from "./core/lock-manager.js";
import { RetryPolicy } from "./core/retry-policy.js";
import { InMemoryStore } from "./adapters/in-memory-store.js";
import { SafetyTripRuleEngine } from "./domain/safety-trip-rule-engine.js";
import { SessionSaga } from "./domain/session-saga.js";
import { SessionMeter } from "./domain/session-meter.js";

import { JudgeDemoService } from "./demo/judge-demo.js";
import { RealPaymentAdapter } from "./adapters/real-payment-adapter.js";
import { InMemoryUserRepository } from "./adapters/in-memory-user-repository.js";
import { OtpService } from "./domain/otp-service.js";
import { TextBeeSmsSender } from "./adapters/textbee-sms-sender.js";
import { FxRateAdapter } from "./adapters/fx-rate-adapter.js";
import { StellarUsdcAdapter } from "./adapters/stellar-usdc-adapter.js";
import { InstamojoAdapter } from "./adapters/instamojo-adapter.js";
import { UserWalletManager } from "./adapters/user-wallet-manager.js";
import { findOutlet } from "./domain/outlet-catalog.js";


// Lazy require so the heavy real-adapter SDKs (stellar-sdk, axios, razorpay,
// prisma) are only loaded when GRIDSHARE_USE_REAL_ADAPTERS=true. This keeps
// the default mock path runnable without those deps installed.
const require = createRequire(import.meta.url);

function withRetry(delegate, retryPolicy, Wrapper) {
  if (retryPolicy.attempts <= 1) {
    return delegate;
  }
  return new Wrapper({ delegate, retryPolicy });
}

export function createApp({ env = process.env, config = loadConfig(env) } = {}) {
  const eventBus = new EventBus({
    sinks: config.eventLogPath ? [new JsonlEventSink(config.eventLogPath)] : []
  });

  const retryPolicy = new RetryPolicy({
    attempts: config.adapterRetryAttempts,
    baseDelayMs: config.adapterRetryBaseDelayMs,
    eventBus
  });

  let store;
  let idempotencyStore;
  let lockManager;
  let chain;
  let hardware;
  let paymentAdapter;
  let users;
  let sharedPrisma = null;

  // Lazily create (and memoize) one PrismaClient shared by the store, lock
  // manager, and user repository so we don't open multiple connection pools.
  const getPrisma = () => {
    if (!sharedPrisma) {
      const { PrismaClient } = require("@prisma/client");
      sharedPrisma = new PrismaClient({ datasourceUrl: config.databaseUrl });
    }
    return sharedPrisma;
  };

  // ---- Persistence layer (store / idempotency / locks) ----
  // Driven by config.persist, NOT by useRealAdapters. This means the app can
  // durably store every session, telemetry sample, command, wallet top-up, and
  // payout to Postgres even while the chain/hardware/payments stay mocked.
  if (config.persist) {
    const prisma = getPrisma();
    const { PostgresStore } = require("./adapters/postgres-store.js");
    const { PostgresIdempotencyStore } = require("./core/postgres-idempotency-store.js");
    const { PostgresLockManager } = require("./core/postgres-lock-manager.js");

    store = new PostgresStore({ prisma });
    idempotencyStore = new PostgresIdempotencyStore({ store });
    lockManager = new PostgresLockManager({ prismaClient: prisma });
  } else {
    store = new InMemoryStore();
    idempotencyStore = new IdempotencyStore();
    lockManager = new LockManager();
  }

  // ---- External adapters (chain / hardware / payments) ----
  // Driven by config.useRealAdapters. Mock adapters keep credits, plug state,
  // and payments in-process; the persistence layer above still records the
  // resulting domain state to Postgres.
  if (config.useRealAdapters) {
    const { RealChainRelayer } = require("./adapters/real-chain-relayer.js");
    const { RealHardwareBridge } = require("./adapters/real-hardware-bridge.js");
    const { RealPaymentAdapter } = require("./adapters/real-payment-adapter.js");

    // Per-user custodial Stellar wallet address resolution.
    // Automatically generates + funds (Friendbot) a new Stellar account per user on testnet.
    const walletManager = new UserWalletManager({
      getKv: (key) => store.getKv?.(key),
      setKv: (key, val) => store.setKv?.(key, val),
      fundOnCreate: true,  // funds via Friendbot on testnet
      logger: console,
    });

    // Resolve address map from env (for pre-known identities) with dynamic fallback.
    const staticMap = config.stellarAddressMap ?? {};
    const resolveAddress = async (id) => {
      // 1. Static map from .env (e.g. { "rider_demo": "G...", "*": "G..." })
      if (staticMap[id] && typeof staticMap[id] === "string" && staticMap[id].length === 56) return staticMap[id];
      // 2. Already a Stellar G... address
      if (typeof id === "string" && id.startsWith("G") && id.length === 56) return id;
      // 3. Wildcard fallback from static map
      if (staticMap["*"] && typeof staticMap["*"] === "string" && staticMap["*"].length === 56) return staticMap["*"];
      // 4. Auto-generate custodial wallet (persisted in KV store)
      return walletManager.resolveAddress(id);
    };

    chain = new RealChainRelayer({
      rpcUrl: config.stellarRpcUrl,
      networkPassphrase: config.stellarNetworkPassphrase,
      contractId: config.sorobanContractId,
      relayerSecretKey: config.stellarRelayerSecretKey,
      tokenAddress: config.stellarTokenAddress,
      tokenUnitsPerPaise: config.stellarTokenUnitsPerPaise,
      pricePerKwhPaise: config.pricePerKwhPaise,
      platformFeeBps: config.platformFeeBps,
      resolveAddress,
      getSession: (sessionId) => {
        try { return store.requireSession(sessionId); } catch { return null; }
      },
      eventBus
    });

    hardware = new RealHardwareBridge({
      clientId: config.tuyaClientId,
      clientSecret: config.tuyaClientSecret,
      endpoint: config.tuyaEndpoint,
      deviceId: config.tuyaDeviceId,
      webhookSecret: config.tuyaWebhookSecret,
      // Per-outlet routing: map outletId -> its Tuya providerDeviceId from the
      // catalog so multiple plugs can be controlled independently. Unresolved
      // outlets fall back to the single configured tuyaDeviceId.
      resolveDeviceId: (outletId) => findOutlet(outletId)?.providerDeviceId,
      eventBus
    });


    paymentAdapter = new RealPaymentAdapter({
      keyId: config.razorpayKeyId,
      keySecret: config.razorpayKeySecret,
      webhookSecret: config.razorpayWebhookSecret,
      eventBus
    });
  } else {
    const rawChain = new MockChainRelayer({ eventBus });
    const rawHardware = new MockHardwareBridge({ eventBus });
    chain = withRetry(rawChain, retryPolicy, RetryingChainRelayer);
    hardware = withRetry(rawHardware, retryPolicy, RetryingHardwareBridge);
    paymentAdapter = new RealPaymentAdapter({
      keyId: "rzp_test_TF2vRTHMmIUlO3",
      keySecret: "5HjlT2I6eWxK0oTnVuV88jQT",
      webhookSecret: "test_secret",
      eventBus
    });
  }

  // User/host identity registry. Persist to Postgres whenever the persistence
  // layer is enabled (so real identity data reaches the admin dashboard).
  // Otherwise fall back to an in-memory registry so the default demo/test path
  // stays DB-free.
  if (config.persist) {
    const { PrismaUserRepository } = require("./adapters/prisma-user-repository.js");
    users = new PrismaUserRepository({ prisma: getPrisma() });
  } else {
    users = new InMemoryUserRepository();
  }

  // Phone OTP: real SMS via TextBee when credentials are configured, otherwise
  // a no-op sender so the mock/dev path still issues a code (logged, not sent).
  const smsSender = config.smsEnabled
    ? new TextBeeSmsSender({
      apiKey: config.textbeeApiKey,
      deviceId: config.textbeeDeviceId,
      baseUrl: config.textbeeBaseUrl
    })
    : null;

  const otpService = new OtpService({
    smsSender,
    ttlSeconds: config.otpTtlSeconds,
    // In production (SMS enabled), never expose code in response payload.
    exposeCodeInResponse: !config.smsEnabled,
    eventBus
  });

  const safetyEngine = new SafetyTripRuleEngine({
    hardware,
    eventBus,
    thresholds: config.safety
  });

  // FX rate provider (USD->INR) for USDC top-up quoting. Lightweight (fetch +
  // in-memory cache + fallback constant), so it's always constructed.
  const fxRate = new FxRateAdapter({
    url: config.fxRateUrl,
    fallbackRate: config.usdInrFallbackRate,
    cacheTtlSeconds: config.fxCacheTtlSeconds,
    eventBus
  });

  // Optional USDC-on-Stellar deposit rail. Classic-ledger asset watched via
  // Horizon, independent of the Soroban contract path.
  let usdcAdapter = null;
  if (config.usdcEnabled) {
    usdcAdapter = new StellarUsdcAdapter({
      horizonUrl: config.stellarHorizonUrl,
      networkPassphrase: config.stellarNetworkPassphrase,
      assetCode: config.usdcAssetCode,
      assetIssuer: config.usdcIssuer,
      receivePublicKey: config.usdcReceivePublic,
      receiveSecretKey: config.usdcReceiveSecret,
      eventBus
    });
  }

  const instamojoAdapter = new InstamojoAdapter({
    apiKey: config.instamojoApiKey || 'ee91608496268cc938dbbd8204c98aaf',
    authToken: config.instamojoAuthToken || '946d213101c26a9a590ef5ff25b00514',
    salt: config.instamojoSalt || 'dabd6f5ac69b40d7808c9b099e4fa717',
  });

  const saga = new SessionSaga({
    store,
    chain,
    hardware,
    eventBus,
    idempotencyStore,
    lockManager,
    safetyEngine,
    config: {
      pricePerKwhCredits: config.pricePerKwhCredits,
      serviceFeeBps: config.serviceFeeBps
    }
  });

  const demo = new JudgeDemoService({
    saga,
    eventBus,
    config
  });

  // Per-minute billing clock. Ticks active per-minute sessions on an interval,
  // auto-stopping them when the selected duration elapses or the accrued charge
  // reaches the locked deposit. Started explicitly via app.startSessionMeter().
  const sessionMeter = new SessionMeter({
    saga,
    store,
    eventBus,
    intervalMs: config.meterIntervalMs
  });

  const app = {

    config,
    eventBus,
    store,
    chain,
    hardware,
    paymentAdapter,
    instamojoAdapter,
    fxRate,
    usdcAdapter,
    users,
    otp: otpService,
    retryPolicy,
    safetyEngine,
    saga,
    sessionMeter,
    demo
  };

  app.startSessionMeter = () => sessionMeter.start();


  // Start the Horizon payment watcher: each confirmed USDC deposit whose memo
  // matches a pending intent is minted as credits via the SAME topUpWallet
  // path used by UPI. Idempotent on the Stellar tx hash. Cursor is persisted
  // so a restart never double-credits and never misses a payment.
  if (usdcAdapter) {
    app.startUsdcWatcher = () => startUsdcWatcher({ app, store, saga, usdcAdapter, eventBus });
  }

  return app;
}

async function startUsdcWatcher({ app, store, saga, usdcAdapter, eventBus }) {
  const CURSOR_KEY = "usdc:horizon:cursor";
  const cursor = (await store.getKv?.(CURSOR_KEY)) ?? "now";

  return usdcAdapter.watchPayments({
    cursor,
    onCursor: async (paging) => {
      if (store.setKv) await store.setKv(CURSOR_KEY, paging);
    },
    onPayment: async (payment) => {
      // payment: { memo, amountUsdc, txHash, from }
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
          txHash: payment.txHash
        });
        return;
      }

      // Require the rider to have sent at least the quoted USDC amount.
      if (payment.amountUsdc + 1e-7 < intent.expectedUsdc) {
        eventBus.publish("usdc.underpaid", {
          memo: payment.memo,
          expectedUsdc: intent.expectedUsdc,
          receivedUsdc: payment.amountUsdc,
          txHash: payment.txHash
        });
        return;
      }

      const intentPaymentId = `${payment.memo}:${payment.txHash}`;
      await saga.topUpWallet({
        userId: intent.userId,
        amountCredits: intent.amountCredits,
        paymentId: intentPaymentId,      // unique per intent: memo:txHash
        source: "usdc"
      });
      await store.updateUsdcIntent(payment.memo, { status: "confirmed", txHash: payment.txHash, paidAssetCode: paidAsset });
      eventBus.publish("usdc.confirmed", {
        memo: payment.memo,
        userId: intent.userId,
        amountCredits: intent.amountCredits,
        txHash: payment.txHash
      });
    }
  });
}
