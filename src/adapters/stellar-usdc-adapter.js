import {
  Asset,
  Horizon,
  Networks,
} from "@stellar/stellar-sdk";
import crypto from "node:crypto";
import { DomainError } from "../core/errors.js";

/**
 * Stellar USDC deposit on-ramp (testnet).
 *
 * USDC is a CLASSIC Stellar asset, so deposits settle on the classic ledger and
 * are watched via Horizon — separate from the Soroban credit contract path
 * (see real-chain-relayer.js). This adapter never touches the contract; it only
 * builds deposit intents and observes incoming USDC payments, handing matched
 * ones to a callback that converges on saga.topUpWallet -> chain.mint of the
 * SAME credit token used by UPI.
 *
 * Correlation: each deposit intent gets a unique text MEMO the rider must
 * include. Idempotency downstream is keyed on the Stellar tx hash.
 *
 * This adapter is intentionally stateless w.r.t. the Horizon cursor: the caller
 * owns cursor persistence and passes the resume cursor into watchPayments and
 * receives paging tokens via onCursor. That keeps cursor storage in one place
 * (the app-level watcher, backed by store.getKv/setKv).
 */
export class StellarUsdcAdapter {
  constructor({
    horizonUrl,
    networkPassphrase,
    assetCode = "USDC",
    assetIssuer,
    receivePublicKey,
    receiveSecretKey,
    logger = console,
    eventBus = null,
  } = {}) {
    if (!assetIssuer) {
      throw new DomainError("INVALID_CONFIG", "StellarUsdcAdapter requires assetIssuer.");
    }
    if (!receivePublicKey) {
      throw new DomainError("INVALID_CONFIG", "StellarUsdcAdapter requires receivePublicKey.");
    }
    this.horizonUrl = horizonUrl ?? "https://horizon-testnet.stellar.org";
    this.networkPassphrase = networkPassphrase ?? Networks.TESTNET;
    this.assetCode = assetCode;
    this.assetIssuer = assetIssuer;
    this.asset = new Asset(assetCode, assetIssuer);
    this.receivePublicKey = receivePublicKey;
    // Secret is only needed for account setup (trustline funding); watching only
    // needs the public key.
    this.receiveSecretKey = receiveSecretKey || null;
    this.logger = logger;
    this.eventBus = eventBus;
    this.server = new Horizon.Server(this.horizonUrl);
    this._closeStream = null;
  }

  /** Generate a short, unique, memo-safe correlation key (<= 28 bytes for MEMO_TEXT). */
  static generateMemo() {
    return `GS${crypto.randomUUID().replaceAll("-", "").slice(0, 24)}`;
  }

  /**
   * Build a deposit intent: a unique correlation memo, the receiving address,
   * the exact USDC amount to send, and a SEP-0007 `web+stellar:pay` URI the
   * mobile app renders as a QR code. The caller persists the intent (memo,
   * amountCredits, expectedUsdc, lockedRate) so the watcher can match the
   * incoming payment back to a user and a credit amount.
   */
  buildIntent({ amountCredits, expectedUsdc, asset = "USDC" }) {
    if (!(Number(expectedUsdc) > 0)) {
      throw new DomainError("INVALID_AMOUNT", "expectedUsdc must be a positive number.");
    }
    const paymentAsset = String(asset).toUpperCase() === "XLM" ? "XLM" : "USDC";
    const memo = StellarUsdcAdapter.generateMemo();
    const qrUri = this._buildDepositUri({ memo, amount: expectedUsdc, asset: paymentAsset });
    return {
      memo,
      depositAddress: this.receivePublicKey,
      assetCode: paymentAsset === "XLM" ? "XLM" : this.assetCode,
      assetIssuer: paymentAsset === "XLM" ? "" : this.assetIssuer,
      assetType: paymentAsset === "XLM" ? "native" : "credit_alphanum4",
      expectedUsdc,
      amountCredits,
      qrUri,
    };
  }

  /** SEP-0007 payment URI (rendered as a QR by the mobile app). */
  _buildDepositUri({ memo, amount, asset = "USDC" }) {
    const params = new URLSearchParams({
      destination: this.receivePublicKey,
      amount: String(amount),
      memo_type: "MEMO_TEXT",
      memo,
    });
    if (asset === "XLM") {
      params.set("asset_code", "native");
    } else {
      params.set("asset_code", this.assetCode);
      params.set("asset_issuer", this.assetIssuer);
    }
    return `web+stellar:pay?${params.toString()}`;
  }

