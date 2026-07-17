import { DomainError } from "./errors.js";
import { hashPayload } from "./hash.js";

function clone(value) {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

export class IdempotencyStore {
  constructor() {
    this.records = new Map();
    this.inFlight = new Map();
  }

  async run(scope, key, payload, handler) {
    if (!key) {
      return handler();
    }

    const recordKey = `${scope}:${key}`;
    const payloadHash = hashPayload(payload);
    const existing = this.records.get(recordKey);

    if (existing) {
      if (existing.payloadHash !== payloadHash) {
        throw new DomainError(
          "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD",
          "The idempotency key was already used with a different payload.",
          { scope, key }
        );
      }

      return clone(existing.response);
    }

    const pending = this.inFlight.get(recordKey);
    if (pending) {
      if (pending.payloadHash !== payloadHash) {
        throw new DomainError(
          "IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD",
          "The idempotency key is already running with a different payload.",
          { scope, key }
        );
      }

      return clone(await pending.promise);
    }

    let run;
    const promise = new Promise((resolve, reject) => {
      run = async () => {
        try {
          const response = await handler();
          const storedResponse = clone(response);
          this.records.set(recordKey, {
            payloadHash,
            response: storedResponse,
            createdAt: new Date().toISOString()
          });
          resolve(storedResponse);
        } catch (error) {
          reject(error);
        } finally {
          this.inFlight.delete(recordKey);
        }
      };
    });

    this.inFlight.set(recordKey, { payloadHash, promise });
    run();
    return clone(await promise);
  }
}
