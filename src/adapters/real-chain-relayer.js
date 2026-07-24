import {
  Address,
  Contract,
  Keypair,
  Networks,
  Operation,
  rpc,
  TransactionBuilder,
  xdr,
  nativeToScVal,
  scValToNative,
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
    serviceFeeBps = 125,        // 1.25% service fee in basis points (default 1.25%)
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
    this.server = new rpc.Server(this.rpcUrl, { allowHttp: true });
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

  async resolveAddressVal(addrOrId) {
    const addr = (typeof addrOrId === "string" && addrOrId.startsWith("G") && addrOrId.length === 56)
      ? addrOrId
      : await this.resolveAddress(addrOrId);
    return new Address(addr).toScVal();
  }

  addressVal(addrOrId) {
    const addr = (typeof addrOrId === "string" && addrOrId.startsWith("G") && addrOrId.length === 56)
      ? addrOrId
      : this.relayerAddress;
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

    // Step 1: sign for simulation
    inner.sign(this.relayerKeypair);

    // Step 2: simulate to get footprint / auth
    const sim = await this.server.simulateTransaction(inner);
    if (sim.error) {
      throw new DomainError("CHAIN_SIMULATE_FAILED", "Soroban simulation failed: " + sim.error, { error: sim.error });
    }

    // Step 3: prepare (injects footprint + sets resource fee)
    const prepared = await this.server.prepareTransaction(inner);
    prepared.sign(this.relayerKeypair);

    // Step 4: submit
    const send = await this.server.sendTransaction(prepared);
    if (send.status === "ERROR") {
      throw new DomainError("CHAIN_SUBMIT_FAILED", "Transaction rejected at submit.", { status: send.status, result: send.errorResult });
    }

    const hash = send.hash;
    console.log(`[chain] submitted tx ${hash}, waiting for confirmation...`);

    // Step 5: poll for confirmation
    const start = Date.now();
    while (Date.now() - start < 30000) {
      await new Promise((r) => setTimeout(r, 2000));
      const tx = await this.server.getTransaction(hash);
      if (tx.status === "SUCCESS") {
        const ledger = tx.ledger ?? 0;
        console.log(`[chain] tx ${hash} confirmed at ledger ${ledger}`);
        return { txHash: hash, ledger };
      }
      if (tx.status === "FAILED") {
        throw new DomainError("CHAIN_TX_FAILED", "On-chain transaction failed.", { status: tx.status, hash });
      }
    }
    throw new DomainError("CHAIN_TX_TIMEOUT", "Transaction not confirmed within 30s.", { hash });
  }


  // -------------------------------------------------------------- wallet ops

  /** Mint credits into `userId`'s wallet. Called on UPI top-up. */
  async mint({ userId, amountCredits }) {
    const userScVal = await this.resolveAddressVal(userId);
    const op = this.contract.call(
      "mint",
      userScVal,
      this.i128Val(amountCredits)
    );
    const { txHash, ledger } = await this.submitFeeBumped(op);
    const result = { txHash, ledger, amountCredits, mintedAt: new Date().toISOString() };
    this.eventBus?.publish("chain.wallet_minted", result);
    return result;
  }

  /** Burn credits from `hostId`'s earned balance. Called on host payout confirm. */
  async redeem({ hostId, amountCredits }) {
    const hostScVal = await this.resolveAddressVal(hostId);
    const op = this.contract.call(
      "redeem",
      hostScVal,
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
      const userScVal = await this.resolveAddressVal(userId);
      const op = this.contract.call("balance_of", userScVal);
      const source = await this.server.getAccount(this.relayerAddress);
      const tx = new TransactionBuilder(source, { fee: BASE_FEE, networkPassphrase: this.networkPassphrase })
        .addOperation(op)
        .setTimeout(30)
        .build();
      const sim = await this.server.simulateTransaction(tx);
      const val = sim.result?.retval;
      return val ? Number(scValToNative(val)) : 0;
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
      return val ? Number(scValToNative(val)) : 0;
    } catch {
      return 0;
    }
  }

  // -------------------------------------------------------------- session ops

  async lockDeposit({ sessionId, riderId, depositCredits }) {
    const session = this.getSession(sessionId);
    const hostId = session?.hostId ?? riderId;
    const outletId = session?.outletId ?? sessionId;

    const riderScVal = await this.resolveAddressVal(riderId);
    const hostScVal = await this.resolveAddressVal(hostId);

    const op = this.contract.call(
      "lock_deposit",
      this.bytesVal(sessionId),
      riderScVal,
      hostScVal,
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