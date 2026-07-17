import {
  Address,
  Contract,
  Keypair,
  Networks,
  Operation,
  SorobanRpc,
  TransactionBuilder,
  xdr,
  nativeToScVal,
  BASE_FEE,
} from "@stellar/stellar-sdk";
import crypto from "node:crypto";
import { DomainError } from "../core/errors.js";

const REASON_SYMBOLS = {
  user_stop: "user",
  auto_threshold: "auto",
  safety_trip: "safety",
  hardware_activation_failed: "actfail",
  manual: "user",
};

/**
 * Production Soroban relayer for the GridShare credit-wallet contract.
 * No external token; credits are native to the contract.
 * Every mutating call is fee-bumped (CAP-0015) with the relayer
 * key and awaited to confirmation.
 */
export class RealChainRelayer {
  constructor({
    rpcUrl,
    networkPassphrase,
    contractId,
    relayerSecretKey,
    tokenAddress,               // optional, accepted for backward compat but unused
    tokenUnitsPerPaise,         // optional, accepted for backward compat but unused
    pricePerKwhCredits = 1800,  // credits per 1000 Wh (whole credits)
    serviceFeeBps = 300,        // 2-3% service fee in basis points (default 3%)
    resolveAddress,
    getSession,
    eventBus,
  } = {}) {
    if (!contractId || !relayerSecretKey) {
      throw new DomainError(
        "INVALID_CONFIG",
        "RealChainRelayer requires contractId and relayerSecretKey."
      );
    }
    this.rpcUrl = rpcUrl ?? "https://soroban-testnet.stellar.org";
    this.networkPassphrase = networkPassphrase ?? Networks.TESTNET;
    this.contract = new Contract(contractId);
    this.relayerKeypair = Keypair.fromSecret(relayerSecretKey);
    this.relayerAddress = this.relayerKeypair.publicKey();
    // tokenAddress and tokenUnitsPerPaise accepted but unused in credit model
    this.pricePerKwhCredits = pricePerKwhCredits;
    this.serviceFeeBps = serviceFeeBps;
    this.resolveAddress = resolveAddress ?? ((id) => { throw new DomainError("ADDRESS_UNRESOLVED", `No address mapping for ${id}.`); });
    this.getSession = getSession ?? (() => null);
    this.eventBus = eventBus;
    this.server = new SorobanRpc.Server(this.rpcUrl, { allowHttp: true });
    this.contractSessions = new Map();
  }

  // ---------------------------------------------------------------- helpers

  bytesVal(str) {
    return xdr.ScVal.scvBytes(Buffer.from(str, "utf8"));
  }

  i128Val(n) {
    return nativeToScVal(n, { type: "i128" });
  }

  symbolVal(s) {
    return nativeToScVal(s, { type: "symbol" });
  }

  addressVal(addrOrId) {
    const addr = typeof addrOrId === "string" && addrOrId.startsWith("G")
      ? addrOrId
      : this.resolveAddress(addrOrId);
    return new Address(addr).toScVal();
  }

  async submitFeeBumped(operation) {
    const source = await this.server.getAccount(this.relayerAddress);
    const inner = new TransactionBuilder(source, {
      fee: BASE_FEE,
      networkPassphrase: this.networkPassphrase,
    })
      .addOperation(operation)
      .setTimeout(60)
      .build();

    const innerSigned = inner.signAndPrebuild(this.relayerKeypair).toEnvelope();

    const feeBump = TransactionBuilder.buildFeeBumpTransaction(
      this.relayerKeypair,
      BASE_FEE,
      innerSigned,
      this.networkPassphrase
    ).build();

    const send = await this.server.sendTransaction(feeBump);
    if (send.status && send.status !== "PENDING" && send.status !== "SUCCESS") {
      throw new DomainError("CHAIN_SUBMIT_FAILED", "Transaction rejected at submit.", { status: send.status });
    }

    const hash = send.hash;
    const start = Date.now();
    let result;
    while (Date.now() - start < 30000) {
      await new Promise((r) => setTimeout(r, 1000));
      const tx = await this.server.getTransaction(hash);
      if (tx.status === "SUCCESS") {
        result = tx;
        break;
      }
      if (tx.status === "FAILED" || tx.status === "NOT_FOUND") {
        throw new DomainError("CHAIN_TX_FAILED", "On-chain transaction failed.", { status: tx.status, hash });
      }
    }
    if (!result) {
      throw new DomainError("CHAIN_TX_TIMEOUT", "Transaction not confirmed within 30s.", { hash });
    }

    const ledger = result.ledger ?? 0;
    return { txHash: hash, ledger };
  }

  // -------------------------------------------------------------- wallet ops

  /** Mint credits into `userId`'s wallet. Called on UPI top-up. */
  async mint({ userId, amountCredits }) {
    const op = this.contract.call(
      "mint",
      this.addressVal(userId),
      this.i128Val(amountCredits)
    );
    const { txHash, ledger } = await this.submitFeeBumped(op);
    const result = { txHash, ledger, amountCredits, mintedAt: new Date().toISOString() };
    this.eventBus?.publish("chain.wallet_minted", result);
    return result;
  }

