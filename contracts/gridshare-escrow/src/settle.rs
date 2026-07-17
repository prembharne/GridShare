//! On-chain settlement math. This is a *trustless* port of the backend's
//! `computeSettlement`. The relayer submits raw telemetry; the contract
//! recomputes the split and asserts conservation. A relayer that tries to
//! steal (e.g. over-allocate to the treasury) is rejected by the
//! conservation check below.
//!
//! Formula (identical to the JS reference; all values are whole credits):
//!   raw_amount_due = energy_wh * price_per_kwh_raw / 1000
//!   amount_due     = min(deposit, raw_amount_due)
//!   service_fee    = amount_due * service_fee_bps / 10000   (the 2-3% cut)
//!   host_share     = amount_due - service_fee
//!   refund         = deposit - amount_due
//!
//! Invariant that always holds by construction and is asserted defensively:
//!   host_share + service_fee + refund == deposit

use soroban_sdk::Env;

use crate::errors::EscrowError;
use crate::types::SettlementResult;

#[derive(Clone, Copy, Debug)]
pub struct SettlementTerms {
    pub deposit: i128,
    pub energy_wh: i128,
    pub price_per_kwh_raw: i128,
    pub service_fee_bps: i128,
}

/// Compute and validate the settlement. Reverts on overflow, bad fee range,
/// or conservation failure.
pub fn compute(env: &Env, t: SettlementTerms) -> SettlementResult {
    if t.deposit <= 0 {
        soroban_sdk::panic_with_error!(env, EscrowError::InvalidAmount);
    }
    if t.energy_wh < 0 {
        soroban_sdk::panic_with_error!(env, EscrowError::InvalidAmount);
    }
    if t.price_per_kwh_raw < 0 {
        soroban_sdk::panic_with_error!(env, EscrowError::InvalidAmount);
    }
    if !(0..=10_000).contains(&t.service_fee_bps) {
        soroban_sdk::panic_with_error!(env, EscrowError::InvalidFeeBps);
    }

    // overflow-checks = true makes `*` panic on overflow, but we guard the
    // division-by-zero (price) explicitly and use checked math for clarity.
    let raw_amount_due = t
        .energy_wh
        .checked_mul(t.price_per_kwh_raw)
        .map(|v| v / 1000i128)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));

    let amount_due = raw_amount_due.min(t.deposit);

    let service_fee = amount_due
        .checked_mul(t.service_fee_bps)
        .map(|v| v / 10_000i128)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));

    let host_share = amount_due
        .checked_sub(service_fee)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));

    let refund = t
        .deposit
        .checked_sub(amount_due)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));

    if host_share < 0 || service_fee < 0 || refund < 0 {
        soroban_sdk::panic_with_error!(env, EscrowError::NegativeRefund);
    }
    if host_share + service_fee + refund != t.deposit {
        soroban_sdk::panic_with_error!(env, EscrowError::ConservationViolated);
    }

    SettlementResult {
        energy_wh: t.energy_wh,
        price_per_kwh_raw: t.price_per_kwh_raw,
        service_fee_bps: t.service_fee_bps,
        amount_due,
        service_fee,
        host_share,
        refund,
    }
}
