import crypto from "node:crypto";
import { invariant } from "../core/errors.js";
import { computeSettlement } from "./settlement-math.js";
import {
  computeTimeSettlement,
  activeSecondsBetween
} from "./time-settlement-math.js";
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
      paymentId: input.paymentId,
      // Funding rail: "upi" (Razorpay, default) or "usdc" (Stellar deposit).
      // Both rails mint the SAME credit token; source is tracked off-chain
      // only for the host's separate UPI / USDC earnings reporting.
      source: input.source === "usdc" ? "usdc" : "upi"
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
        source: payload.source,
        status: "confirmed",
        createdAt: now(),
        updatedAt: now()
      });

      // Update local balance mirror
      await this.store.upsertWalletBalance(payload.userId, payload.amountCredits);

      // Track funding provenance (buckets sum to the on-chain balance).
      if (this.store.addSourceCredits) {
        await this.store.addSourceCredits(payload.userId, payload.source, payload.amountCredits);
      }

      this.eventBus.publish("wallet.topup", {
        userId: payload.userId,
        amountCredits: payload.amountCredits,
        paymentId: payload.paymentId,
        source: payload.source
      });

      return { userId: payload.userId, amountCredits: payload.amountCredits, source: payload.source };
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
      depositCredits: input.depositCredits,
      // Per-minute billing (optional). When ratePerMinuteCredits is provided the
      // session bills by elapsed active minutes; otherwise it falls back to the
      // legacy energy-based model. selectedDurationMinutes lets the rider cap the
      // charge to a chosen duration (auto-stops at that point).
      ratePerMinuteCredits: input.ratePerMinuteCredits,
      selectedDurationMinutes: input.selectedDurationMinutes
    };

    return this.idempotencyStore.run("session.intent", input.idempotencyKey, payload, async () => {
      invariant(payload.riderId, "INVALID_RIDER", "riderId is required.");
      invariant(payload.hostId, "INVALID_HOST", "hostId is required.");
      invariant(payload.outletId, "INVALID_OUTLET", "outletId is required.");
      invariant(Number.isInteger(payload.depositCredits) && payload.depositCredits > 0, "INVALID_DEPOSIT", "depositCredits must be a positive integer.");

      const billByTime =
        payload.ratePerMinuteCredits !== undefined &&
        payload.ratePerMinuteCredits !== null;
      if (billByTime) {
        invariant(
          Number.isInteger(payload.ratePerMinuteCredits) && payload.ratePerMinuteCredits >= 0,
          "INVALID_RATE",
          "ratePerMinuteCredits must be a non-negative integer."
        );
      }
      if (payload.selectedDurationMinutes !== undefined && payload.selectedDurationMinutes !== null) {
        invariant(
          Number.isInteger(payload.selectedDurationMinutes) && payload.selectedDurationMinutes > 0,
          "INVALID_DURATION",
          "selectedDurationMinutes must be a positive integer."
        );
      }

      const session = await this.store.createSession({
        id: input.sessionId ?? createSessionId(),
        riderId: payload.riderId,
        hostId: payload.hostId,
        outletId: payload.outletId,
        depositCredits: payload.depositCredits,
        billingMode: billByTime ? "per_minute" : "energy",
        ratePerMinuteCredits: billByTime ? payload.ratePerMinuteCredits : null,
        selectedDurationMinutes: payload.selectedDurationMinutes ?? null,
        status: "created",
        createdAt: now(),
        updatedAt: now()
      });

      this.eventBus.publish("session.intent_created", {
        sessionId: session.id,
        riderId: session.riderId,
        hostId: session.hostId,
        outletId: session.outletId,
        depositCredits: session.depositCredits,
        billingMode: session.billingMode,
        ratePerMinuteCredits: session.ratePerMinuteCredits,
        selectedDurationMinutes: session.selectedDurationMinutes
      });

      return { session };
    });
  }


  /**
   * Start a session: check rider balance, lock credits, turn hardware ON.
   * Replaces the old handlePaymentCaptured -> activatePaidSession flow.
   */
  async startSession(input) {
    // Public entry: acquire the per-session lock, then run the shared body.
    return this.withSessionLock(input.sessionId, () => this._startSessionLocked(input));
  }

  /**
   * Start-session body. Assumes the caller ALREADY holds the session lock.
   * Split out so reconcileSession (which already locks) can reuse it without
   * re-entering withSessionLock — the non-reentrant LockManager would otherwise
   * deadlock (reconcile holds session:<id>, startSession waits on the same key).
   */
  async _startSessionLocked(input) {
    const key = input.idempotencyKey ?? `start_${input.sessionId}`;
    const payload = { sessionId: input.sessionId };

    return this.idempotencyStore.run("session.start", key, payload, async () => {
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
    });
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

      // Per-minute sessions bill by elapsed time, not energy: the SessionMeter
      // (tickSession) owns auto-stop. Here we only record telemetry for live
      // dashboards and return a time-based preview.
      if (session.billingMode === "per_minute") {
        const preview = this._computeSettlementFor(session, { stoppedAt: now() });
        return {
          session: await this.store.requireSession(sessionId),
          telemetry,
          settlementPreview: preview
        };
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
        // Already inside the session lock — call the locked body directly to
        // avoid re-entering withSessionLock (non-reentrant → would deadlock).
        const result = await this._startSessionLocked({ sessionId, idempotencyKey: `reconcile_${sessionId}` });
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

    const recovered = results.filter((result) => result.ok && !result.result.skipped).length;
    const failed = results.filter((result) => !result.ok).length;

    this.eventBus.publish("reconciliation.completed", {
      scanned: sessions.length,
      recovered,
      failed
    });

    return { scanned: sessions.length, recovered, failed, results };
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

  /**
   * Choose the settlement model for a session. Per-minute sessions (created with
   * ratePerMinuteCredits) bill by elapsed active seconds; everything else keeps
   * the legacy energy-based settlement so existing flows are unchanged.
   */
  _computeSettlementFor(session, { energyWh = 0, stoppedAt = now() } = {}) {
    if (session.billingMode === "per_minute" && session.ratePerMinuteCredits != null) {
      const activeSeconds = activeSecondsBetween(session.activeAt, stoppedAt);
      return computeTimeSettlement({
        depositCredits: session.depositCredits,
        activeSeconds,
        ratePerMinuteCredits: session.ratePerMinuteCredits,
        serviceFeeBps: this.config.serviceFeeBps
      });
    }
    return computeSettlement({
      depositCredits: session.depositCredits,
      energyWh,
      pricePerKwhCredits: this.config.pricePerKwhCredits,
      serviceFeeBps: this.config.serviceFeeBps
    });
  }

  /**
   * Per-minute meter tick. Pure clock math (no hardware dependency): for an
   * active per-minute session it computes the live charge and auto-stops when
   * either the rider's selected duration elapses or the accrued charge reaches
   * the locked deposit. Non-per-minute or non-active sessions are a no-op.
   * Safe to call repeatedly (e.g. from the SessionMeter scheduler).
   */
  async tickSession(sessionId) {
    return this.withSessionLock(sessionId, async () => {
      const session = await this.store.requireSession(sessionId);
      if (session.status !== "active" || session.billingMode !== "per_minute") {
        return { session, skipped: true };
      }

      const activeSeconds = activeSecondsBetween(session.activeAt, now());

      const durationElapsed =
        session.selectedDurationMinutes != null &&
        activeSeconds >= session.selectedDurationMinutes * 60;

      // When the rider's selected duration has elapsed, bill EXACTLY that
      // duration rather than the (rounded-up) overshoot: the tick may fire a
      // few seconds late, and partial minutes round up, so using the raw
      // elapsed time would over-charge by a whole minute. Clamp the settlement
      // clock to the selected-duration boundary.
      const settleAt = durationElapsed
        ? new Date(new Date(session.activeAt).getTime() + session.selectedDurationMinutes * 60000).toISOString()
        : now();
      const preview = this._computeSettlementFor(session, { stoppedAt: settleAt });

      const depositReached = preview.amountDueCredits >= session.depositCredits;

      if (durationElapsed || depositReached) {
        const reason = durationElapsed ? "duration_elapsed" : "prepaid_threshold_reached";

        this.eventBus.publish("session.auto_stop", {
          sessionId,
          reason,
          activeSeconds,
          amountDueCredits: preview.amountDueCredits,
          depositCredits: session.depositCredits
        });
        return this.stopAndSettle({
          session,
          reason,
          stopKind: durationElapsed ? "auto_timer" : "auto_threshold",
          // Bill to the clamped boundary, not the (late) wall-clock tick time.
          stoppedAt: settleAt
        });

      }

      this.eventBus.publish("session.meter_tick", {
        sessionId,
        activeSeconds,
        billedMinutes: preview.billedMinutes,
        amountDueCredits: preview.amountDueCredits,
        remainingCredits: session.depositCredits - preview.amountDueCredits
      });

      return { session, meter: preview, activeSeconds };
    });
  }

  async stopAndSettle({ session, reason, stopKind, hardwareAlreadyOff = false, telemetry, stoppedAt }) {

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

    // Per-minute auto-stops pass a clamped stoppedAt (the selected-duration
    // boundary) so the settlement bills exactly the chosen duration. All other
    // stops settle as of now().
    const settlement = this._computeSettlementFor(session, {
      energyWh: latestTelemetry.energyWh,
      stoppedAt: stoppedAt ?? now()
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

    // Attribute the host's earned credits to funding sources (UPI vs USDC) in
    // proportion to the rider's current bucket ratio. On-chain credits are
    // fungible; this off-chain split powers the host's separate earnings
    // sections without changing the settlement ledger. Best-effort: a failure
    // here must not undo a completed on-chain settlement.
    const hostShareCredits = session.pendingSettlement?.hostShareCredits ?? 0;
    if (this.store.transferSourceCredits && hostShareCredits > 0 && session.riderId && session.hostId) {
      try {
        const split = await this.store.transferSourceCredits(session.riderId, session.hostId, hostShareCredits);
        this.eventBus.publish("wallet.earnings_attributed", {
          sessionId: session.id,
          hostId: session.hostId,
          riderId: session.riderId,
          hostShareCredits,
          split
        });
      } catch (error) {
        this.eventBus.publish("wallet.earnings_attribution_failed", {
          sessionId: session.id,
          hostId: session.hostId,
          reason: error.code ?? error.message
        });
      }
    }

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