import { DomainError } from "../core/errors.js";

function clone(value) {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

export class MockHardwareBridge {
  constructor({ eventBus }) {
    this.eventBus = eventBus;
    this.deviceStates = new Map();
    this.commands = [];
    this.failNextOnCount = 0;
    this.failNextOffCount = 0;
  }

  simulateNextOnFailure(count = 1) {
    this.failNextOnCount = count;
  }

  simulateNextOffFailure(count = 1) {
    this.failNextOffCount = count;
  }

  async setSwitch({ outletId, desiredState, reason, sessionId }) {
    if (desiredState === true && this.failNextOnCount > 0) {
      this.failNextOnCount -= 1;
      throw new DomainError("HARDWARE_COMMAND_FAILED", "Mock hardware failed to turn on.", {
        outletId,
        sessionId
      });
    }

    if (desiredState === false && this.failNextOffCount > 0) {
      this.failNextOffCount -= 1;
      throw new DomainError("HARDWARE_COMMAND_FAILED", "Mock hardware failed to turn off.", {
        outletId,
        sessionId
      });
    }

    const command = {
      id: `cmd_${this.commands.length + 1}`,
      outletId,
      sessionId,
      desiredState,
      reason,
      issuedAt: new Date().toISOString(),
      acknowledgedAt: new Date().toISOString()
    };

    this.deviceStates.set(outletId, desiredState);
    this.commands.push(command);
    this.eventBus.publish("hardware.switch_changed", command);
    return clone(command);
  }

  getSwitchState(outletId) {
    return this.deviceStates.get(outletId) ?? false;
  }

  /**
   * Synthetic live snapshot for dev/mock mode so /outlets/:id/live and the host
   * dashboard render without a real device. Mirrors the RealHardwareBridge
   * shape: powers a plausible ~3.3 kW draw when the switch is on, zero when off.
   */
  async getLiveStatus(outletId) {
    const switchOn = this.getSwitchState(outletId);
    return {
      outletId,
      online: true,
      switchOn,
      powerW: switchOn ? 3300 : 0,
      currentA: switchOn ? 14.3 : 0,
      voltageV: switchOn ? 230 : 0,
      energyWh: 0,
      tempC: 32,
      sampledAt: new Date().toISOString(),
      mock: true
    };
  }


  getCommands({ outletId, sessionId } = {}) {
    return clone(
      this.commands.filter((command) => {
        if (outletId && command.outletId !== outletId) return false;
        if (sessionId && command.sessionId !== sessionId) return false;
        return true;
      })
    );
  }
}
