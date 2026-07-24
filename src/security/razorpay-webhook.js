import crypto from "node:crypto";
import { DomainError } from "../core/errors.js";

function timingSafeEqualHex(left, right) {
  if (!left || !right) return false;

  const leftBuffer = Buffer.from(left, "hex");
  const rightBuffer = Buffer.from(right, "hex");

  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

export function signRazorpayWebhook(rawBody, secret) {
  return crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
}

export function verifyRazorpayWebhook({ rawBody, signature, secret }) {
  if (!secret) {
    return { verified: false, skipped: true };
  }

  if (!signature) {
    throw new DomainError("WEBHOOK_SIGNATURE_MISSING", "Razorpay webhook signature is required.");
  }

  const expected = signRazorpayWebhook(rawBody, secret);
  if (!timingSafeEqualHex(expected, signature)) {
    throw new DomainError("WEBHOOK_SIGNATURE_INVALID", "Razorpay webhook signature is invalid.");
  }

  return { verified: true, skipped: false };
}

export function verifyRazorpaySignature(orderId, paymentId, signature, secret) {
  if (!secret) return false;
  const expected = crypto.createHmac("sha256", secret).update(`${orderId}|${paymentId}`).digest("hex");
  return timingSafeEqualHex(expected, signature);
}
