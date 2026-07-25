/**
 * SessionMeter — the per-minute billing clock.
 *
 * On a fixed interval it scans active sessions and calls saga.tickSession on
 * each per-minute session. tickSession is pure clock math (no hardware call),
 * so the meter keeps working even if a device is offline: it accrues the charge
 * and auto-stops the session when the rider's selected duration elapses or the
 * accrued charge reaches the locked deposit.
 *
 * The meter is intentionally dumb and idempotent — every tick recomputes from
 * activeAt, so a missed or duplicated tick never double-bills.
 */
export class SessionMeter {
    constructor({ saga, store, eventBus, intervalMs = 15000, logger = console } = {}) {
        this.saga = saga;
        this.store = store;
        this.eventBus = eventBus;
        this.intervalMs = intervalMs;
        this.logger = logger;
        this.timer = null;
        this.running = false;
    }

    start() {
        if (this.timer) return this;
        // unref() so the meter never keeps the process alive on its own.
        this.timer = setInterval(() => this.tickOnce(), this.intervalMs);
        if (typeof this.timer.unref === "function") this.timer.unref();
        this.logger?.log?.(`SessionMeter started (every ${this.intervalMs}ms).`);
        return this;
    }

    stop() {
        if (this.timer) {
            clearInterval(this.timer);
            this.timer = null;
        }
        return this;
    }

    /**
     * Run a single sweep. Guarded against overlap so a slow sweep never stacks.
     * Each session is ticked independently; one failure doesn't abort the rest.
     */
    async tickOnce() {
        if (this.running) return { skipped: true };
        this.running = true;
        let ticked = 0;
        let stopped = 0;
        try {
            const sessions = await this.store.listSessions({ statuses: ["active"] });
            for (const session of sessions) {
                if (session.billingMode !== "per_minute") continue;
                try {
                    const result = await this.saga.tickSession(session.id);
                    ticked += 1;
                    if (result?.session?.status === "settled") stopped += 1;
                } catch (error) {
                    this.eventBus?.publish("meter.tick_failed", {
                        sessionId: session.id,
                        reason: error.code ?? error.message
                    });
                }
            }
        } finally {
            this.running = false;
        }
        return { ticked, stopped };
    }
}
