import crypto from "node:crypto";
import { DomainError, invariant } from "../core/errors.js";

function delay(ms) {
  if (ms <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function demoId() {
  return `demo_${crypto.randomUUID().replaceAll("-", "").slice(0, 12)}`;
}

export class JudgeDemoService {
  constructor({ saga, eventBus, config }) {
    this.saga = saga;
    this.eventBus = eventBus;
    this.config = config;
  }

  async run(input = {}) {
    if (!this.config.demoMode) {
      throw new DomainError("DEMO_MODE_DISABLED", "Demo endpoints are disabled in this environment.");
    }

    const id = input.demoId ?? demoId();
    const stepDelayMs = Number(input.stepDelayMs ?? this.config.demoStepDelayMs);
    invariant(Number.isInteger(stepDelayMs) && stepDelayMs >= 0 && stepDelayMs <= 10000, "INVALID_DEMO_STEP_DELAY", "stepDelayMs must be between 0 and 10000.");

    const riderId = input.riderId ?? "rider_demo";
    const hostId = input.hostId ?? "host_demo";
    const outletId = input.outletId ?? `outlet_${id}`;
    const depositCredits = input.depositCredits ?? 500;

    const safeTelemetry = input.safeTelemetry ?? [
      { energyWh: 500, currentAmp: 8, voltageV: 231, tempC: 39 },
      { energyWh: 1100, currentAmp: 9.2, voltageV: 230, tempC: 42 }
    ];
    const safetyTelemetry = input.safetyTelemetry ?? {
      energyWh: 1500,
      currentAmp: 18.2,
      voltageV: 231,
      tempC: 42
    };

    this.eventBus.publish("demo.started", {
      demoId: id,
      riderId,
      hostId,
      outletId,
      depositCredits
    });

    // 1. Top up rider's wallet
    const topup = await this.saga.topUpWallet({
      userId: riderId,
      amountCredits: depositCredits,
      paymentId: `pay_${id}`,
      idempotencyKey: `${id}:topup`
    });
    this.eventBus.publish("demo.topup_complete", { demoId: id, ...topup });

    // 2. Create session intent (no payment step needed - wallet already funded)
    const intent = await this.saga.createIntent({
      riderId,
      hostId,
      outletId,
      depositCredits,
      idempotencyKey: `${id}:intent`
    });
    const sessionId = intent.session.id;
    this.eventBus.publish("demo.intent_created", { demoId: id, sessionId });

    await delay(stepDelayMs);

    // 3. Start session (checks wallet balance, locks credits, turns hardware ON)
    const start = await this.saga.startSession({
      sessionId,
      idempotencyKey: `${id}:start`
    });
    this.eventBus.publish("demo.start_to_active", {
      demoId: id,
      sessionId,
      status: start.session.status
    });

    // 4. Simulate safe charging telemetry
    let latest;
    for (const telemetry of safeTelemetry) {
      await delay(stepDelayMs);
      latest = await this.saga.ingestTelemetry(sessionId, telemetry);
      this.eventBus.publish("demo.telemetry_tick", {
        demoId: id,
        sessionId,
        telemetry: latest.telemetry,
        settlementPreview: latest.settlementPreview
      });
    }

    // 5. Trigger safety trip
    await delay(stepDelayMs);
    const final = await this.saga.ingestTelemetry(sessionId, safetyTelemetry);
    this.eventBus.publish("demo.safety_trip_complete", {
      demoId: id,
      sessionId,
      status: final.session.status,
      settlement: final.settlement
    });

    // 6. Show host earnings (for manual off-ramp payout)
    const hostEarnings = await this.saga.getHostEarnings(hostId);
    this.eventBus.publish("demo.host_earnings", { demoId: id, hostId, ...hostEarnings });

    const preCompletionAudit = await this.saga.getSessionAudit(sessionId);
    const summary = {
      demoId: id,
      sessionId,
      finalStatus: final.session.status,
      settlement: final.settlement,
      invoiceDescription: final.session.invoiceDescription,
      hostEarnedCredits: hostEarnings.earnedCredits,
      hardwareCommands: preCompletionAudit.hardwareCommands.map((command) => ({
        id: command.id,
        desiredState: command.desiredState,
        reason: command.reason
      })),
      eventTypes: preCompletionAudit.events.map((event) => event.type)
    };

    this.eventBus.publish("demo.completed", summary);
    const audit = await this.saga.getSessionAudit(sessionId);
    summary.eventTypes = audit.events.map((event) => event.type);

    return {
      summary,
      audit
    };
  }
}