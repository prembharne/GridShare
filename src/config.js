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

function numberFromEnv(env, name, fallback, { min, max } = {}) {
  const raw = env[name];
  const value = raw === undefined || raw === "" ? fallback : Number(raw);

  if (!Number.isFinite(value)) {
    throw new DomainError("INVALID_CONFIG", `${name} must be a finite number.`, { name, value: raw });
  }

  if (min !== undefined && value < min) {
    throw new DomainError("INVALID_CONFIG", `${name} must be at least ${min}.`, { name, value });
  }

  if (max !== undefined && value > max) {
    throw new DomainError("INVALID_CONFIG", `${name} must be at most ${max}.`, { name, value });
  }

  return value;
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
    serviceFeeBps: integerFromEnv(env, "GRIDSHARE_SERVICE_FEE_BPS", 125, { min: 0, max: 10000 }),
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
    // ── Instamojo UPI payment gateway ──
    instamojoApiKey: stringFromEnv(env, "INSTAMOJO_API_KEY", ""),
    instamojoAuthToken: stringFromEnv(env, "INSTAMOJO_AUTH_TOKEN", ""),
    instamojoSalt: stringFromEnv(env, "INSTAMOJO_SALT", ""),
    // ── USDC-on-Stellar top-up ──
    usdcEnabled: booleanFromEnv(env, "STELLAR_USDC_ENABLED", true),
    stellarHorizonUrl: stringFromEnv(env, "STELLAR_HORIZON_URL", "https://horizon-testnet.stellar.org"),
    usdcIssuer: stringFromEnv(env, "STELLAR_USDC_ISSUER", "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5"),
    usdcAssetCode: stringFromEnv(env, "STELLAR_USDC_ASSET_CODE", "USDC"),
    usdcReceivePublic: stringFromEnv(env, "STELLAR_USDC_RECEIVE_PUBLIC", "GBQMCWALFHLRCF2LHDMTR5DVHRNWGXQHIF6MGALCTDTDHN6SPCEVKOKQ"),
    usdcReceiveSecret: stringFromEnv(env, "STELLAR_USDC_RECEIVE_SECRET", "SDWAMBMHF66ZMK7ZO65N6SPBOOLHJ2DEUEBIRQAZPMTB2GQCSDUYMC2H"),
    usdcIntentTtlSeconds: integerFromEnv(env, "GRIDSHARE_USDC_INTENT_TTL_SECONDS", 900, { min: 60, max: 86400 }),
    walletConnectProjectId: stringFromEnv(env, "WALLETCONNECT_PROJECT_ID", "3f139c3090412322bc70d9d894dadb38"),
    // FX: 1 USDC = 1 USD; credits = floor(usdc * usdInrRate). Live rate is
    // fetched from a free provider and cached; this is the fallback when the
    // provider is unreachable (currently ~95 INR/USD).
    usdInrFallbackRate: numberFromEnv(env, "GRIDSHARE_USDC_FALLBACK_RATE", 95, { min: 1, max: 1000 }),
    fxRateUrl: stringFromEnv(env, "GRIDSHARE_FX_RATE_URL", "https://open.er-api.com/v6/latest/USD"),
    fxCacheTtlSeconds: integerFromEnv(env, "GRIDSHARE_FX_CACHE_TTL_SECONDS", 3600, { min: 60, max: 86400 }),
    // TextBee SMS gateway (real OTP delivery). When apiKey+deviceId are set,
    // send-otp generates a real code and texts it; otherwise auth stays in the
    // dev "any code works" mock path.
    textbeeApiKey: stringFromEnv(env, "TEXTBEE_API_KEY", ""),
    textbeeDeviceId: stringFromEnv(env, "TEXTBEE_DEVICE_ID", ""),
    textbeeBaseUrl: stringFromEnv(env, "TEXTBEE_BASE_URL", "https://api.textbee.dev/api/v1"),
    otpTtlSeconds: integerFromEnv(env, "GRIDSHARE_OTP_TTL_SECONDS", 300, { min: 30, max: 1800 }),
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

  // Persist domain state (sessions, telemetry, commands, wallet, payouts) to
  // Postgres independently of the real chain/hardware/payment adapters. Real
  // adapters always persist. Otherwise GRIDSHARE_PERSIST controls it, defaulting
  // on whenever DATABASE_URL is explicitly configured. This lets "everything
  // stores" work with mock chain/hardware, so persistence isn't hostage to a
  // Tuya device or Soroban contract being live. Tests call createApp() with no
  // env, so DATABASE_URL is unset and this stays off (in-memory).
  config.persist = config.useRealAdapters
    ? true
    : booleanFromEnv(env, "GRIDSHARE_PERSIST", Boolean(env.DATABASE_URL));

  // Real SMS OTP via TextBee is enabled only when both the API key and device
  // id are present. Otherwise the auth flow falls back to dev mode (OTP is
  // logged/returned instead of texted), so local runs keep working with no
  // TextBee account.
  config.smsEnabled = Boolean(config.textbeeApiKey && config.textbeeDeviceId);

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

  // USDC top-up can be enabled independently of the real chain/hardware/payment
  // adapters (it uses its own Horizon client, not the Soroban relayer). When on,
  // it needs a funded testnet receiving account with a USDC trustline.
  if (config.usdcEnabled) {
    const requiredUsdc = [
      ["usdcReceivePublic", config.usdcReceivePublic],
      ["usdcReceiveSecret", config.usdcReceiveSecret],
      ["usdcIssuer", config.usdcIssuer]
    ];

    for (const [name, value] of requiredUsdc) {
      if (!value) {
        throw new DomainError("INVALID_CONFIG", `STELLAR_USDC_ENABLED is true but ${name} is not configured.`, { name });
      }
    }
  }

  return config;
}