import axios from "axios";
import { DomainError } from "../core/errors.js";

export class RealHardwareBridge {
  constructor({ clientId, clientSecret, endpoint, deviceId, webhookSecret, eventBus, resolveDeviceId } = {}) {
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.endpoint = endpoint || "https://openapi.tuyacn.com";
    this.deviceId = deviceId;
    this.webhookSecret = webhookSecret;
    this.eventBus = eventBus;
    // Optional per-outlet routing: maps an outletId to its Tuya device id.
    // Falls back to the single configured deviceId when unset/unresolved so
    // single-plug deployments keep working unchanged.
    this.resolveDeviceId = resolveDeviceId;
    this.accessToken = null;
    this.tokenExpiry = 0;
    this.deviceStates = new Map();
    this.commands = [];
  }

  /**
   * Resolve the Tuya device id for an outlet. Prefers the injected resolver
   * (per-outlet routing), then the outlet-scoped fallback, then the globally
   * configured deviceId. Throws when nothing can be resolved.
   */
  resolveDevice(outletId) {
    let deviceId;
    if (typeof this.resolveDeviceId === "function" && outletId != null) {
      try {
        deviceId = this.resolveDeviceId(outletId);
      } catch {
        deviceId = undefined;
      }
    }
    deviceId = deviceId || this.deviceId;
    if (!deviceId) {
      throw new DomainError("HARDWARE_DEVICE_UNRESOLVED", "No Tuya device id could be resolved for outlet.", {
        outletId
      });
    }
    return deviceId;
  }


  async getAccessToken() {
    const now = Date.now();
    if (this.accessToken && now < this.tokenExpiry - 60000) {
      return this.accessToken;
    }

    const response = await axios.post(`${this.endpoint}/v1.0/token`, null, {
      params: { grant_type: 1 },
      auth: { username: this.clientId, password: this.clientSecret }
    });

    this.accessToken = response.data.result.access_token;
    this.tokenExpiry = now + response.data.result.expire_time * 1000;
    return this.accessToken;
  }

  async setSwitch({ outletId, desiredState, reason, sessionId }) {
    const token = await this.getAccessToken();
    const deviceId = this.resolveDevice(outletId);
    const commands = [{
      code: "switch_1",
      value: desiredState
    }];

    const response = await axios.post(
      `${this.endpoint}/v1.0/devices/${deviceId}/commands`,
      { commands },
      { headers: { Authorization: `Bearer ${token}` } }
    );


    if (!response.data.success) {
      throw new DomainError("HARDWARE_COMMAND_FAILED", "Tuya command failed.", {
        outletId,
        sessionId,
        response: response.data
      });
    }

    const command = {
      id: `cmd_${this.commands.length + 1}`,
      outletId,
      sessionId,
      desiredState,
      reason,
      providerCommandId: response.data.result?.sn ?? `tuya_${Date.now()}`,
      issuedAt: new Date().toISOString(),
      acknowledgedAt: new Date().toISOString()
    };

    this.deviceStates.set(outletId, desiredState);
    this.commands.push(command);
    this.eventBus?.publish("hardware.switch_changed", command);
    return this.clone(command);
  }

  async getDeviceStatus(outletId) {
    const token = await this.getAccessToken();
    const deviceId = this.resolveDevice(outletId);
    const response = await axios.get(
      `${this.endpoint}/v1.0/devices/${deviceId}/status`,
      { headers: { Authorization: `Bearer ${token}` } }
    );

    if (!response.data.success) {
      throw new DomainError("HARDWARE_STATUS_FAILED", "Failed to get device status.", {
        outletId,
        response: response.data
      });
    }

    const status = {};
    for (const item of response.data.result) {
      status[item.code] = item.value;
    }
    return status;
  }

  /**
   * Live, UI-friendly snapshot for a single outlet. Normalizes the raw Tuya
   * status codes (cur_power in deciwatts, cur_current in mA, cur_voltage in
   * decivolts, add_ele in Wh) into a stable shape consumed by /outlets/:id/live
   * and the host dashboard. Falls back to the last-known switch state on error.
   */
  async getLiveStatus(outletId) {
    const status = await this.getDeviceStatus(outletId);
    const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);
    return {
      outletId,
      online: true,
      switchOn: Boolean(status.switch_1 ?? status.switch ?? false),
      powerW: num(status.cur_power) / 10,
      currentA: num(status.cur_current) / 1000,
      voltageV: num(status.cur_voltage) / 10,
      energyWh: num(status.add_ele),
      tempC: num(status.temp_current) / 10,
      sampledAt: new Date().toISOString(),
      raw: status
    };
  }


  getSwitchState(outletId) {
    return this.deviceStates.get(outletId) ?? false;
  }

  getCommands({ outletId, sessionId } = {}) {
    return this.clone(
      this.commands.filter((command) => {
        if (outletId && command.outletId !== outletId) return false;
        if (sessionId && command.sessionId !== sessionId) return false;
        return true;
      })
    );
  }

  async handleTelemetryWebhook(payload, signature) {
    if (this.webhookSecret) {
      const expected = this.computeSignature(payload);
      if (signature !== expected) {
        throw new DomainError("WEBHOOK_SIGNATURE_INVALID", "Invalid Tuya webhook signature.");
      }
    }

    const telemetry = this.parseTelemetry(payload);
    this.eventBus?.publish("telemetry.received", { telemetry, raw: payload });
    return telemetry;
  }

  parseTelemetry(payload) {
    const status = payload?.data?.status ?? [];
    const getVal = (code) => {
      const item = status.find((s) => s.code === code);
      return item ? Number(item.value) : 0;
    };

    return {
      energyWh: getVal("add_ele"),
      currentAmp: getVal("cur_current") / 10,
      voltageV: getVal("cur_voltage") / 10,
      tempC: getVal("temp_current") / 10,
      sampledAt: new Date().toISOString(),
      rawProviderPayload: payload
    };
  }

  computeSignature(payload) {
    const crypto = require("node:crypto");
    return crypto.createHmac("sha256", this.webhookSecret)
      .update(JSON.stringify(payload))
      .digest("hex");
  }

  clone(value) {
    return value === undefined ? value : JSON.parse(JSON.stringify(value));
  }
}