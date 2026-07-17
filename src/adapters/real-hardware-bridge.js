import axios from "axios";
import { DomainError } from "../core/errors.js";

export class RealHardwareBridge {
  constructor({ clientId, clientSecret, endpoint, deviceId, webhookSecret, eventBus } = {}) {
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.endpoint = endpoint || "https://openapi.tuyacn.com";
    this.deviceId = deviceId;
    this.webhookSecret = webhookSecret;
    this.eventBus = eventBus;
    this.accessToken = null;
    this.tokenExpiry = 0;
    this.deviceStates = new Map();
    this.commands = [];
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
    const commands = [{
      code: "switch_1",
      value: desiredState
    }];

    const response = await axios.post(
      `${this.endpoint}/v1.0/devices/${this.deviceId}/commands`,
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

  async getDeviceStatus() {
    const token = await this.getAccessToken();
    const response = await axios.get(
      `${this.endpoint}/v1.0/devices/${this.deviceId}/status`,
      { headers: { Authorization: `Bearer ${token}` } }
    );

    if (!response.data.success) {
      throw new DomainError("HARDWARE_STATUS_FAILED", "Failed to get device status.", {
        response: response.data
      });
    }

    const status = {};
    for (const item of response.data.result) {
      status[item.code] = item.value;
    }
    return status;
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