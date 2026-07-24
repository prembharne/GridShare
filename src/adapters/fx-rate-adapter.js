import { DomainError } from "../core/errors.js";

/**
 * FxRateAdapter — live USD→INR exchange rate with an in-memory cache and a
 * configurable fallback.
 *
 * Used by the USDC top-up path: 1 USDC == 1 USD, so credits minted =
 * floor(usdcAmount * usdInrRate). The rate is fetched from a free, no-key
 * provider (open.er-api.com by default), cached for `cacheTtlSeconds`, and
 * falls back to `fallbackRate` when the provider is unreachable or returns a
 * malformed body. This keeps top-ups working offline/in CI without a network.
 *
 * Injected `fetchImpl` (defaults to global fetch) makes it unit-testable.
 */
export class FxRateAdapter {
  constructor({ url, fallbackRate, cacheTtlSeconds, fetchImpl } = {}) {
    this.url = url ?? "https://open.er-api.com/v6/latest/USD";
    this.fallbackRate = Number.isFinite(fallbackRate) && fallbackRate > 0 ? fallbackRate : 95;
    this.cacheTtlMs = (Number.isFinite(cacheTtlSeconds) ? cacheTtlSeconds : 3600) * 1000;
    this.fetchImpl = fetchImpl ?? globalThis.fetch;
    this._cached = null; // { rate, fetchedAtMs }
  }

  /**
   * Return the current USD→INR rate plus metadata about where it came from.
   * Never throws: on any failure it serves the last cached value, else the
   * configured fallback.
   */
  async getUsdInr() {
    const nowMs = Date.now();

    if (this._cached && nowMs - this._cached.fetchedAtMs < this.cacheTtlMs) {
      return { rate: this._cached.rate, source: "cache", fetchedAt: new Date(this._cached.fetchedAtMs).toISOString() };
    }

    try {
      const rate = await this._fetchLive();
      this._cached = { rate, fetchedAtMs: nowMs };
      return { rate, source: "live", fetchedAt: new Date(nowMs).toISOString() };
    } catch (error) {
      if (this._cached) {
        return {
          rate: this._cached.rate,
          source: "stale-cache",
          fetchedAt: new Date(this._cached.fetchedAtMs).toISOString(),
          warning: String(error.message ?? error)
        };
      }
      return { rate: this.fallbackRate, source: "fallback", warning: String(error.message ?? error) };
    }
  }

  async _fetchLive() {
    if (typeof this.fetchImpl !== "function") {
      throw new DomainError("FX_FETCH_UNAVAILABLE", "No fetch implementation available for FX rate.");
    }

    const response = await this.fetchImpl(this.url, { method: "GET" });
    if (!response.ok) {
      throw new DomainError("FX_FETCH_FAILED", `FX provider returned HTTP ${response.status}.`, { status: response.status });
    }

    const body = await response.json();
    // open.er-api.com shape: { result: "success", rates: { INR: 96.5, ... } }
    const rate = body?.rates?.INR;
    if (body?.result && body.result !== "success") {
      throw new DomainError("FX_PROVIDER_ERROR", "FX provider reported a non-success result.", { result: body.result });
    }
    if (!Number.isFinite(rate) || rate <= 0) {
      throw new DomainError("FX_RATE_MALFORMED", "FX provider response had no valid INR rate.");
    }

    return rate;
  }
}
