import { invariant } from "../core/errors.js";

/**
 * Compute settlement in whole credits.
 * All monetary values are whole credits (1 credit = 1 INR).
 * Service fee is a single 2-3% cut to treasury.
 *
 * Formula:
 *   raw_amount_due = energy_wh * price_per_kwh_credits / 1000
 *   amount_due     = min(deposit_credits, raw_amount_due)
 *   service_fee    = floor(amount_due * service_fee_bps / 10000)
 *   host_share     = amount_due - service_fee
 *   refund_credits = deposit_credits - amount_due
 *
 * Invariant: host_share + service_fee + refund_credits == deposit_credits
 */
export function computeSettlement({
  depositCredits,
  energyWh,
  pricePerKwhCredits,
  serviceFeeBps
}) {
  invariant(Number.isInteger(depositCredits) && depositCredits >= 0, "INVALID_DEPOSIT", "depositCredits must be a non-negative integer.");
  invariant(Number.isFinite(energyWh) && energyWh >= 0, "INVALID_ENERGY", "energyWh must be non-negative.");
  invariant(Number.isInteger(pricePerKwhCredits) && pricePerKwhCredits >= 0, "INVALID_PRICE", "pricePerKwhCredits must be a non-negative integer.");
  invariant(Number.isInteger(serviceFeeBps) && serviceFeeBps >= 0 && serviceFeeBps <= 10000, "INVALID_FEE", "serviceFeeBps must be between 0 and 10000.");

  const rawAmountDue = Math.round((energyWh * pricePerKwhCredits) / 1000);
  const amountDueCredits = Math.min(depositCredits, rawAmountDue);

  const serviceFeeCredits = Math.floor((amountDueCredits * serviceFeeBps) / 10000);
  const hostShareCredits = amountDueCredits - serviceFeeCredits;
  const refundCredits = depositCredits - amountDueCredits;

  // Conservation check (defensive, should always hold)
  if (hostShareCredits + serviceFeeCredits + refundCredits !== depositCredits) {
    throw new Error("Conservation violated in settlement math.");
  }

  return {
    energyWh,
    pricePerKwhCredits,
    serviceFeeBps,
    amountDueCredits,
    serviceFeeCredits,
    hostShareCredits,
    refundCredits
  };
}