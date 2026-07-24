/**
 * UserWalletManager — auto-generates & funds custodial Stellar accounts for each user.
 * On testnet, new accounts are funded via Friendbot automatically.
 * Address mappings are persisted in-memory (KV store) keyed by userId.
 */
import { Keypair } from "@stellar/stellar-sdk";

const TESTNET_FRIENDBOT = "https://friendbot.stellar.org";
const FRIENDBOT_TIMEOUT_MS = 15_000;

export class UserWalletManager {
  /**
   * @param {object} opts
   * @param {Function} opts.getKv   - async (key) => value
   * @param {Function} opts.setKv   - async (key, value) => void
   * @param {string}   [opts.defaultAddress] - fallback address if generation fails
   * @param {boolean}  [opts.fundOnCreate]   - fund via Friendbot on testnet (default true)
   * @param {object}   [opts.logger]
   */
  constructor({ getKv, setKv, defaultAddress = null, fundOnCreate = true, logger = console } = {}) {
    this.getKv = getKv;
    this.setKv = setKv;
    this.defaultAddress = defaultAddress;
    this.fundOnCreate = fundOnCreate;
    this.logger = logger;
    // In-process cache so we don't hit KV store on every mint
    this._cache = new Map();
  }

  /**
   * Resolve or create a Stellar address for the given userId.
   * Returns a Stellar G... public key.
   */
  async resolveAddress(userId) {
    if (!userId) throw new Error("userId is required");

    // 1. In-process cache
    if (this._cache.has(userId)) return this._cache.get(userId);

    // 2. KV persistence
    const kvKey = `stellar:wallet:${userId}`;
    try {
      const stored = await this.getKv?.(kvKey);
      if (stored) {
        this._cache.set(userId, stored);
        return stored;
      }
    } catch (_) {}

    // 3. If userId looks like a Stellar address already, use it
    if (typeof userId === "string" && userId.startsWith("G") && userId.length === 56) {
      this._cache.set(userId, userId);
      return userId;
    }

    // 4. Generate a fresh custodial keypair for this user
    const kp = Keypair.random();
    const address = kp.publicKey();
    this.logger.info?.(`[wallet-manager] generated Stellar address for ${userId}: ${address}`);

    // 5. Fund on testnet via Friendbot
    if (this.fundOnCreate) {
      try {
        const res = await fetch(`${TESTNET_FRIENDBOT}?addr=${encodeURIComponent(address)}`, {
          signal: AbortSignal.timeout(FRIENDBOT_TIMEOUT_MS)
        });
        if (res.ok) {
          this.logger.info?.(`[wallet-manager] funded ${address} via Friendbot`);
        } else {
          const body = await res.text().catch(() => "");
          // Account may already be funded (duplicate), that's fine
          this.logger.warn?.(`[wallet-manager] Friendbot ${res.status}: ${body.slice(0, 100)}`);
        }
      } catch (err) {
        this.logger.warn?.(`[wallet-manager] Friendbot failed for ${address}: ${err?.message}`);
        // Non-fatal — contract storage doesn't require account to have XLM for mint target
      }
    }

    // 6. Persist
    try {
      await this.setKv?.(kvKey, address);
    } catch (_) {}
    this._cache.set(userId, address);

    return address;
  }

  /**
   * Get existing address without creating (returns null if not found).
   */
  async getAddress(userId) {
    if (this._cache.has(userId)) return this._cache.get(userId);
    const kvKey = `stellar:wallet:${userId}`;
    try {
      return (await this.getKv?.(kvKey)) ?? null;
    } catch {
      return null;
    }
  }
}
