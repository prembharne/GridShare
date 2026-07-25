import { invariant } from "../core/errors.js";

/**
 * Compute a TIME-based settlement in whole credits.
 *
 * Unlike settlement-math.js (which bills by energy consumed, Wh), this bills by
 * elapsed active minutes — the model GridShare uses for per-minute charging.
 * All monetary values are whole credits (1 credit = 1 INR).
 *
 * Formula:
 *   billedMinutes  = ceil(activeSeconds / 60)          // any partial minute rounds up
 *   rawAmountDue   = billedMinutes * ratePerMinuteCredits
 *   amountDue      = min(depositCredits, rawAmountDue)  // never exceed the locked deposit
 *   serviceFee     = floor(amountDue * serviceFeeBps / 10000)
 *   hostShare      = amountDue - serviceFee
 *   refund         = depositCredits - amountDue
 *
 * Invariant: hostShare + serviceFee + refund == depositCredits
 */
export function computeTimeSettlement({
    depositCredits,
    activeSeconds,
    ratePerMinuteCredits,
    serviceFeeBps
}) {
    invariant(
        Number.isInteger(depositCredits) && depositCredits >= 0,
        "INVALID_DEPOSIT",
        "depositCredits must be a non-negative integer."
    );
    invariant(
        Number.isFinite(activeSeconds) && activeSeconds >= 0,
        "INVALID_DURATION",
        "activeSeconds must be a finite non-negative number."
    );
    invariant(
        Number.isInteger(ratePerMinuteCredits) && ratePerMinuteCredits >= 0,
        "INVALID_RATE",
        "ratePerMinuteCredits must be a non-negative integer."
    );
    invariant(
        Number.isInteger(serviceFeeBps) && serviceFeeBps >= 0 && serviceFeeBps <= 10000,
        "INVALID_FEE",
        "serviceFeeBps must be between 0 and 10000."
    );

    const billedMinutes = Math.ceil(activeSeconds / 60);
    const rawAmountDue = billedMinutes * ratePerMinuteCredits;
    const amountDueCredits = Math.min(depositCredits, rawAmountDue);

    const serviceFeeCredits = Math.floor((amountDueCredits * serviceFeeBps) / 10000);
    const hostShareCredits = amountDueCredits - serviceFeeCredits;
    const refundCredits = depositCredits - amountDueCredits;

    // Conservation check (defensive, should always hold)
    if (hostShareCredits + serviceFeeCredits + refundCredits !== depositCredits) {
        throw new Error("Conservation violated in time settlement math.");
    }

    return {
        billedMinutes,
        activeSeconds,
        ratePerMinuteCredits,
        serviceFeeBps,
        amountDueCredits,
        serviceFeeCredits,
        hostShareCredits,
        refundCredits
    };
}

/**
 * Elapsed active seconds between two ISO timestamps (activeAt → stoppedAt/now).
 * Returns 0 if either is missing or the range is negative (clock skew guard).
 */
export function activeSecondsBetween(activeAt, stoppedAt) {
    if (!activeAt) return 0;
    const start = new Date(activeAt).getTime();
    const end = stoppedAt ? new Date(stoppedAt).getTime() : Date.now();
    if (!Number.isFinite(start) || !Number.isFinite(end)) return 0;
    return Math.max(0, Math.round((end - start) / 1000));
}
