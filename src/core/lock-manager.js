export class LockManager {
  constructor() {
    this.tails = new Map();
  }

  async runExclusive(key, handler) {
    const previousTail = this.tails.get(key) ?? Promise.resolve();
    let release;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    const nextTail = previousTail.catch(() => {}).then(() => gate);

    this.tails.set(key, nextTail);
    await previousTail.catch(() => {});

    try {
      return await handler();
    } finally {
      release();
      if (this.tails.get(key) === nextTail) {
        this.tails.delete(key);
      }
    }
  }
}
