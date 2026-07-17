import Razorpay from "razorpay";
import { DomainError } from "../core/errors.js";

export class RealPaymentAdapter {
  constructor({ keyId, keySecret, webhookSecret, eventBus } = {}) {
    this.razorpay = new Razorpay({ key_id: keyId, key_secret: keySecret });
    this.webhookSecret = webhookSecret;
    this.eventBus = eventBus;
  }

  async createOrder({ amountPaise, currency = "INR", receipt, notes = {} }) {
    const order = await this.razorpay.orders.create({
      amount: amountPaise,
      currency,
      receipt,
      notes
    });
    return {
      id: order.id,
      amount: order.amount,
      currency: order.currency,
      status: order.status,
      createdAt: order.created_at
    };
  }

  async verifyWebhookSignature(rawBody, signature) {
    const crypto = require("node:crypto");
    const expected = crypto.createHmac("sha256", this.webhookSecret)
      .update(rawBody)
      .digest("hex");

    if (signature !== expected) {
      throw new DomainError("WEBHOOK_SIGNATURE_INVALID", "Invalid Razorpay webhook signature.");
    }
  }

  async handlePaymentCapturedWebhook(payload) {
    const payment = payload.payment?.entity;
    if (!payment || payment.status !== "captured") {
      return { captured: false };
    }

    const result = {
      sessionId: payment.notes?.session_id,
      paymentId: payment.id,
      amountPaise: payment.amount,
      capturedAt: new Date(payment.created_at * 1000).toISOString()
    };

    this.eventBus?.publish("payment.captured", result);
    return { captured: true, ...result };
  }

  /**
   * Handle wallet top-up webhook.
   * Expects payment.notes.user_id to identify the wallet owner.
   * 1 INR paid = 1 credit minted.
   */
  async handleTopUpWebhook(payload) {
    const payment = payload.payment?.entity;
    if (!payment || payment.status !== "captured") {
      return { captured: false };
    }

    const userId = payment.notes?.user_id;
    if (!userId) {
      throw new DomainError("MISSING_USER_ID", "Top-up webhook requires user_id in payment notes.");
    }

    const amountCredits = payment.amount; // 1 INR = 1 credit (Razorpay amount is in paise, but we treat whole INR)
    // Note: Razorpay sends amount in paise. If user pays ₹500, amount=50000 paise.
    // We need to convert: credits = amount / 100 (since 1 credit = 1 INR)
    const credits = Math.floor(payment.amount / 100);

    const result = {
      userId,
      paymentId: payment.id,
      amountCredits: credits,
      capturedAt: new Date(payment.created_at * 1000).toISOString()
    };

    this.eventBus?.publish("wallet.topup", result);
    return { captured: true, ...result };
  }

  async refundPayment({ paymentId, amountPaise, notes = {} }) {
    const refund = await this.razorpay.payments.refund(paymentId, {
      amount: amountPaise,
      notes
    });
    return {
      id: refund.id,
      paymentId,
      amount: refund.amount,
      status: refund.status,
      createdAt: refund.created_at
    };
  }

  async createPayout({ accountId, amountPaise, currency = "INR", purpose = "payout", notes = {} }) {
    const payout = await this.razorpay.payouts.create({
      account_number: accountId,
      amount: amountPaise,
      currency,
      purpose,
      notes
    });
    return {
      id: payout.id,
      amount: payout.amount,
      status: payout.status,
      createdAt: payout.created_at
    };
  }

  async getPayment(paymentId) {
    const payment = await this.razorpay.payments.fetch(paymentId);
    return {
      id: payment.id,
      amount: payment.amount,
      status: payment.status,
      captured: payment.captured,
      createdAt: payment.created_at
    };
  }
}