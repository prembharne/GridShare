import crypto from "node:crypto";
import { DomainError } from "../core/errors.js";

/**
 * Real phone-OTP service. Generates a numeric code, stores it in memory with a
 * TTL + attempt cap, and verifies it. SMS delivery is delegated to an injected
 * `sendSms(phone, message)` function (TextBee in production). When no sender is
 * configured, the code is logged to the console (dev fallback) so local sign-in
 * still works without burning SMS credits.
 *
 * State is in-memory (per-process). Fine for a single backend instance / demo;
 * a multi-instance deployment would move this to Redis/Postgres.
 */
export class OtpService {
  constructor({
    smsSender = null,
    ttlSeconds = 300,
    codeLength = 6,
    maxAttempts = 5,
    exposeCodeInResponse = false,
    eventBus = null,
    logger = console
  } = {}) {
    this.smsSender = smsSender;
    this.ttlMs = ttlSeconds * 1000;
    this.codeLength = codeLength;
    this.maxAttempts = maxAttempts;
    this.exposeCodeInResponse = exposeCodeInResponse;
    this.eventBus = eventBus;
    this.logger = logger;
    this.byPhone = new Map(); // phoneE164 -> { code, expiresAt, attempts }
  }

  _generateCode() {
    // Cryptographically-random numeric code, zero-padded to codeLength.
    const max = 10 ** this.codeLength;
    const n = crypto.randomInt(0, max);
    return String(n).padStart(this.codeLength, "0");
  }

  /**
   * Create + send an OTP for a phone number. Overwrites any prior pending code
   * for that number (a fresh request invalidates the old code).
   */
  async requestOtp(phone) {
    if (!phone || typeof phone !== "string") {
      throw new DomainError("INVALID_PHONE", "A phone number is required to send an OTP.");
    }

    const code = this._generateCode();
    const expiresAt = Date.now() + this.ttlMs;
    this.byPhone.set(phone, { code, expiresAt, attempts: 0 });

    const message = `Hey! The code you requested is ${code}. It is valid for ${Math.round(this.ttlMs / 60000)} mins.`;

    if (this.smsSender) {
      this.logger.log(`[OTP SMS] Sending code ${code} to ${phone} via TextBee...`);
      try {
        await this.smsSender.sendSms(phone, message);
        this.logger.log(`[OTP SMS] TextBee accepted SMS for ${phone} ✓`);
      } catch (err) {
        this.logger.error(`[OTP SMS Error] Failed to send SMS to ${phone}:`, err.message, err.details || "");
        throw err;
      }
    } else {
      // Dev fallback: no SMS provider configured, surface the code in logs.
      this.logger.log(`[OTP dev] ${phone} -> ${code} (no SMS provider configured)`);
    }

    this.eventBus?.publish("auth.otp_requested", { phone, viaSms: Boolean(this.smsSender) });

    const result = {
      sent: true,
      viaSms: Boolean(this.smsSender),
      expiresInSeconds: Math.round(this.ttlMs / 1000)
    };
    // Dev-only: return the code so local sign-in works without a real phone.
    if (this.exposeCodeInResponse) result.devCode = code;
    return result;
  }

  /**
   * Verify a submitted code. Throws DomainError on any failure (no code,
   * expired, too many attempts, mismatch). Consumes the code on success.
   */
  verifyOtp(phone, submittedCode) {
    const entry = this.byPhone.get(phone);
    if (!entry) {
      throw new DomainError("OTP_NOT_FOUND", "No verification code was requested for this number, or it has expired.");
    }

    if (Date.now() > entry.expiresAt) {
      this.byPhone.delete(phone);
      throw new DomainError("OTP_EXPIRED", "This verification code has expired. Please request a new one.");
    }

    if (entry.attempts >= this.maxAttempts) {
      this.byPhone.delete(phone);
      throw new DomainError("OTP_TOO_MANY_ATTEMPTS", "Too many incorrect attempts. Please request a new code.");
    }

    const submitted = String(submittedCode ?? "").trim();
    // Constant-time compare to avoid leaking match progress via timing.
    const expected = entry.code;
    const ok =
      submitted.length === expected.length &&
      crypto.timingSafeEqual(Buffer.from(submitted), Buffer.from(expected));

    if (!ok) {
      entry.attempts += 1;
      throw new DomainError("OTP_INVALID", "Incorrect verification code.");
    }

    this.byPhone.delete(phone);
    return true;
  }
}
