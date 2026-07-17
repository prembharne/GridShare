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
import { JudgeDemoService } from "./demo/judge-demo.js";

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

  if (config.useRealAdapters) {
    const { PrismaClient } = require("@prisma/client");
    const prisma = new PrismaClient({ datasourceUrl: config.databaseUrl });

    const { PostgresStore } = require("./adapters/postgres-store.js");
    const { PostgresIdempotencyStore } = require("./core/postgres-idempotency-store.js");
    const { PostgresLockManager } = require("./core/postgres-lock-manager.js");
    const { RealChainRelayer } = require("./adapters/real-chain-relayer.js");
    const { RealHardwareBridge } = require("./adapters/real-hardware-bridge.js");
    const { RealPaymentAdapter } = require("./adapters/real-payment-adapter.js");

    store = new PostgresStore({ prisma });
    idempotencyStore = new PostgresIdempotencyStore({ store });
    lockManager = new PostgresLockManager({ prismaClient: prisma });

    chain = new RealChainRelayer({
      rpcUrl: config.stellarRpcUrl,
      networkPassphrase: config.stellarNetworkPassphrase,
      contractId: config.sorobanContractId,
      relayerSecretKey: config.stellarRelayerSecretKey,
      tokenAddress: config.stellarTokenAddress,
      tokenUnitsPerPaise: config.stellarTokenUnitsPerPaise,
      pricePerKwhPaise: config.pricePerKwhPaise,
      platformFeeBps: config.platformFeeBps,
      resolveAddress: (id) => config.stellarAddressMap[id] ?? config.stellarAddressMap["*"] ?? id,
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
      eventBus
    });

    paymentAdapter = new RealPaymentAdapter({
      keyId: config.razorpayKeyId,
      keySecret: config.razorpayKeySecret,
      webhookSecret: config.razorpayWebhookSecret,
      eventBus
    });
  } else {
    store = new InMemoryStore();
    idempotencyStore = new IdempotencyStore();
    lockManager = new LockManager();

    const rawChain = new MockChainRelayer({ eventBus });
    const rawHardware = new MockHardwareBridge({ eventBus });
    chain = withRetry(rawChain, retryPolicy, RetryingChainRelayer);
    hardware = withRetry(rawHardware, retryPolicy, RetryingHardwareBridge);
    paymentAdapter = null;
  }

  const safetyEngine = new SafetyTripRuleEngine({
    hardware,
    eventBus,
    thresholds: config.safety
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

  return {
    config,
    eventBus,
    store,
    chain,
    hardware,
    paymentAdapter,
    retryPolicy,
    safetyEngine,
    saga,
    demo
  };
}
