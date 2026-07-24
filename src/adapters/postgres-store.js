import { PrismaClient } from "@prisma/client";
import { DomainError } from "../core/errors.js";

function clone(value) {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

function toISO(date) {
  return date ? new Date(date).toISOString() : null;
}

export class PostgresStore {
  constructor({ prisma } = {}) {
    this.prisma = prisma ?? new PrismaClient();
    this.usdcIntents = new Map();
    this.sourceLedgerMap = new Map();
    this.kvMap = new Map();
    this.walletTopUpsMap = new Map();
    this.walletBalancesMap = new Map();
  }

  // ── Wallet ───────────────────────────────────────────────────────────────
  async createWalletTopUp(topUp) {
    this.walletTopUpsMap.set(topUp.id, clone(topUp));
    return clone(topUp);
  }

  async upsertWalletBalance(userId, amountCredits) {
    const current = this.walletBalancesMap.get(userId) ?? 0;
    const updated = current + amountCredits;
    this.walletBalancesMap.set(userId, updated);
    return updated;
  }

  async getWalletBalance(userId) {
    return this.walletBalancesMap.get(userId) ?? 0;
  }



  async createSession(session) {
    const existing = await this.prisma.session.findUnique({ where: { id: session.id } });
    if (existing) {
      throw new DomainError("SESSION_ALREADY_EXISTS", "Session already exists.", { sessionId: session.id });
    }

    await this.prisma.session.create({
      data: {
        id: session.id,
        riderId: session.riderId,
        hostId: session.hostId,
        outletId: session.outletId,
        status: session.status,
        depositCredits: session.depositCredits,
        paymentId: session.paymentId ?? null,
        paidAt: session.paidAt ? new Date(session.paidAt) : null,
        escrowLockTxHash: session.escrowLockTxHash ?? null,
        hardwareOnCommandId: session.hardwareOnCommandId ?? null,
        hardwareOffCommandId: session.hardwareOffCommandId ?? null,
        activeAt: session.activeAt ? new Date(session.activeAt) : null,
        stoppedAt: session.stoppedAt ? new Date(session.stoppedAt) : null,
        stopReason: session.stopReason ?? null,
        stopKind: session.stopKind ?? null,
        pendingSettlement: session.pendingSettlement ?? null,
        pendingOracleReport: session.pendingOracleReport ?? null,
        settlement: session.settlement ?? null,
        settlementTxHash: session.settlementTxHash ?? null,
        refundTxHash: session.refundTxHash ?? null,
        invoiceDescription: session.invoiceDescription ?? null,
        failureCode: session.failureCode ?? null,
        createdAt: session.createdAt ? new Date(session.createdAt) : new Date(),
        updatedAt: session.updatedAt ? new Date(session.updatedAt) : new Date(),
      }
    });

    return this.getSession(session.id);
  }

  async getSession(sessionId) {
    const session = await this.prisma.session.findUnique({ where: { id: sessionId } });
    return session ? this.mapSession(session) : undefined;
  }

  async requireSession(sessionId) {
    const session = await this.getSession(sessionId);
    if (!session) {
      throw new DomainError("SESSION_NOT_FOUND", "Session was not found.", { sessionId });
    }
    return session;
  }

  async updateSession(sessionId, patch) {
    const existing = await this.requireSession(sessionId);

    const data = {};
    if (patch.status !== undefined) data.status = patch.status;
    if (patch.paymentId !== undefined) data.paymentId = patch.paymentId;
    if (patch.paidAt !== undefined) data.paidAt = patch.paidAt ? new Date(patch.paidAt) : null;
    if (patch.escrowLockTxHash !== undefined) data.escrowLockTxHash = patch.escrowLockTxHash;
    if (patch.hardwareOnCommandId !== undefined) data.hardwareOnCommandId = patch.hardwareOnCommandId;
    if (patch.hardwareOffCommandId !== undefined) data.hardwareOffCommandId = patch.hardwareOffCommandId;
    if (patch.activeAt !== undefined) data.activeAt = patch.activeAt ? new Date(patch.activeAt) : null;
    if (patch.stoppedAt !== undefined) data.stoppedAt = patch.stoppedAt ? new Date(patch.stoppedAt) : null;
    if (patch.stopReason !== undefined) data.stopReason = patch.stopReason;
    if (patch.stopKind !== undefined) data.stopKind = patch.stopKind;
    if (patch.pendingSettlement !== undefined) data.pendingSettlement = patch.pendingSettlement;
    if (patch.pendingOracleReport !== undefined) data.pendingOracleReport = patch.pendingOracleReport;
    if (patch.settlement !== undefined) data.settlement = patch.settlement;
    if (patch.settlementTxHash !== undefined) data.settlementTxHash = patch.settlementTxHash;
    if (patch.refundTxHash !== undefined) data.refundTxHash = patch.refundTxHash;
    if (patch.invoiceDescription !== undefined) data.invoiceDescription = patch.invoiceDescription;
    if (patch.failureCode !== undefined) data.failureCode = patch.failureCode;
    data.updatedAt = new Date();

    await this.prisma.session.update({
      where: { id: sessionId },
      data
    });

    return this.getSession(sessionId);
  }

  async listSessions({ statuses } = {}) {
    const where = statuses ? { status: { in: statuses } } : {};
    const sessions = await this.prisma.session.findMany({ where, orderBy: { createdAt: "desc" } });
    return sessions.map(this.mapSession);
  }

  async appendTelemetry(sessionId, telemetry) {
    const previous = await this.prisma.telemetrySample.findFirst({
      where: { sessionId },
      orderBy: { sampledAt: "desc" },
      select: { energyWh: true }
    });

    if (previous && telemetry.energyWh < Number(previous.energyWh)) {
      throw new DomainError(
        "TELEMETRY_ENERGY_DECREASED",
        "Telemetry energyWh must be cumulative and cannot decrease.",
        { sessionId, previousEnergyWh: Number(previous.energyWh), energyWh: telemetry.energyWh }
      );
    }

    const record = await this.prisma.telemetrySample.create({
      data: {
        sessionId,
        outletId: telemetry.outletId ?? (await this.requireSession(sessionId)).outletId,
        sampledAt: telemetry.sampledAt ? new Date(telemetry.sampledAt) : new Date(),
        energyWh: telemetry.energyWh,
        currentAmp: telemetry.currentAmp,
        voltageV: telemetry.voltageV,
        tempC: telemetry.tempC,
        rawProviderPayload: telemetry.rawProviderPayload ?? null,
      }
    });

    return this.mapTelemetry(record);
  }

  async getTelemetry(sessionId) {
    const records = await this.prisma.telemetrySample.findMany({
      where: { sessionId },
      orderBy: { sampledAt: "asc" }
    });
    return records.map(this.mapTelemetry);
  }

  async getLatestTelemetry(sessionId) {
    const record = await this.prisma.telemetrySample.findFirst({
      where: { sessionId },
      orderBy: { sampledAt: "desc" }
    });
    return record ? this.mapTelemetry(record) : null;
  }

  async createHardwareCommand(command) {
    const created = await this.prisma.hardwareCommand.create({
      data: {
        id: command.id,
        sessionId: command.sessionId ?? null,
        outletId: command.outletId,
        desiredState: command.desiredState,
        reason: command.reason,
        providerCommandId: command.providerCommandId ?? null,
        status: command.status ?? "issued",
        issuedAt: command.issuedAt ? new Date(command.issuedAt) : new Date(),
        acknowledgedAt: command.acknowledgedAt ? new Date(command.acknowledgedAt) : null,
        failureCode: command.failureCode ?? null,
        rawProviderResponse: command.rawProviderResponse ?? null,
      }
    });
    return this.mapHardwareCommand(created);
  }

  async getHardwareCommands({ outletId, sessionId } = {}) {
    const where = {};
    if (outletId) where.outletId = outletId;
    if (sessionId) where.sessionId = sessionId;

    const commands = await this.prisma.hardwareCommand.findMany({
      where,
      orderBy: { issuedAt: "desc" }
    });
    return commands.map(this.mapHardwareCommand);
  }

  async updateHardwareCommand(commandId, patch) {
    const data = {};
    if (patch.status !== undefined) data.status = patch.status;
    if (patch.providerCommandId !== undefined) data.providerCommandId = patch.providerCommandId;
    if (patch.acknowledgedAt !== undefined) data.acknowledgedAt = patch.acknowledgedAt ? new Date(patch.acknowledgedAt) : null;
    if (patch.failureCode !== undefined) data.failureCode = patch.failureCode;
    if (patch.rawProviderResponse !== undefined) data.rawProviderResponse = patch.rawProviderResponse;

    const updated = await this.prisma.hardwareCommand.update({
      where: { id: commandId },
      data
    });
    return this.mapHardwareCommand(updated);
  }

  async createIdempotencyKey(scope, key, payloadHash, responseJson) {
    await this.prisma.idempotencyKey.upsert({
      where: { scope_key: { scope, key } },
      update: { payloadHash, responseJson },
      create: { scope, key, payloadHash, responseJson }
    });
  }

  async getIdempotencyKey(scope, key) {
    return this.prisma.idempotencyKey.findUnique({ where: { scope_key: { scope, key } } });
  }

  async createOutboxEvent(eventType, sessionId, payload) {
    await this.prisma.outboxEvent.create({
      data: { eventType, sessionId, payload }
    });
  }

  async getPendingOutboxEvents(limit = 100) {
    return this.prisma.outboxEvent.findMany({
      where: { status: "pending", nextAttemptAt: { lte: new Date() } },
      orderBy: { nextAttemptAt: "asc" },
      take: limit
    });
  }

  async markOutboxEventSent(id) {
    await this.prisma.outboxEvent.update({
      where: { id },
      data: { status: "sent", sentAt: new Date() }
    });
  }

  async markOutboxEventFailed(id, attempts) {
    await this.prisma.outboxEvent.update({
      where: { id },
      data: {
        status: "failed",
        attempts,
        nextAttemptAt: new Date(Date.now() + Math.min(attempts * 1000, 60000))
      }
    });
  }

  async createReconciliationRun(details = {}) {
    return this.prisma.reconciliationRun.create({
      data: { details }
    });
  }

  async finishReconciliationRun(id, { scanned, recovered, failed }) {
    await this.prisma.reconciliationRun.update({
      where: { id },
      data: { finishedAt: new Date(), scanned, recovered, failed }
    });
  }

  async createLedgerEvent(eventType, sessionId, payload) {
    await this.prisma.ledgerEvent.create({
      data: { eventType, sessionId, payload }
    });
  }

  // --------------------------- Wallet ---------------------------

  async upsertWalletBalance(userId, deltaCredits) {
    const existing = await this.prisma.walletBalance.findUnique({ where: { userId } });
    if (!existing) {
      if (deltaCredits < 0) {
        throw new DomainError("INSUFFICIENT_BALANCE", "Wallet balance would go negative.", { userId });
      }
      const record = await this.prisma.walletBalance.create({
        data: { userId, balanceCredits: deltaCredits }
      });
      return { userId, balanceCredits: record.balanceCredits };
    }
    const next = existing.balanceCredits + deltaCredits;
    if (next < 0) {
      throw new DomainError("INSUFFICIENT_BALANCE", "Wallet balance would go negative.", { userId });
    }
    const updated = await this.prisma.walletBalance.update({
      where: { userId },
      data: { balanceCredits: { increment: deltaCredits } }
    });
    return { userId, balanceCredits: updated.balanceCredits };
  }

  async getWalletBalance(userId) {
    const record = await this.prisma.walletBalance.findUnique({ where: { userId } });
    return { userId, balanceCredits: record?.balanceCredits ?? 0 };
  }

  // --------------------------- Top-ups ---------------------------

  async createWalletTopUp(input) {
    const id = input.id ?? input.paymentId;
    const record = await this.prisma.walletTopUp.create({
      data: {
        id,
        userId: input.userId,
        amountCredits: input.amountCredits,
        paymentId: input.paymentId,
        status: input.status ?? "pending",
        createdAt: input.createdAt ? new Date(input.createdAt) : new Date()
      }
    });
    return this.mapTopUp(record);
  }

  async getWalletTopUp(id) {
    const record = await this.prisma.walletTopUp.findUnique({ where: { id } });
    return record ? this.mapTopUp(record) : undefined;
  }

  async updateWalletTopUpStatus(id, status) {
    const existing = await this.prisma.walletTopUp.findUnique({ where: { id } });
    if (!existing) {
      throw new DomainError("TOPUP_NOT_FOUND", "Top-up record not found.", { id });
    }
    const record = await this.prisma.walletTopUp.update({
      where: { id },
      data: { status }
    });
    return this.mapTopUp(record);
  }

  // --------------------------- Host Payouts (off-ramp) ---------------------------

  async createHostPayout(input) {
    const record = await this.prisma.hostPayout.create({
      data: {
        id: input.id,
        hostId: input.hostId,
        credits: input.credits,
        inrAmount: input.inrAmount,
        method: input.method,
        reference: input.reference ?? null,
        status: "pending",
        periodStart: input.periodStart ? new Date(input.periodStart) : null,
        periodEnd: input.periodEnd ? new Date(input.periodEnd) : null
      }
    });
    return this.mapPayout(record);
  }

  async getHostPayout(id) {
    const record = await this.prisma.hostPayout.findUnique({ where: { id } });
    return record ? this.mapPayout(record) : undefined;
  }

  async markPayoutPaid(id, { reference }) {
    const existing = await this.prisma.hostPayout.findUnique({ where: { id } });
    if (!existing) {
      throw new DomainError("PAYOUT_NOT_FOUND", "Payout record not found.", { id });
    }
    const record = await this.prisma.hostPayout.update({
      where: { id },
      data: { status: "paid", reference, paidAt: new Date() }
    });
    return this.mapPayout(record);
  }

  async markPayoutBurned(id) {
    const existing = await this.prisma.hostPayout.findUnique({ where: { id } });
    if (!existing) {
      throw new DomainError("PAYOUT_NOT_FOUND", "Payout record not found.", { id });
    }
    // The payout row is created/marked paid elsewhere; burning is a bookkeeping
    // no-op here for idempotency, matching InMemoryStore.
    return this.mapPayout(existing);
  }

  // --------------------------- Outlets ---------------------------

  // Upsert an outlet (its host user must already exist). Used to seed the demo
  // catalog so session inserts satisfy the outlet foreign key. Uses raw SQL
  // because `location` is a PostGIS geography column, which Prisma's typed API
  // can't write (it's an Unsupported type in the schema).
  async upsertOutlet(outlet) {
    const lng = Number(outlet.lng);
    const lat = Number(outlet.lat);
    await this.prisma.$executeRaw`
      INSERT INTO outlets (id, host_id, display_name, device_provider, provider_device_id, location, address, max_current_amp, status, created_at, updated_at)
      VALUES (
        ${outlet.id},
        ${outlet.hostId},
        ${outlet.displayName},
        ${outlet.deviceProvider ?? "tuya"},
        ${outlet.providerDeviceId},
        ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography,
        ${outlet.address ?? null},
        ${outlet.maxCurrentAmp ?? 16},
        ${outlet.status ?? "available"}::"OutletStatus",
        now(),
        now()
      )
      ON CONFLICT (id) DO UPDATE SET
        host_id = EXCLUDED.host_id,
        display_name = EXCLUDED.display_name,
        device_provider = EXCLUDED.device_provider,
        provider_device_id = EXCLUDED.provider_device_id,
        location = EXCLUDED.location,
        address = EXCLUDED.address,
        max_current_amp = EXCLUDED.max_current_amp,
        status = EXCLUDED.status,
        updated_at = now()
    `;
    return { id: outlet.id };
  }

  mapTopUp(record) {
    return clone({
      id: record.id,
      userId: record.userId,
      amountCredits: record.amountCredits,
      paymentId: record.paymentId,
      status: record.status,
      createdAt: toISO(record.createdAt),
      updatedAt: toISO(record.updatedAt)
    });
  }

  mapPayout(record) {
    return clone({
      id: record.id,
      hostId: record.hostId,
      credits: record.credits,
      inrAmount: record.inrAmount,
      method: record.method,
      reference: record.reference,
      status: record.status,
      periodStart: toISO(record.periodStart),
      periodEnd: toISO(record.periodEnd),
      createdAt: toISO(record.createdAt),
      paidAt: toISO(record.paidAt)
    });
  }

  mapSession(session) {
    return clone({
      id: session.id,
      riderId: session.riderId,
      hostId: session.hostId,
      outletId: session.outletId,
      status: session.status,
      depositCredits: session.depositCredits,
      paymentId: session.paymentId,
      paidAt: toISO(session.paidAt),
      escrowLockTxHash: session.escrowLockTxHash,
      hardwareOnCommandId: session.hardwareOnCommandId,
      hardwareOffCommandId: session.hardwareOffCommandId,
      activeAt: toISO(session.activeAt),
      stoppedAt: toISO(session.stoppedAt),
      stopReason: session.stopReason,
      stopKind: session.stopKind,
      pendingSettlement: session.pendingSettlement,
      pendingOracleReport: session.pendingOracleReport,
      settlement: session.settlement,
      settlementTxHash: session.settlementTxHash,
      refundTxHash: session.refundTxHash,
      invoiceDescription: session.invoiceDescription,
      failureCode: session.failureCode,
      createdAt: toISO(session.createdAt),
      updatedAt: toISO(session.updatedAt)
    });
  }

  mapTelemetry(record) {
    return clone({
      sessionId: record.sessionId,
      outletId: record.outletId,
      sampledAt: toISO(record.sampledAt),
      receivedAt: toISO(record.receivedAt),
      energyWh: Number(record.energyWh),
      currentAmp: Number(record.currentAmp),
      voltageV: Number(record.voltageV),
      tempC: Number(record.tempC),
      rawProviderPayload: record.rawProviderPayload
    });
  }

  mapHardwareCommand(cmd) {
    return clone({
      id: cmd.id,
      sessionId: cmd.sessionId,
      outletId: cmd.outletId,
      desiredState: cmd.desiredState,
      reason: cmd.reason,
      providerCommandId: cmd.providerCommandId,
      status: cmd.status,
      issuedAt: toISO(cmd.issuedAt),
      acknowledgedAt: toISO(cmd.acknowledgedAt),
      failureCode: cmd.failureCode,
      rawProviderResponse: cmd.rawProviderResponse
    });
  }

  // ── USDC Intents ────────────────────────────────────────────────────────
  async createUsdcIntent(input) {
    if (this.usdcIntents.has(input.memo)) {
      throw new DomainError("USDC_INTENT_EXISTS", "A USDC intent with this memo already exists.", { memo: input.memo });
    }
    const record = {
      memo: input.memo,
      userId: input.userId,
      amountCredits: input.amountCredits,
      expectedUsdc: input.expectedUsdc,
      assetCode: input.assetCode ?? "USDC",
      assetType: input.assetType ?? "credit_alphanum4",
      lockedRate: input.lockedRate,
      status: input.status ?? "pending",
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

  // ── Source Ledger ────────────────────────────────────────────────────────
  async getSourceLedger(userId) {
    const entry = this.sourceLedgerMap.get(userId) ?? { upi: 0, usdc: 0 };
    return clone(entry);
  }

  async addSourceCredits(userId, source, amount) {
    const entry = this.sourceLedgerMap.get(userId) ?? { upi: 0, usdc: 0 };
    if (source === "usdc") entry.usdc += amount;
    else entry.upi += amount;
    this.sourceLedgerMap.set(userId, entry);
    return clone(entry);
  }

  async transferSourceCredits(fromUserId, toUserId, amountCredits) {
    const from = this.sourceLedgerMap.get(fromUserId) ?? { upi: 0, usdc: 0 };
    const total = from.upi + from.usdc;
    let upiShare = 0;
    let usdcShare = 0;

    if (total > 0 && amountCredits > 0) {
      upiShare = Math.min(from.upi, Math.round((from.upi / total) * amountCredits));
      usdcShare = amountCredits - upiShare;
      if (usdcShare > from.usdc) {
        usdcShare = from.usdc;
        upiShare = Math.min(from.upi, amountCredits - usdcShare);
      }
    }
    from.upi = Math.max(0, from.upi - upiShare);
    from.usdc = Math.max(0, from.usdc - usdcShare);
    this.sourceLedgerMap.set(fromUserId, from);

    const to = this.sourceLedgerMap.get(toUserId) ?? { upi: 0, usdc: 0 };
    to.upi += upiShare;
    to.usdc += usdcShare;
    this.sourceLedgerMap.set(toUserId, to);

    return { transferredUpi: upiShare, transferredUsdc: usdcShare };
  }

  // ── Key-Value Store ──────────────────────────────────────────────────────
  async getKv(key) {
    return this.kvMap.get(key) ?? null;
  }

  async setKv(key, value) {
    this.kvMap.set(key, value);
  }

  async $disconnect() {
    await this.prisma.$disconnect();
  }
}
