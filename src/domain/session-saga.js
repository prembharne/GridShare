import crypto from "node:crypto";
import { invariant } from "../core/errors.js";
import { computeSettlement } from "./settlement-math.js";
import { INVOICE_DESCRIPTION, assertComplianceCopy } from "./compliance.js";

function now() {
  return new Date().toISOString();
}

function createSessionId() {
  return `sess_${crypto.randomUUID().replaceAll("-", "").slice(0, 18)}`;
}

function normalizeTelemetry(input) {
  const telemetry = {
    energyWh: Number(input.energyWh),
    currentAmp: Number(input.currentAmp),
    voltageV: Number(input.voltageV),
    tempC: Number(input.tempC),
    sampledAt: input.sampledAt ?? now()
  };

  invariant(Number.isFinite(telemetry.energyWh) && telemetry.energyWh >= 0, "INVALID_TELEMETRY", "energyWh must be a finite non-negative number.");
  invariant(Number.isFinite(telemetry.currentAmp) && telemetry.currentAmp >= 0, "INVALID_TELEMETRY", "currentAmp must be a finite non-negative number.");
  invariant(Number.isFinite(telemetry.voltageV) && telemetry.voltageV > 0, "INVALID_TELEMETRY", "voltageV must be a finite positive number.");
  invariant(Number.isFinite(telemetry.tempC), "INVALID_TELEMETRY", "tempC must be a finite number.");

  return telemetry;
}

export class SessionSaga {
  constructor({
    store,
    chain,
    hardware,
    eventBus,
    idempotencyStore,
    lockManager,
    safetyEngine,
    config
  }) {
    this.store = store;
    this.chain = chain;
    this.hardware = hardware;
    this.eventBus = eventBus;
    this.idempotencyStore = idempotencyStore;
    this.lockManager = lockManager;
    this.safetyEngine = safetyEngine;
    this.config = config;
  }

  async withSessionLock(sessionId, handler) {
    invariant(sessionId, "INVALID_SESSION", "sessionId is required.");
    if (!this.lockManager) {
      return handler();
    }
    return this.lockManager.runExclusive(`session:${sessionId}`, handler);
  }

  // ============================ WALLET ============================

  /**
   * Mint credits into a user's wallet (called on UPI top-up webhook).
   * Idempotent on paymentId.
   */
  async topUpWallet(input) {
    const payload = {
      userId: input.userId,
      amountCredits: input.amountCredits,
      paymentId: input.paymentId
    };

    const key = input.idempotencyKey ?? input.paymentId;

    return this.idempotencyStore.run("wallet.topup", key, payload, async () => {
      invariant(payload.userId, "INVALID_USER", "userId is required.");
      invariant(Number.isInteger(payload.amountCredits) && payload.amountCredits > 0, "INVALID_AMOUNT", "amountCredits must be a positive integer.");
      invariant(payload.paymentId, "INVALID_PAYMENT", "paymentId is required.");

      // Mint credits on-chain
      await this.chain.mint({ userId: payload.userId, amountCredits: payload.amountCredits });

      // Record top-up in store
      await this.store.createWalletTopUp({
        id: payload.paymentId,
        userId: payload.userId,
        amountCredits: payload.amountCredits,
        paymentId: payload.paymentId,
        status: "confirmed",
        createdAt: now(),
        updatedAt: now()
      });

      // Update local balance mirror
      await this.store.upsertWalletBalance(payload.userId, payload.amountCredits);

      this.eventBus.publish("wallet.topup", {
        userId: payload.userId,
        amountCredits: payload.amountCredits,
        paymentId: payload.paymentId
      });

      return { userId: payload.userId, amountCredits: payload.amountCredits };
    });
  }

  /**
   * Get a user's current wallet balance (from chain, mirrored in store).
   */
  async getWalletBalance(userId) {
    invariant(userId, "INVALID_USER", "userId is required.");
    const onChain = await this.chain.balanceOf(userId);
    return { userId, balanceCredits: onChain };
  }

  /**
   * Get a host's earned credits (for off-ramp payout).
   */
  async getHostEarnings(hostId) {
    invariant(hostId, "INVALID_HOST", "hostId is required.");
    const onChain = await this.chain.balanceOf(hostId);
    return { hostId, earnedCredits: onChain };
  }

