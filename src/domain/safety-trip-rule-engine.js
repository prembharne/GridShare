export class SafetyTripRuleEngine {
  constructor({ hardware, eventBus, thresholds }) {
    this.hardware = hardware;
    this.eventBus = eventBus;
    this.thresholds = thresholds;
  }

  async evaluate({ session, telemetry }) {
    const reason = this.getTripReason(telemetry);

    if (!reason) {
      return { tripped: false };
    }

    const command = await this.hardware.setSwitch({
      outletId: session.outletId,
      desiredState: false,
      reason: `safety_trip:${reason}`,
      sessionId: session.id
    });

    this.eventBus.publish("safety.trip", {
      sessionId: session.id,
      outletId: session.outletId,
      reason,
      telemetry,
      commandId: command.id
    });

    return {
      tripped: true,
      reason,
      command
    };
  }

  getTripReason(telemetry) {
    if (telemetry.currentAmp > this.thresholds.maxCurrentAmp) {
      return "current_spike";
    }

    if (telemetry.tempC > this.thresholds.maxTempC) {
      return "temperature_spike";
    }

    if (telemetry.voltageV < this.thresholds.minVoltageV) {
      return "voltage_drop";
    }

    if (telemetry.voltageV > this.thresholds.maxVoltageV) {
      return "voltage_spike";
    }

    return null;
  }
}
