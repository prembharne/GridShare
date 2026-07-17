import { DomainError } from "./core/errors.js";

function booleanFromEnv(env, name, fallback) {
  const raw = env[name];
  if (raw === undefined || raw === "") return fallback;
  if (["true", "1", "yes", "on"].includes(String(raw).toLowerCase())) return true;
  if (["false", "0", "no", "off"].includes(String(raw).toLowerCase())) return false;
  throw new DomainError("INVALID_CONFIG", `${name} must be a boolean.`, { name, value: raw });
}

function integerFromEnv(env, name, fallback, { min, max } = {}) {
  const raw = env[name];
  const value = raw === undefined || raw === "" ? fallback : Number(raw);

  if (!Number.isInteger(value)) {
    throw new DomainError("INVALID_CONFIG", `${name} must be an integer.`, { name, value: raw });
  }

  if (min !== undefined && value < min) {
    throw new DomainError("INVALID_CONFIG", `${name} must be at least ${min}.`, { name, value });
  }

  if (max !== undefined && value > max) {
    throw new DomainError("INVALID_CONFIG", `${name} must be at most ${max}.`, { name, value });
  }

  return value;
}

function stringFromEnv(env, name, fallback) {
  const raw = env[name];
  return raw === undefined || raw === "" ? fallback : raw;
}

function safeJsonParse(raw, name) {
  try {
    return JSON.parse(raw);
  } catch {
    throw new DomainError("INVALID_CONFIG", `${name} must be valid JSON.`, { name });
  }
}

export function loadConfig(env = process.env) {
  const config = {
    port: integerFromEnv(env, "PORT", 8080, { min: 1, max: 65535 }),
    requestBodyLimitBytes: integerFromEnv(env, "GRIDSHARE_REQUEST_BODY_LIMIT_BYTES", 1_048_576, { min: 1024 }),
    demoMode: booleanFromEnv(env, "GRIDSHARE_DEMO_MODE", env.NODE_ENV !== "production"),
    demoStepDelayMs: integerFromEnv(env, "GRIDSHARE_DEMO_STEP_DELAY_MS", 0, { min: 0, max: 10000 }),
    adapterRetryAttempts: integerFromEnv(env, "GRIDSHARE_ADAPTER_RETRY_ATTEMPTS", 1, { min: 1, max: 5 }),
    adapterRetryBaseDelayMs: integerFromEnv(env, "GRIDSHARE_ADAPTER_RETRY_BASE_DELAY_MS", 0, { min: 0, max: 5000 }),
    pricePerKwhCredits: integerFromEnv(env, "GRIDSHARE_PRICE_PER_KWH_CREDITS", 18, { min: 1 }),
    serviceFeeBps: integerFromEnv(env, "GRIDSHARE_SERVICE_FEE_BPS", 300, { min: 0, max: 10000 }),
    useRealAdapters: booleanFromEnv(env, "GRIDSHARE_USE_REAL_ADAPTERS", false),
    databaseUrl: stringFromEnv(env, "DATABASE_URL", "postgres://gridshare:gridshare_dev_password@localhost:5432/gridshare"),
    stellarRpcUrl: stringFromEnv(env, "STELLAR_RPC_URL", "https://soroban-testnet.stellar.org"),
    stellarNetworkPassphrase: stringFromEnv(env, "STELLAR_NETWORK_PASSPHRASE", "Test SDF Network ; September 2015"),
    sorobanContractId: stringFromEnv(env, "SOROBAN_CONTRACT_ID", ""),
    stellarRelayerSecretKey: stringFromEnv(env, "STELLAR_RELAYER_SECRET_KEY", ""),
    stellarAddressMap: env.STELLAR_ADDRESS_MAP ? safeJsonParse(env.STELLAR_ADDRESS_MAP, "STELLAR_ADDRESS_MAP") : {},
    adminApiKey: stringFromEnv(env, "GRIDSHARE_ADMIN_API_KEY", ""),
    tuyaClientId: stringFromEnv(env, "TUYA_CLIENT_ID", ""),
    tuyaClientSecret: stringFromEnv(env, "TUYA_CLIENT_SECRET", ""),
    tuyaEndpoint: stringFromEnv(env, "TUYA_ENDPOINT", "https://openapi.tuyacn.com"),
    tuyaDeviceId: stringFromEnv(env, "TUYA_DEVICE_ID", ""),
    tuyaWebhookSecret: stringFromEnv(env, "TUYA_WEBHOOK_SECRET", ""),
    razorpayKeyId: stringFromEnv(env, "RAZORPAY_KEY_ID", ""),
    razorpayKeySecret: stringFromEnv(env, "RAZORPAY_KEY_SECRET", ""),
    razorpayWebhookSecret: stringFromEnv(env, "RAZORPAY_WEBHOOK_SECRET", ""),
    safety: {
      maxCurrentAmp: integerFromEnv(env, "GRIDSHARE_MAX_CURRENT_AMP", 16, { min: 1 }),
      maxTempC: integerFromEnv(env, "GRIDSHARE_MAX_TEMP_C", 70, { min: 1 }),
      minVoltageV: integerFromEnv(env, "GRIDSHARE_MIN_VOLTAGE_V", 180, { min: 1 }),
      maxVoltageV: integerFromEnv(env, "GRIDSHARE_MAX_VOLTAGE_V", 260, { min: 1 })
    },
    eventLogPath: env.GRIDSHARE_EVENT_LOG_PATH || null
  };

  if (config.safety.minVoltageV >= config.safety.maxVoltageV) {
    throw new DomainError("INVALID_CONFIG", "GRIDSHARE_MIN_VOLTAGE_V must be lower than GRIDSHARE_MAX_VOLTAGE_V.", {
      minVoltageV: config.safety.minVoltageV,
      maxVoltageV: config.safety.maxVoltageV
    });
  }

  if (config.useRealAdapters) {
    const required = [
      ["databaseUrl", config.databaseUrl],
      ["sorobanContractId", config.sorobanContractId],
      ["stellarRelayerSecretKey", config.stellarRelayerSecretKey],
      ["tuyaClientId", config.tuyaClientId],
      ["tuyaClientSecret", config.tuyaClientSecret],
      ["tuyaDeviceId", config.tuyaDeviceId],
      ["razorpayKeyId", config.razorpayKeyId],
      ["razorpayKeySecret", config.razorpayKeySecret]
    ];

    for (const [name, value] of required) {
      if (!value) {
        throw new DomainError("INVALID_CONFIG", `Real adapters enabled but ${name} is not configured.`, { name });
      }
    }
  }

  return config;
}