  /**
   * Burn host's earned credits after off-chain payout (redeem/off-ramp).
   * Idempotent on payoutId.
   */
  async redeemHostCredits(input) {
    const payload = {
      hostId: input.hostId,
      amountCredits: input.amountCredits,
      payoutId: input.payoutId,
      reference: input.reference
    };

    return this.idempotencyStore.run("wallet.redeem", input.payoutId, payload, async () => {
      invariant(payload.hostId, "INVALID_HOST", "hostId is required.");
      invariant(Number.isInteger(payload.amountCredits) && payload.amountCredits > 0, "INVALID_AMOUNT", "amountCredits must be a positive integer.");
      invariant(payload.payoutId, "INVALID_PAYOUT", "payoutId is required.");
      invariant(payload.reference, "MISSING_REFERENCE", "Off-chain payout reference (UTR/txn id) is required.");

      // Burn credits on-chain
      await this.chain.redeem({ hostId: payload.hostId, amountCredits: payload.amountCredits });

      // Mark payout as burned in store
      await this.store.markPayoutBurned(payload.payoutId);

      this.eventBus.publish("wallet.redeem", {
        hostId: payload.hostId,
        amountCredits: payload.amountCredits,
        payoutId: payload.payoutId,
        reference: payload.reference
      });

      return { hostId: payload.hostId, amountCredits: payload.amountCredits, burned: true };
    });
  }

  // ============================ SESSION LIFECYCLE ============================

  /**
   * Register session intent. No payment step needed - user must have wallet balance.
   * Status: "created"
   */
  async createIntent(input) {
    const payload = {
      riderId: input.riderId,
      hostId: input.hostId,
      outletId: input.outletId,
      depositCredits: input.depositCredits
    };

    return this.idempotencyStore.run("session.intent", input.idempotencyKey, payload, async () => {
      invariant(payload.riderId, "INVALID_RIDER", "riderId is required.");
      invariant(payload.hostId, "INVALID_HOST", "hostId is required.");
      invariant(payload.outletId, "INVALID_OUTLET", "outletId is required.");
      invariant(Number.isInteger(payload.depositCredits) && payload.depositCredits > 0, "INVALID_DEPOSIT", "depositCredits must be a positive integer.");

      const session = await this.store.createSession({
        id: input.sessionId ?? createSessionId(),
        riderId: payload.riderId,
        hostId: payload.hostId,
        outletId: payload.outletId,
        depositCredits: payload.depositCredits,
        status: "created",
        createdAt: now(),
        updatedAt: now()
      });

      this.eventBus.publish("session.intent_created", {
        sessionId: session.id,
        riderId: session.riderId,
        hostId: session.hostId,
        outletId: session.outletId,
        depositCredits: session.depositCredits
      });

      return { session };
    });
  }

  /**
   * Start a session: check rider balance, lock credits, turn hardware ON.
   * Replaces the old handlePaymentCaptured -> activatePaidSession flow.
   */
  async startSession(input) {
    const key = input.idempotencyKey ?? `start_${input.sessionId}`;
    const payload = { sessionId: input.sessionId };

    return this.withSessionLock(payload.sessionId, () =>
      this.idempotencyStore.run("session.start", key, payload, async () => {
        const session = await this.store.requireSession(payload.sessionId);

        invariant(["created", "lock_failed"].includes(session.status), "SESSION_NOT_STARTABLE", "Only created or lock_failed sessions can be started.", {
          sessionId: session.id,
          status: session.status
        });

        // Pre-check: rider must have enough credits in wallet
        const wallet = await this.chain.balanceOf(session.riderId);
        if (wallet < session.depositCredits) {
          await this.store.updateSession(session.id, {
            status: "lock_failed",
            failureCode: "INSUFFICIENT_BALANCE"
          });
          this.eventBus.publish("session.reconciliation_needed", {
            sessionId: session.id,
            status: "lock_failed",
            failureCode: "INSUFFICIENT_BALANCE"
          });
          throw new Error("INSUFFICIENT_BALANCE");
        }

        // Lock credits from rider's wallet
        let lockResult;
        try {
          lockResult = await this.chain.lockDeposit({
            sessionId: session.id,
            riderId: session.riderId,
            hostId: session.hostId,
            depositCredits: session.depositCredits
          });
        } catch (error) {
          await this.store.updateSession(session.id, {
            status: "lock_failed",
            failureCode: error.code ?? "CHAIN_LOCK_FAILED"
          });
          this.eventBus.publish("session.reconciliation_needed", {
            sessionId: session.id,
            status: "lock_failed",
            failureCode: error.code ?? "CHAIN_LOCK_FAILED"
          });
          throw error;
        }

        // Turn hardware ON
        try {
          const hardwareCommand = await this.hardware.setSwitch({
            outletId: session.outletId,
            desiredState: true,
            reason: "session_started",
            sessionId: session.id
          });

          const activated = await this.store.updateSession(session.id, {
            status: "active",
            escrowLockTxHash: lockResult.txHash,
            hardwareOnCommandId: hardwareCommand.id,
            activeAt: now(),
            failureCode: null
          });

          this.eventBus.publish("session.activated", {
            sessionId: session.id,
            escrowLockTxHash: lockResult.txHash,
            hardwareOnCommandId: hardwareCommand.id
          });

          return { session: activated, chain: lockResult, hardware: hardwareCommand };
        } catch (error) {
          // On hardware failure, refund the locked credits to rider
          const refund = await this.chain.refundDeposit({
            sessionId: session.id,
            reason: "hardware_activation_failed"
          });

          const failed = await this.store.updateSession(session.id, {
            status: "refunded_after_activation_failure",
            escrowLockTxHash: lockResult.txHash,
            refundTxHash: refund.txHash,
            failureCode: error.code ?? "HARDWARE_COMMAND_FAILED"
          });

          this.eventBus.publish("session.activation_failed_refunded", {
            sessionId: session.id,
            refundTxHash: refund.txHash,
            failureCode: failed.failureCode
          });

          return { session: failed, chain: lockResult, refund };
        }
      })
    );
  }

