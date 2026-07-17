import { createApp } from "./app.js";

const app = createApp();

const intent = await app.saga.createIntent({
  riderId: "rider_demo",
  hostId: "host_demo",
  outletId: "outlet_demo",
  depositPaise: 5000,
  idempotencyKey: "demo-intent-001"
});

const sessionId = intent.session.id;

await app.saga.handlePaymentCaptured({
  sessionId,
  paymentId: "pay_demo_001",
  amountPaise: 5000,
  idempotencyKey: "pay_demo_001"
});

await app.saga.ingestTelemetry(sessionId, {
  energyWh: 500,
  currentAmp: 8,
  voltageV: 231,
  tempC: 39
});

const final = await app.saga.ingestTelemetry(sessionId, {
  energyWh: 1500,
  currentAmp: 18.2,
  voltageV: 231,
  tempC: 42
});

const summary = {
  sessionId,
  finalStatus: final.session.status,
  hardwareCommands: app.hardware.getCommands({ sessionId }).map((command) => ({
    id: command.id,
    desiredState: command.desiredState,
    reason: command.reason
  })),
  settlement: final.settlement,
  eventTypes: app.eventBus.list().map((event) => event.type),
  invoiceDescription: final.session.invoiceDescription
};

console.log(JSON.stringify(summary, null, 2));
