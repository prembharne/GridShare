import crypto from "node:crypto";
import { DomainError } from "../core/errors.js";

export class PostgresIdempotencyStore {
  constructor({ store }) {
    this.store = store;
  }

  async run(scope, key, payload, handler) {
    const payloadHash = this.hashPayload(payload);
    const existing = await this.store.getIdempotencyKey(scope, key);

    if (existing) {
      if (existing.payloadHash !== payloadHash) {
        throw new DomainError("IDEMPOTENCY_KEY_CONFLICT", "Idempotency key reused with different payload.", { scope, key });
      }
      return JSON.parse(existing.responseJson);
    }

    const result = await handler();
    await this.store.createIdempotencyKey(scope, key, payloadHash, JSON.stringify(result));
    return result;
  }

  hashPayload(payload) {
    return crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex");
  }
}