  /** Burn credits from `hostId`'s earned balance. Called on host payout confirm. */
  async redeem({ hostId, amountCredits }) {
    const op = this.contract.call(
      "redeem",
      this.addressVal(hostId),
      this.i128Val(amountCredits)
    );
    const { txHash, ledger } = await this.submitFeeBumped(op);
    const result = { txHash, ledger, amountCredits, redeemedAt: new Date().toISOString() };
    this.eventBus?.publish("chain.wallet_redeemed", result);
    return result;
  }

  /** View: get a user's spendable/earned credit balance. */
  async balanceOf(userId) {
    try {
      const op = this.contract.call("balance_of", this.addressVal(userId));
      const source = await this.server.getAccount(this.relayerAddress);
      const tx = new TransactionBuilder(source, { fee: BASE_FEE, networkPassphrase: this.networkPassphrase })
        .addOperation(op)
        .setTimeout(30)
        .build();
      const sim = await this.server.simulateTransaction(tx);
      const val = sim.result?.retval;
      return val ? Number(val) : 0;
    } catch {
      return 0;
    }
  }

  /** View: get total supply of credits (sum of all balances). */
  async totalSupply() {
    try {
      const op = this.contract.call("total_supply");
      const source = await this.server.getAccount(this.relayerAddress);
      const tx = new TransactionBuilder(source, { fee: BASE_FEE, networkPassphrase: this.networkPassphrase })
        .addOperation(op)
        .setTimeout(30)
        .build();
      const sim = await this.server.simulateTransaction(tx);
      const val = sim.result?.retval;
      return val ? Number(val) : 0;
    } catch {
      return 0;
    }
  }

  // -------------------------------------------------------------- session ops

  async lockDeposit({ sessionId, riderId, depositCredits }) {
    const session = this.getSession(sessionId);
    const hostId = session?.hostId ?? riderId;
    const outletId = session?.outletId ?? sessionId;

    const op = this.contract.call(
      "lock_deposit",
      this.bytesVal(sessionId),
      this.addressVal(riderId),
      this.addressVal(hostId),
      this.bytesVal(outletId),
      this.i128Val(depositCredits),
      this.i128Val(this.pricePerKwhCredits),
      this.i128Val(this.serviceFeeBps)
    );

    const { txHash, ledger } = await this.submitFeeBumped(op);

    const result = {
      sessionId,
      txHash,
      ledger,
      status: "locked",
      feeBumped: true,
      lockedAt: new Date().toISOString(),
    };
    this.contractSessions.set(sessionId, { status: "locked", lockResult: result });
    this.eventBus?.publish("chain.escrow_locked", result);
    return result;
  }

  async settleSession({ sessionId, settlement, oracleReport }) {
    const energyWh = settlement?.energyWh ?? oracleReport?.finalTelemetry?.energyWh ?? 0;
    const telemetryHash = crypto
      .createHash("sha256")
      .update(JSON.stringify(oracleReport ?? {}))
      .digest("hex");
    const reason = REASON_SYMBOLS[oracleReport?.reason] ?? "auto";

    const op = this.contract.call(
      "settle_session",
      this.bytesVal(sessionId),
      this.i128Val(energyWh),
      this.bytesVal(telemetryHash),
      this.symbolVal(reason)
    );

    const { txHash, ledger } = await this.submitFeeBumped(op);

    const result = {
      sessionId,
      txHash,
      ledger,
      status: "settled",
      settlement,
      settledAt: new Date().toISOString(),
    };
    this.contractSessions.set(sessionId, { status: "settled", settlementResult: result });
    this.eventBus?.publish("chain.session_settled", result);
    return result;
  }

  async refundDeposit({ sessionId, reason }) {
    const symbol = REASON_SYMBOLS[reason] ?? "actfail";
    const op = this.contract.call(
      "refund_deposit",
      this.bytesVal(sessionId),
      this.symbolVal(symbol)
    );

    const { txHash, ledger } = await this.submitFeeBumped(op);

    const result = {
      sessionId,
      txHash,
      ledger,
      status: "refunded",
      reason,
      refundedAt: new Date().toISOString(),
    };
    this.contractSessions.set(sessionId, { status: "refunded", refundResult: result });
    this.eventBus?.publish("chain.escrow_refunded", result);
    return result;
  }

  async getContractSession(sessionId) {
    try {
      const op = this.contract.call("get_session", this.bytesVal(sessionId));
      const source = await this.server.getAccount(this.relayerAddress);
      const tx = new TransactionBuilder(source, { fee: BASE_FEE, networkPassphrase: this.networkPassphrase })
        .addOperation(op)
        .setTimeout(30)
        .build();
      const sim = await this.server.simulateTransaction(tx);
      const val = sim.result?.retval;
      if (!val) return null;
      return this.decodeSession(val);
    } catch {
      return this.contractSessions.get(sessionId) ?? null;
    }
  }

  decodeSession(scVal) {
    // Minimal decode; in production parse the full SessionData struct.
    return { raw: scVal?.value()?.toString?.() ?? null };
  }

  clone(value) {
    return value === undefined ? value : JSON.parse(JSON.stringify(value));
  }
}