  async ingestTelemetry(sessionId, input) {
    return this.withSessionLock(sessionId, async () => {
      const session = await this.store.requireSession(sessionId);

      invariant(
        ["active"].includes(session.status),
        "SESSION_NOT_TELEMETRY_READY",
        "Telemetry is accepted only for active sessions.",
        { sessionId, status: session.status }
      );

      const telemetry = await this.store.appendTelemetry(sessionId, normalizeTelemetry(input));
      this.eventBus.publish("telemetry.received", { sessionId, telemetry });

      const safety = await this.safetyEngine.evaluate({ session, telemetry });
      if (safety.tripped) {
        return this.stopAndSettle({
          session,
          reason: safety.reason,
          stopKind: "safety_trip",
          hardwareAlreadyOff: true,
          telemetry
        });
      }

      const preview = computeSettlement({
        depositCredits: session.depositCredits,
        energyWh: telemetry.energyWh,
        pricePerKwhCredits: this.config.pricePerKwhCredits,
        serviceFeeBps: this.config.serviceFeeBps
      });

      if (preview.amountDueCredits >= session.depositCredits) {
        this.eventBus.publish("session.auto_stop_threshold", {
          sessionId,
          amountDueCredits: preview.amountDueCredits,
          depositCredits: session.depositCredits
        });

        return this.stopAndSettle({
          session,
          reason: "prepaid_threshold_reached",
          stopKind: "auto_threshold",
          telemetry
        });
      }

      return {
        session: await this.store.requireSession(sessionId),
        telemetry,
        settlementPreview: preview
      };
    });
  }

  async stopSession(input) {
    const key = input.idempotencyKey;
    const payload = {
      sessionId: input.sessionId,
      reason: input.reason ?? "user_stop"
    };

    return this.withSessionLock(payload.sessionId, () =>
      this.idempotencyStore.run("session.stop", key, payload, async () => {
        const session = await this.store.requireSession(payload.sessionId);

        if (session.status === "settled") {
          return { session };
        }

        if (session.status === "stopping") {
          return this.completePendingSettlement(session);
        }

        invariant(session.status === "active", "SESSION_NOT_STOPPABLE", "Only active sessions can be stopped.", {
          sessionId: session.id,
          status: session.status
        });

        return this.stopAndSettle({
          session,
          reason: payload.reason,
          stopKind: "manual"
        });
      })
    );
  }

  async reconcileSession(sessionId) {
    return this.withSessionLock(sessionId, async () => {
      const session = await this.store.requireSession(sessionId);

      if (["created", "lock_failed"].includes(session.status)) {
        const result = await this.startSession({ sessionId, idempotencyKey: `reconcile_${sessionId}` });
        this.eventBus.publish("session.reconciled", {
          sessionId,
          fromStatus: session.status,
          toStatus: result.session.status
        });
        return result;
      }

      if (session.status === "stopping") {
        const result = await this.completePendingSettlement(session);
        this.eventBus.publish("session.reconciled", {
          sessionId,
          fromStatus: session.status,
          toStatus: result.session.status
        });
        return result;
      }

      return {
        session,
        skipped: true,
        reason: "session_not_in_recoverable_state"
      };
    });
  }

