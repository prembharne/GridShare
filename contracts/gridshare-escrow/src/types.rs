//! On-chain data structures for the GridShare credit-wallet contract.
//!
//! There is no external token. A single integer unit — the **credit** — is used
//! everywhere, where 1 credit == 1 INR (whole integers only). Users top up via
//! UPI and the contract `mint`s credits; charging deducts credits from the rider
//! and credits the host (minus a 2-3% service fee to the treasury). Host earnings
//! are `redeem`ed (burned) when paid out off-chain.
//!
//! The contract only ever trusts integer conservation:
//!   host_share + service_fee + refund == deposit
//!   total_supply == sum(balances)

use soroban_sdk::{contracttype, Address, Bytes, Symbol};

/// Strict state machine. `Created` is the only initial state; transitions
/// may only advance forward and may never revisit a prior state.
#[contracttype]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum SessionStatus {
    Created = 0,
    Locked = 1,
    Settled = 2,
    Refunded = 3,
}

/// Result of a settlement, recomputed *on-chain* from telemetry so a
/// compromised relayer cannot lie about the fee split.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SettlementResult {
    pub energy_wh: i128,             // cumulative energy delivered (Wh)
    pub price_per_kwh_raw: i128,    // agreed price term (credits per 1000 Wh)
    pub service_fee_bps: i128,      // agreed service fee in basis points (0..10000)
    pub amount_due: i128,           // credits owed for energy consumed
    pub service_fee: i128,          // credits to treasury
    pub host_share: i128,           // credits to host
    pub refund: i128,               // credits back to rider
}

/// Wrapper to work around soroban-sdk 21.x `Option<contracttype>` test-build bug.
/// Use `has_settlement` flag instead of Option.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SettlementOpt {
    pub has_settlement: bool,
    pub settlement: SettlementResult,
}

/// Full session record persisted per session.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SessionData {
    pub rider: Address,             // whose wallet balance is locked/refunded
    pub host: Address,              // whose earned-credit balance is paid
    pub outlet: Bytes,              // opaque outlet id (backend format)
    pub deposit: i128,              // total credits held for this session
    pub price_per_kwh_raw: i128,    // agreed price term (credits per 1000 Wh)
    pub service_fee_bps: i128,      // agreed service fee (0..10000)
    pub status: SessionStatus,
    pub oracle_commitment: Bytes,   // sha256 of agreed terms; bound at lock
    pub last_settlement: SettlementOpt,
    pub created_at: u64,
    pub locked_at: u64,
    pub settled_at: u64,
    pub refunded_at: u64,
    pub stop_reason: Symbol,        // last stop reason
}

/// Reason codes mirrored from the backend's `stopKind` / safety engine so
/// off-chain tooling can render the same labels.
#[allow(dead_code)]
pub mod reasons {
    use soroban_sdk::symbol_short;

    pub const USER_STOP: soroban_sdk::Symbol = symbol_short!("user");
    pub const AUTO_THRESHOLD: soroban_sdk::Symbol = symbol_short!("auto");
    pub const SAFETY_TRIP: soroban_sdk::Symbol = symbol_short!("safety");
    pub const ACTIVATION_FAILED: soroban_sdk::Symbol = symbol_short!("actfail");
}
