export class RetryingChainRelayer {
  constructor({ delegate, retryPolicy }) {
    this.delegate = delegate;
    this.retryPolicy = retryPolicy;
  }

  lockDeposit(input) {
    return this.retryPolicy.run({
      operation: "chain.lock_deposit",
      context: { sessionId: input.sessionId },
      handler: () => this.delegate.lockDeposit(input)
    });
  }

  settleSession(input) {
    return this.retryPolicy.run({
      operation: "chain.settle_session",
      context: { sessionId: input.sessionId },
      handler: () => this.delegate.settleSession(input)
    });
  }

  refundDeposit(input) {
    return this.retryPolicy.run({
      operation: "chain.refund_deposit",
      context: { sessionId: input.sessionId },
      handler: () => this.delegate.refundDeposit(input)
    });
  }

  // Wallet operations (mint/redeem also need retry for transient failures)
  mint(input) {
    return this.retryPolicy.run({
      operation: "chain.mint",
      context: { userId: input.userId },
      handler: () => this.delegate.mint(input)
    });
  }

  redeem(input) {
    return this.retryPolicy.run({
      operation: "chain.redeem",
      context: { hostId: input.hostId },
      handler: () => this.delegate.redeem(input)
    });
  }

  // Views (no retry needed)
  balanceOf(userId) {
    return this.delegate.balanceOf(userId);
  }

  totalSupply() {
    return this.delegate.totalSupply();
  }

  getContractSession(sessionId) {
    return this.delegate.getContractSession(sessionId);
  }

  // Test/diagnostic controls forwarded from the underlying adapter.
  // Optional chaining keeps real adapters (which omit these) safe.
  simulateNextLockFailure(...args) {
    return this.delegate.simulateNextLockFailure?.(...args);
  }

  simulateNextSettleFailure(...args) {
    return this.delegate.simulateNextSettleFailure?.(...args);
  }

  simulateNextRefundFailure(...args) {
    return this.delegate.simulateNextRefundFailure?.(...args);
  }
}
