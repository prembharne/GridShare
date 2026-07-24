import { DomainError } from "../core/errors.js";

function clone(value) {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

function createId() {
  return `topup_${crypto.randomUUID().replaceAll("-", "").slice(0, 18)}`;
}

function createPayoutId() {
  return `payout_${crypto.randomUUID().replaceAll("-", "").slice(0, 18)}`;
}

export class InMemoryStore {
  constructor() {
    this.sessions = new Map();
    this.telemetryBySession = new Map();
    this.walletBalances = new Map();     // userId -> balanceCredits
    this.walletTopups = new Map();       // id -> topup record
    this.hostPayouts = new Map();        // id -> payout record
    this.usdcIntents = new Map();        // memo -> usdc deposit intent
    this.sourceLedger = new Map();       // userId -> { upi, usdc } credit buckets
    this.kv = new Map();                 // misc key-value (e.g. Horizon cursor)
  }

  // --------------------------- Sessions ---------------------------

  async createSession(session) {
    if (this.sessions.has(session.id)) {
      throw new DomainError("SESSION_ALREADY_EXISTS", "Session already exists.", { sessionId: session.id });
    }

    this.sessions.set(session.id, clone(session));
    return this.getSession(session.id);
  }

  async getSession(sessionId) {
    return clone(this.sessions.get(sessionId));
  }

  async listSessions({ statuses } = {}) {
    const allowed = statuses ? new Set(statuses) : null;
    return Array.from(this.sessions.values())
      .filter((session) => !allowed || allowed.has(session.status))
      .map((session) => clone(session));
  }

  async requireSession(sessionId) {
    const session = this.getSession(sessionId);

    if (!session) {
      throw new DomainError("SESSION_NOT_FOUND", "Session was not found.", { sessionId });
    }

    return session;
  }

  async updateSession(sessionId, patch) {
    const existing = await this.requireSession(sessionId);
    const updated = {
      ...existing,
      ...patch,
      updatedAt: new Date().toISOString()
    };
    this.sessions.set(sessionId, clone(updated));
    return this.getSession(sessionId);
  }

  // --------------------------- Telemetry ---------------------------

  async appendTelemetry(sessionId, telemetry) {
    const list = this.telemetryBySession.get(sessionId) ?? [];
    const previous = list.at(-1);

    if (previous && telemetry.energyWh < previous.energyWh) {
      throw new DomainError(
        "TELEMETRY_ENERGY_DECREASED",
        "Telemetry energyWh must be cumulative and cannot decrease.",
        { sessionId, previousEnergyWh: previous.energyWh, energyWh: telemetry.energyWh }
      );
    }

    const record = {
      ...telemetry,
      receivedAt: new Date().toISOString()
    };
    list.push(record);
    this.telemetryBySession.set(sessionId, list);
    return clone(record);
  }

  async getTelemetry(sessionId) {
    return clone(this.telemetryBySession.get(sessionId) ?? []);
  }

  async getLatestTelemetry(sessionId) {
    const list = this.telemetryBySession.get(sessionId) ?? [];
    return clone(list.at(-1));
  }

  // --------------------------- Wallet ---------------------------

  async upsertWalletBalance(userId, deltaCredits) {
    const current = this.walletBalances.get(userId) ?? 0;
    const next = current + deltaCredits;
    if (next < 0) {
      throw new DomainError("INSUFFICIENT_BALANCE", "Wallet balance would go negative.", { userId });
    }
    this.walletBalances.set(userId, next);
    return { userId, balanceCredits: next };
  }

  async getWalletBalance(userId) {
    return { userId, balanceCredits: this.walletBalances.get(userId) ?? 0 };
  }

  // --------------------------- Top-ups ---------------------------

  async createWalletTopUp(input) {
    const id = input.id ?? createId();
    const record = {
      id,
      userId: input.userId,
      amountCredits: input.amountCredits,
      paymentId: input.paymentId,
      status: input.status ?? "pending",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    this.walletTopups.set(id, record);
    return clone(record);
  }

  async getWalletTopUp(id) {
    return clone(this.walletTopups.get(id));
  }

  async updateWalletTopUpStatus(id, status) {
    const record = this.walletTopups.get(id);
    if (!record) {
      throw new DomainError("TOPUP_NOT_FOUND", "Top-up record not found.", { id });
    }
    record.status = status;
    record.updatedAt = new Date().toISOString();
    this.walletTopups.set(id, record);
    return clone(record);
  }

  // --------------------------- Host Payouts (off-ramp) ---------------------------

  async createHostPayout(input) {
    const id = input.id ?? createPayoutId();
    const record = {
      id,
      hostId: input.hostId,
      credits: input.credits,
      inrAmount: input.inrAmount,           // equals credits (1:1)
      method: input.method,
      reference: input.reference ?? null,
      status: "pending",
      periodStart: input.periodStart ?? null,
      periodEnd: input.periodEnd ?? null,
      createdAt: new Date().toISOString(),
      paidAt: null
    };
    this.hostPayouts.set(id, record);
    return clone(record);
  }

  async getHostPayout(id) {
    return clone(this.hostPayouts.get(id));
  }

  async markPayoutPaid(id, { reference }) {
    const record = this.hostPayouts.get(id);
    if (!record) {
      throw new DomainError("PAYOUT_NOT_FOUND", "Payout record not found.", { id });
    }
    record.status = "paid";
    record.reference = reference;
    record.paidAt = new Date().toISOString();
    this.hostPayouts.set(id, record);
    return clone(record);
  }

  async markPayoutBurned(id) {
    const record = this.hostPayouts.get(id);
    if (!record) {
      throw new DomainError("PAYOUT_NOT_FOUND", "Payout record not found.", { id });
    }
    // already marked paid; this is a no-op for idempotency
    return clone(record);
  }

  // --------------------------- USDC deposit intents ---------------------------
  // A pending USDC top-up. `memo` is the correlation key the rider includes in
  // their Stellar payment; the Horizon watcher matches on it. Idempotency at
  // mint time is on the Stellar tx hash, not the memo.

  async createUsdcIntent(input) {
    if (this.usdcIntents.has(input.memo)) {
      throw new DomainError("USDC_INTENT_EXISTS", "A USDC intent with this memo already exists.", { memo: input.memo });
    }
    const record = {
      memo: input.memo,
      userId: input.userId,
      amountCredits: input.amountCredits,      // credits to mint on confirmation
      expectedUsdc: input.expectedUsdc,        // USDC the rider should send
      assetCode: input.assetCode ?? "USDC",   // USDC or XLM for the selected rail
      assetType: input.assetType ?? "credit_alphanum4",
      lockedRate: input.lockedRate,            // INR/USD rate locked at quote time
      status: input.status ?? "pending",       // pending | confirmed | expired
      txHash: null,
      paidAssetCode: input.paidAssetCode ?? null,
      expiresAt: input.expiresAt ?? null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    this.usdcIntents.set(record.memo, record);
    return clone(record);
  }

  async getUsdcIntentByMemo(memo) {
    return clone(this.usdcIntents.get(memo));
  }

  async updateUsdcIntent(memo, patch) {
    const record = this.usdcIntents.get(memo);
    if (!record) {
      throw new DomainError("USDC_INTENT_NOT_FOUND", "USDC intent not found.", { memo });
    }
    const updated = { ...record, ...patch, updatedAt: new Date().toISOString() };
    this.usdcIntents.set(memo, updated);
    return clone(updated);
  }

  // --------------------------- Source ledger (UPI vs USDC provenance) ---------------------------
  // On-chain credits are fungible, so the store tracks how each wallet's credits
  // were funded. Buckets always sum to the on-chain balance. Host earnings are
  // split across buckets in proportion to the rider's ratio at settlement time,
  // powering the host's separate UPI / USDC earnings sections.

  async getSourceLedger(userId) {
    const entry = this.sourceLedger.get(userId) ?? { upi: 0, usdc: 0 };
    return { userId, upi: entry.upi, usdc: entry.usdc };
  }

  async addSourceCredits(userId, source, amountCredits) {
    invariantSource(source);
    const entry = this.sourceLedger.get(userId) ?? { upi: 0, usdc: 0 };
    entry[source] += amountCredits;
    if (entry[source] < 0) entry[source] = 0; // defensive; splits guard against this
    this.sourceLedger.set(userId, entry);
    return { userId, upi: entry.upi, usdc: entry.usdc };
  }

  /**
   * Move credits between two wallets' source buckets in the SAME proportions,
   * used at settlement: deduct from rider by ratio, add the identical split to
   * the host. Returns the split actually applied.
   */
  async transferSourceCredits(fromUserId, toUserId, amountCredits) {
    const from = this.sourceLedger.get(fromUserId) ?? { upi: 0, usdc: 0 };
    const total = from.upi + from.usdc;

    let usdcPart;
    if (total <= 0) {
      usdcPart = 0; // no provenance recorded; attribute all to UPI by default
    } else {
      usdcPart = Math.round((amountCredits * from.usdc) / total);
    }
    usdcPart = Math.max(0, Math.min(usdcPart, amountCredits, from.usdc));
    let upiPart = amountCredits - usdcPart;
    if (upiPart > from.upi) {
      // rider lacks enough UPI-bucket credits (rounding edge); rebalance to USDC
      const shortfall = upiPart - from.upi;
      upiPart = from.upi;
      usdcPart = Math.min(from.usdc, usdcPart + shortfall);
    }

    from.upi -= upiPart;
    from.usdc -= usdcPart;
    this.sourceLedger.set(fromUserId, from);

    const to = this.sourceLedger.get(toUserId) ?? { upi: 0, usdc: 0 };
    to.upi += upiPart;
    to.usdc += usdcPart;
    this.sourceLedger.set(toUserId, to);

    return { upi: upiPart, usdc: usdcPart };
  }

  // --------------------------- KV (Horizon cursor, etc.) ---------------------------

  async getKv(key) {
    return this.kv.get(key) ?? null;
  }

  async setKv(key, value) {
    this.kv.set(key, value);
    return value;
  }
}

function invariantSource(source) {
  if (source !== "upi" && source !== "usdc") {
    throw new DomainError("INVALID_SOURCE", "Funding source must be 'upi' or 'usdc'.", { source });
  }
}