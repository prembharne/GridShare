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
        depositPaise: session.depositPaise,
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

  mapSession(session) {
    return clone({
      id: session.id,
      riderId: session.riderId,
      hostId: session.hostId,
      outletId: session.outletId,
      status: session.status,
      depositPaise: session.depositPaise,
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

  async $disconnect() {
    await this.prisma.$disconnect();
  }
}