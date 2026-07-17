export class RetryingHardwareBridge {
  constructor({ delegate, retryPolicy }) {
    this.delegate = delegate;
    this.retryPolicy = retryPolicy;
  }

  setSwitch(input) {
    return this.retryPolicy.run({
      operation: input.desiredState ? "hardware.switch_on" : "hardware.switch_off",
      context: { sessionId: input.sessionId, outletId: input.outletId },
      handler: () => this.delegate.setSwitch(input)
    });
  }

  getSwitchState(outletId) {
    return this.delegate.getSwitchState(outletId);
  }

  getCommands(filter) {
    return this.delegate.getCommands(filter);
  }

  // Test/diagnostic controls forwarded from the underlying adapter.
  // Optional chaining keeps real adapters (which omit these) safe.
  simulateNextOnFailure(...args) {
    return this.delegate.simulateNextOnFailure?.(...args);
  }

  simulateNextOffFailure(...args) {
    return this.delegate.simulateNextOffFailure?.(...args);
  }
}
