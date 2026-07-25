import assert from "node:assert/strict";
import test from "node:test";
import {
    computeTimeSettlement,
    activeSecondsBetween
} from "../src/domain/time-settlement-math.js";

// ============================ Time Settlement Math ============================

test("bills per whole minute, rounding partial minutes up", () => {
    // 90s active @ 2 credits/min → ceil(90/60)=2 min → 4 credits due
    const s = computeTimeSettlement({
        depositCredits: 50,
        activeSeconds: 90,
        ratePerMinuteCredits: 2,
        serviceFeeBps: 300
    });
    assert.equal(s.billedMinutes, 2);
    assert.equal(s.amountDueCredits, 4);
    assert.equal(s.serviceFeeCredits, 0); // floor(4 * 300/10000) = 0
    assert.equal(s.hostShareCredits, 4);
    assert.equal(s.refundCredits, 46);
});

test("caps amount due at the locked deposit", () => {
    // 100 min @ 2 = 200 due, but deposit is only 50 → capped at 50
    const s = computeTimeSettlement({
        depositCredits: 50,
        activeSeconds: 100 * 60,
        ratePerMinuteCredits: 2,
        serviceFeeBps: 300
    });
    assert.equal(s.amountDueCredits, 50);
    assert.equal(s.refundCredits, 0);
    assert.equal(s.serviceFeeCredits, 1); // floor(50 * 300/10000) = 1
    assert.equal(s.hostShareCredits, 49);
});

test("zero active time bills nothing and refunds the full deposit", () => {
    const s = computeTimeSettlement({
        depositCredits: 50,
        activeSeconds: 0,
        ratePerMinuteCredits: 2,
        serviceFeeBps: 300
    });
    assert.equal(s.billedMinutes, 0);
    assert.equal(s.amountDueCredits, 0);
    assert.equal(s.refundCredits, 50);
});

test("conservation invariant always holds", () => {
    for (const activeSeconds of [0, 1, 59, 60, 61, 600, 3600, 99999]) {
        const s = computeTimeSettlement({
            depositCredits: 137,
            activeSeconds,
            ratePerMinuteCredits: 3,
            serviceFeeBps: 250
        });
        assert.equal(
            s.hostShareCredits + s.serviceFeeCredits + s.refundCredits,
            137
        );
    }
});

test("rejects invalid inputs", () => {
    assert.throws(() =>
        computeTimeSettlement({
            depositCredits: -1,
            activeSeconds: 60,
            ratePerMinuteCredits: 2,
            serviceFeeBps: 300
        })
    );
    assert.throws(() =>
        computeTimeSettlement({
            depositCredits: 50,
            activeSeconds: 60,
            ratePerMinuteCredits: 1.5, // must be integer
            serviceFeeBps: 300
        })
    );
    assert.throws(() =>
        computeTimeSettlement({
            depositCredits: 50,
            activeSeconds: 60,
            ratePerMinuteCredits: 2,
            serviceFeeBps: 20000 // > 10000
        })
    );
});

// ============================ activeSecondsBetween ============================

test("activeSecondsBetween computes elapsed seconds", () => {
    const start = "2026-01-01T00:00:00.000Z";
    const end = "2026-01-01T00:02:30.000Z";
    assert.equal(activeSecondsBetween(start, end), 150);
});

test("activeSecondsBetween guards missing/negative ranges", () => {
    assert.equal(activeSecondsBetween(null, "2026-01-01T00:00:00Z"), 0);
    assert.equal(
        activeSecondsBetween("2026-01-01T00:05:00Z", "2026-01-01T00:00:00Z"),
        0
    );
});
