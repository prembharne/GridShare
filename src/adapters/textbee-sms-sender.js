import { DomainError } from "../core/errors.js";

/**
 * Sends SMS via the TextBee gateway (https://textbee.dev), which relays through
 * a registered Android device. Used to deliver login OTPs.
 *
 * POST {baseUrl}/gateway/devices/{deviceId}/send-sms
 *   headers: { "x-api-key": <key>, "content-type": "application/json" }
 *   body:    { recipients: ["+91..."], message: "..." }
 */
export class TextBeeSmsSender {
  constructor({ apiKey, deviceId, baseUrl = "https://api.textbee.dev/api/v1" } = {}) {
    if (!apiKey) throw new DomainError("INVALID_CONFIG", "TextbeeSmsSender requires an API key.");
    if (!deviceId) throw new DomainError("INVALID_CONFIG", "TextbeeSmsSender requires a device id.");
    this.apiKey = apiKey;
    this.deviceId = deviceId;
    this.baseUrl = baseUrl.replace(/\/+$/, "");
  }

  /**
   * Send a plain-text SMS to a single recipient (E.164 phone).
   * Throws DomainError("SMS_SEND_FAILED", ...) on non-2xx or network error.
   */
  async sendSms(phoneInput, message) {
    const phoneE164 = normalizePhone(phoneInput);
    invariantPhone(phoneE164);
    const url = `${this.baseUrl}/gateway/devices/${this.deviceId}/send-sms`;

    let response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": this.apiKey
        },
        body: JSON.stringify({ recipients: [phoneE164], message: message })
      });
    } catch (error) {
      throw new DomainError("SMS_SEND_FAILED", "Could not reach the SMS gateway.", {
        cause: error.message
      });
    }

    if (!response.ok) {
      const detail = await response.text().catch(() => "");
      throw new DomainError("SMS_SEND_FAILED", "SMS gateway rejected the request.", {
        status: response.status,
        detail: detail.slice(0, 500)
      });
    }

    return { delivered: true };
  }
}

function normalizePhone(phone) {
  let cleaned = String(phone || "").trim().replaceAll(/[\s\-\(\)]/g, "");
  if (!cleaned) return cleaned;
  if (!cleaned.startsWith("+")) {
    if (cleaned.length === 10) {
      cleaned = "+91" + cleaned;
    } else {
      cleaned = "+" + cleaned;
    }
  }
  return cleaned;
}

function invariantPhone(phone) {
  if (!phone || !/^\+?[1-9]\d{6,14}$/.test(String(phone))) {
    throw new DomainError("INVALID_PHONE", "A valid E.164 phone number is required.", { phone });
  }
}

