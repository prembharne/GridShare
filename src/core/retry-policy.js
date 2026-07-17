const DEFAULT_RETRYABLE_CODES = new Set([
  "CHAIN_LOCK_FAILED",
  "CHAIN_SETTLE_FAILED",
  "CHAIN_REFUND_FAILED",
  "HARDWARE_COMMAND_FAILED"
]);

function delay(ms) {
  if (ms <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export class RetryPolicy {
  constructor({ attempts = 1, baseDelayMs = 0, eventBus, retryableCodes = DEFAULT_RETRYABLE_CODES } = {}) {
    this.attempts = Math.max(1, attempts);
    this.baseDelayMs = Math.max(0, baseDelayMs);
    this.eventBus = eventBus;
    this.retryableCodes = retryableCodes;
  }

  async run({ operation, context = {}, handler }) {
    let lastError;

    for (let attempt = 1; attempt <= this.attempts; attempt += 1) {
      try {
        const result = await handler({ attempt });
        if (attempt > 1) {
          this.eventBus?.publish("adapter.retry_succeeded", {
            operation,
            attempt,
            ...context
          });
        }
        return result;
      } catch (error) {
        lastError = error;
        const canRetry = attempt < this.attempts && this.retryableCodes.has(error.code);

        if (!canRetry) {
          throw error;
        }

        this.eventBus?.publish("adapter.retry_scheduled", {
          operation,
          attempt,
          nextAttempt: attempt + 1,
          errorCode: error.code,
          ...context
        });

        await delay(this.baseDelayMs * attempt);
      }
    }

    throw lastError;
  }
}
