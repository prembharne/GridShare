import { DomainError } from "../core/errors.js";
import { fakeTxHash } from "../core/hash.js";

function clone(value) {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

export class MockChainRelayer {
  constructor({ eventBus }) {
    this.eventBus = eventBus;
    this.contractSessions = new Map();
    this.ledger = 1000;
    this.failNextLockCount = 0;
    this.failNextSettleCount = 0;
    this.failNextRefundCount = 0;
    this.balances = new Map();  // userId -> balanceCredits
    this._totalSupply = 0;  // backing field; totalSupply() is the accessor
  }

  simulateNextLockFailure(count = 1) {
    this.failNextLockCount = count;
  }

  simulateNextSettleFailure(count = 1) {
    this.failNextSettleCount = count;
  }

  simulateNextRefundFailure(count = 1) {
    this.failNextRefundCount = count;
  }

  // Wallet methods
  async mint({ userId, amountCredits }) {
    if (amountCredits <= 0) {
      throw new DomainError("INVALID_AMOUNT", "Mint amount must be positive.", { userId, amountCredits });
    }
    const current = this.balances.get(userId) ?? 0;
    this.balances.set(userId, current + amountCredits);
    this._totalSupply += amountCredits;

    const result = {
      txHash: fakeTxHash("mint", { userId, amountCredits }),
      ledger: ++this.ledger,
      status: "minted",
      amountCredits,
      mintedAt: new Date().toISOString()
    };
    this.eventBus?.publish("chain.wallet_minted", result);
    return clone(result);
  }

  async balanceOf(userId) {
    return this.balances.get(userId) ?? 0;
  }

  async totalSupply() {
    return this._totalSupply;
  }

  async redeem({ hostId, amountCredits }) {
    if (amountCredits <= 0) {
      throw new DomainError("INVALID_AMOUNT", "Redeem amount must be positive.", { hostId, amountCredits });
    }
    const current = this.balances.get(hostId) ?? 0;
    if (current < amountCredits) {
      throw new DomainError("INSUFFICIENT_BALANCE", "Insufficient balance for redeem.", { hostId, amountCredits, current });
    }
    this.balances.set(hostId, current - amountCredits);
    this._totalSupply -= amountCredits;

    const result = {
      txHash: fakeTxHash("redeem", { hostId, amountCredits }),
      ledger: ++this.ledger,
      status: "redeemed",
      amountCredits,
      redeemedAt: new Date().toISOString()
    };
    this.eventBus?.publish("chain.wallet_redeemed", result);
    return clone(result);
  }

  async lockDeposit({ sessionId, riderId, hostId, depositCredits }) {
    if (this.failNextLockCount > 0) {
      this.failNextLockCount -= 1;
      throw new DomainError("CHAIN_LOCK_FAILED", "Mock chain relayer failed to lock escrow.", { sessionId });
    }

    const existing = this.contractSessions.get(sessionId);
    if (existing?.status === "locked" || existing?.status === "settled") {
      return clone(existing.lockResult);
    }

    if (existing?.status === "refunded") {
      throw new DomainError("ESCROW_ALREADY_REFUNDED", "Escrow was already refunded.", { sessionId });
    }

    // Deduct deposit from rider's wallet balance
    const riderBalance = this.balances.get(riderId) ?? 0;
    if (riderBalance < depositCredits) {
      throw new DomainError("INSUFFICIENT_BALANCE", "Insufficient wallet balance for lock.", { riderId, depositCredits, balance: riderBalance });
    }
    this.balances.set(riderId, riderBalance - depositCredits);

    const result = {
      sessionId,
      txHash: fakeTxHash("lock", { sessionId, riderId, depositCredits }),
      ledger: ++this.ledger,
      status: "locked",
      feeBumped: true,
      lockedAt: new Date().toISOString()
    };

    this.contractSessions.set(sessionId, {
      sessionId,
      riderId,
      hostId,
      depositCredits,
      status: "locked",
      lockResult: result,
      settlementResult: null
    });

    this.eventBus.publish("chain.escrow_locked", result);
    return clone(result);
  }

  async settleSession({ sessionId, settlement, oracleReport }) {
    if (this.failNextSettleCount > 0) {
      this.failNextSettleCount -= 1;
      throw new DomainError("CHAIN_SETTLE_FAILED", "Mock chain relayer failed to settle escrow.", { sessionId });
    }

    const existing = this.contractSessions.get(sessionId);

    if (!existing) {
      throw new DomainError("ESCROW_NOT_FOUND", "No escrow exists for this session.", { sessionId });
    }

    if (existing.status === "settled") {
      return clone(existing.settlementResult);
    }

    if (existing.status !== "locked") {
      throw new DomainError("ESCROW_NOT_SETTLEABLE", "Escrow is not in a settleable state.", {
        sessionId,
        status: existing.status
      });
    }

    const { riderId, hostId, depositCredits } = existing;
    const treasuryId = "treasury"; // fixed treasury address

    // Transfer credits: host share, service fee to treasury, refund to rider
    if (settlement.hostShareCredits > 0) {
      this.balances.set(hostId, (this.balances.get(hostId) ?? 0) + settlement.hostShareCredits);
    }
    if (settlement.serviceFeeCredits > 0) {
      this.balances.set(treasuryId, (this.balances.get(treasuryId) ?? 0) + settlement.serviceFeeCredits);
    }
    if (settlement.refundCredits > 0) {
      this.balances.set(riderId, (this.balances.get(riderId) ?? 0) + settlement.refundCredits);
    }

    const result = {
      sessionId,
      txHash: fakeTxHash("settle", { sessionId, settlement }),
      ledger: ++this.ledger,
      status: "settled",
      settlement,
      oracleReport,
      settledAt: new Date().toISOString()
    };

    this.contractSessions.set(sessionId, {
      ...existing,
      status: "settled",
      settlementResult: result
    });

    this.eventBus.publish("chain.session_settled", result);
    return clone(result);
  }

  async refundDeposit({ sessionId, reason }) {
    if (this.failNextRefundCount > 0) {
      this.failNextRefundCount -= 1;
      throw new DomainError("CHAIN_REFUND_FAILED", "Mock chain relayer failed to refund escrow.", { sessionId });
    }

    const existing = this.contractSessions.get(sessionId);

    if (!existing) {
      throw new DomainError("ESCROW_NOT_FOUND", "No escrow exists for this session.", { sessionId });
    }

    if (existing.status === "refunded") {
      return clone(existing.refundResult);
    }

    if (existing.status !== "locked") {
      throw new DomainError("ESCROW_NOT_REFUNDABLE", "Escrow is not refundable.", {
        sessionId,
        status: existing.status
      });
    }

    const { riderId, depositCredits } = existing;

    // Return full deposit to rider
    this.balances.set(riderId, (this.balances.get(riderId) ?? 0) + depositCredits);

    const result = {
      sessionId,
      txHash: fakeTxHash("refund", { sessionId, reason }),
      ledger: ++this.ledger,
      status: "refunded",
      reason,
      refundedAt: new Date().toISOString()
    };

    this.contractSessions.set(sessionId, {
      ...existing,
      status: "refunded",
      refundResult: result
    });

    this.eventBus.publish("chain.escrow_refunded", result);
    return clone(result);
  }

  getContractSession(sessionId) {
    return clone(this.contractSessions.get(sessionId));
  }

  // Wallet methods for credit model
  async mint({ userId, amountCredits }) {
    const existing = this.balances.get(userId) ?? 0;
    this.balances.set(userId, existing + amountCredits);
    this._totalSupply = (this._totalSupply ?? 0) + amountCredits;
    this.eventBus?.publish("chain.wallet_minted", { userId, amountCredits });
    return { userId, amountCredits, txHash: fakeTxHash("mint", { userId, amountCredits }), ledger: ++this.ledger };
  }

  async balanceOf(userId) {
    return this.balances.get(userId) ?? 0;
  }

  async redeem({ hostId, amountCredits }) {
    const existing = this.balances.get(hostId) ?? 0;
    if (existing < amountCredits) {
      throw new DomainError("INSUFFICIENT_BALANCE", "Insufficient balance for redeem.", { hostId });
    }
    this.balances.set(hostId, existing - amountCredits);
    this._totalSupply = (this._totalSupply ?? 0) - amountCredits;
    this.eventBus?.publish("chain.wallet_redeemed", { hostId, amountCredits });
    return { hostId, amountCredits, txHash: fakeTxHash("redeem", { hostId, amountCredits }), ledger: ++this.ledger };
  }

  async totalSupply() {
    return this._totalSupply ?? 0;
  }
}