  async reconcileAll() {
    const sessions = await this.store.listSessions({ statuses: ["created", "lock_failed", "stopping"] });
    const results = [];

    for (const session of sessions) {
      try {
        results.push({ sessionId: session.id, ok: true, result: await this.reconcileSession(session.id) });
      } catch (error) {
        results.push({
          sessionId: session.id,
          ok: false,
          error: {
            code: error.code ?? "RECONCILIATION_FAILED",
            message: error.message
          }
        });
      }
    }

    this.eventBus.publish("reconciliation.completed", {
      scanned: sessions.length,
      recovered: results.filter((result) => result.ok && !result.result.skipped).length,
      failed: results.filter((result) => !result.ok).length
    });

    return { scanned: sessions.length, results };
  }

  async getSession(sessionId) {
    const session = await this.store.requireSession(sessionId);
    const [telemetry, contract] = await Promise.all([
      this.store.getTelemetry(sessionId),
      Promise.resolve(this.chain.getContractSession(sessionId))
    ]);
    return {
      session,
      telemetry,
      contract
    };
  }

  async getSessionAudit(sessionId) {
    const snapshot = await this.getSession(sessionId);
    const events = this.eventBus.list().filter((event) => event.payload?.sessionId === sessionId);

    return {
      ...snapshot,
      hardwareCommands: this.hardware.getCommands({ sessionId }),
      events
    };
  }

  async stopAndSettle({ session, reason, stopKind, hardwareAlreadyOff = false, telemetry }) {
    const latestTelemetry = telemetry ?? (await this.store.getLatestTelemetry(session.id)) ?? {
      energyWh: 0,
      currentAmp: 0,
      voltageV: 0,
      tempC: 0,
      sampledAt: now()
    };

    let hardwareCommand = null;
    if (!hardwareAlreadyOff) {
      hardwareCommand = await this.hardware.setSwitch({
        outletId: session.outletId,
        desiredState: false,
        reason,
        sessionId: session.id
      });
    }

    const settlement = computeSettlement({
      depositCredits: session.depositCredits,
      energyWh: latestTelemetry.energyWh,
      pricePerKwhCredits: this.config.pricePerKwhCredits,
      serviceFeeBps: this.config.serviceFeeBps
    });

    assertComplianceCopy(INVOICE_DESCRIPTION);

    const oracleReport = {
      source: "gridshare-difficult-core",
      finalTelemetry: latestTelemetry,
      reason
    };

    const stopping = await this.store.updateSession(session.id, {
      status: "stopping",
      stoppedAt: now(),
      stopReason: reason,
      stopKind,
      hardwareOffCommandId: hardwareCommand?.id ?? session.hardwareOffCommandId,
      pendingSettlement: settlement,
      pendingOracleReport: oracleReport,
      failureCode: null
    });

    return this.completePendingSettlement(stopping, { hardwareCommand });
  }

  async completePendingSettlement(session, { hardwareCommand = null } = {}) {
    invariant(session.pendingSettlement, "SETTLEMENT_NOT_PENDING", "Session has no pending settlement to complete.", {
      sessionId: session.id,
      status: session.status
    });

    let chainSettlement;
    try {
      chainSettlement = await this.chain.settleSession({
        sessionId: session.id,
        settlement: session.pendingSettlement,
        oracleReport: session.pendingOracleReport
      });
    } catch (error) {
      await this.store.updateSession(session.id, {
        status: "stopping",
        failureCode: error.code ?? "CHAIN_SETTLE_FAILED"
      });
      this.eventBus.publish("session.reconciliation_needed", {
        sessionId: session.id,
        status: "stopping",
        failureCode: error.code ?? "CHAIN_SETTLE_FAILED"
      });
      throw error;
    }

    const settled = await this.store.updateSession(session.id, {
      status: "settled",
      settlement: session.pendingSettlement,
      settlementTxHash: chainSettlement.txHash,
      invoiceDescription: INVOICE_DESCRIPTION,
      settledAt: now(),
      pendingSettlement: null,
      pendingOracleReport: null,
      failureCode: null
    });

    this.eventBus.publish("session.settled", {
      sessionId: session.id,
      reason: session.stopReason,
      stopKind: session.stopKind,
      settlement: session.pendingSettlement,
      settlementTxHash: chainSettlement.txHash
    });

    return {
      session: settled,
      telemetry: session.pendingOracleReport?.finalTelemetry,
      settlement: session.pendingSettlement,
      chain: chainSettlement,
      hardware: hardwareCommand
    };
  }
}