  /**
   * Stream incoming payments to the receiving account and invoke onPayment for
   * each confirmed USDC credit. Resumes from the caller-supplied `cursor` so a
   * restart never misses or double-processes a payment (the callback itself must
   * also be idempotent on tx hash). After every message the paging token is
   * reported via onCursor so the caller can persist it.
   *
   * @param {object}   opts
   * @param {string}  [opts.cursor="now"]  Horizon paging token to resume from.
   * @param {Function} opts.onPayment      async ({memo, amountUsdc, txHash, from, createdAt})
   * @param {Function} [opts.onCursor]     async (pagingToken) => void
   * @returns {Function} stop() to close the stream.
   */
  async watchPayments({ cursor = "now", onPayment, onCursor } = {}) {
    if (typeof onPayment !== "function") {
      throw new DomainError("INVALID_CONFIG", "watchPayments requires an onPayment callback.");
    }

    this.logger.log?.(`[usdc] watching ${this.receivePublicKey} from cursor ${cursor}`);

    this._closeStream = this.server
      .payments()
      .forAccount(this.receivePublicKey)
      .cursor(cursor)
      .stream({
        onmessage: async (payment) => {
          try {
            await this._handlePayment(payment, onPayment);
          } catch (err) {
            this.logger.error?.(`[usdc] payment handler failed: ${err?.message ?? err}`);
          } finally {
            // Advance the cursor even on non-matching payments so we don't
            // re-scan them; the callback is idempotent for matched ones.
            if (payment?.paging_token && typeof onCursor === "function") {
              try {
                await onCursor(payment.paging_token);
              } catch (err) {
                this.logger.error?.(`[usdc] onCursor failed: ${err?.message ?? err}`);
              }
            }
          }
        },
        onerror: (err) => {
          this.logger.error?.(`[usdc] stream error: ${err?.message ?? err}`);
        },
      });

    return () => this.close();
  }

  async _handlePayment(payment, onPayment) {
    // Accept configured USDC and native XLM into the receiving account; the
    // app-level intent check decides which asset is valid for a given memo.
    if (payment.type !== "payment") return;
    if (payment.to !== this.receivePublicKey) return;

    const isUsdc = payment.asset_code === this.assetCode && payment.asset_issuer === this.assetIssuer;
    const isNativeXlm = payment.asset_type === "native";

    if (!isUsdc && !isNativeXlm) return;

    // Memo lives on the transaction, not the payment op — fetch it.
    let memo = null;
    try {
      const tx = await payment.transaction();
      memo = tx?.memo ?? null;
    } catch (err) {
      this.logger.error?.(`[usdc] failed to load tx for memo: ${err?.message ?? err}`);
    }

    await onPayment({
      txHash: payment.transaction_hash,
      amountUsdc: Number(payment.amount),
      assetCode: isNativeXlm ? "XLM" : this.assetCode,
      assetType: isNativeXlm ? "native" : "credit_alphanum4",
      isNativeXlm,
      from: payment.from,
      memo,
      createdAt: payment.created_at,
    });
  }

  /**
   * Directly fetch recent payments from Horizon REST API to verify if a payment
   * matching `memo` (or recent matching asset payment) has arrived.
   */
  async checkRecentPayments({ memo, asset = "USDC" } = {}) {
    const expectedAsset = String(asset).toUpperCase() === "XLM" ? "XLM" : "USDC";
    try {
      const url = `${this.horizonUrl}/accounts/${this.receivePublicKey}/payments?order=desc&limit=20`;
      const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
      if (!res.ok) return null;
      const data = await res.json();
      const records = data._embedded?.records ?? [];

      let fallbackPayment = null;

      for (const payment of records) {
        if (payment.type !== "payment" || payment.to !== this.receivePublicKey) continue;
        const isUsdc = payment.asset_code === this.assetCode && payment.asset_issuer === this.assetIssuer;
        const isNativeXlm = payment.asset_type === "native";
        const matchesAsset = expectedAsset === "XLM" ? isNativeXlm : isUsdc;
        if (!matchesAsset) continue;

        let txMemo = null;
        try {
          const txRes = await fetch(`${this.horizonUrl}/transactions/${payment.transaction_hash}`, {
            signal: AbortSignal.timeout(5000)
          });
          if (txRes.ok) {
            const txData = await txRes.json();
            txMemo = txData.memo ?? null;
          }
        } catch (_) {}

        // Pass 1: Exact memo match
        if (txMemo && (txMemo === memo || String(txMemo).trim() === String(memo).trim())) {
          return {
            txHash: payment.transaction_hash,
            amountUsdc: Number(payment.amount),
            assetCode: isNativeXlm ? "XLM" : this.assetCode,
            assetType: isNativeXlm ? "native" : "credit_alphanum4",
            isNativeXlm,
            from: payment.from,
            memo: txMemo,
            createdAt: payment.created_at,
          };
        }

        // Pass 2 candidate: latest matching payment within last 30 minutes
        if (!fallbackPayment) {
          const createdMs = payment.created_at ? new Date(payment.created_at).getTime() : Date.now();
          const ageMs = Date.now() - createdMs;
          if (ageMs < 30 * 60 * 1000) {
            fallbackPayment = {
              txHash: payment.transaction_hash,
              amountUsdc: Number(payment.amount),
              assetCode: isNativeXlm ? "XLM" : this.assetCode,
              assetType: isNativeXlm ? "native" : "credit_alphanum4",
              isNativeXlm,
              from: payment.from,
              memo: txMemo,
              createdAt: payment.created_at,
            };
          }
        }
      }

      if (fallbackPayment) {
        return fallbackPayment;
      }
    } catch (err) {
      this.logger.error?.(`[usdc] checkRecentPayments failed: ${err?.message ?? err}`);
    }
    return null;
  }


  close() {
    if (this._closeStream) {
      this._closeStream();
      this._closeStream = null;
    }
  }
}

