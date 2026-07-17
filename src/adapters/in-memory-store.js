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
}