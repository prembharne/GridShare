//! Contract error catalog.
//!
//! Errors are split by category so callers (and the backend's event bus)
//! can distinguish "bad input" from "auth failure" from "illegal state
//! transition". Numeric codes are stable on purpose — the TS relayer maps
//! them back to DomainError codes.

use soroban_sdk::contracterror;

#[contracterror]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum EscrowError {
    // ----- Access control (1000s) -----
    NotInitialized = 1001,
    UnauthorizedRelayer = 1002,
    UnauthorizedAdmin = 1003,
    UnauthorizedUpgrader = 1004,
    AlreadyInitialized = 1005,

    // ----- Input validation (2000s) -----
    InvalidAmount = 2001,
    InvalidFeeBps = 2002,
    InvalidAddress = 2003,
    InvalidSessionId = 2004,
    EmptyCommitment = 2005,

    // ----- State machine (3000s) -----
    SessionAlreadyExists = 3001,
    SessionNotFound = 3002,
    InvalidStateTransition = 3003,
    AlreadyLocked = 3004,
    AlreadySettled = 3005,
    AlreadyRefunded = 3006,
    NotLockable = 3007,
    NotSettleable = 3008,
    NotRefundable = 3009,

    // ----- Math / conservation (4000s) -----
    MathOverflow = 4001,
    ConservationViolated = 4002,
    AmountExceedsDeposit = 4003,
    NegativeRefund = 4004,

    // ----- Oracle / integrity (5000s) -----
    OracleCommitmentMismatch = 5001,
    TelemetryHashMismatch = 5002,

    // ----- Operational (6000s) -----
    ContractPaused = 6001,
    UpgradeTimelockActive = 6002,
    InsufficientBalance = 6003,
}
