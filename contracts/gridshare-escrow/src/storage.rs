//! Storage layout, role management, and the emergency pause switch.
//!
//! Security notes:
//! - Roles are written once at init and only mutatable by ADMIN.
//! - `pause()` is a circuit breaker: when set, every mutating entrypoint
//!   reverts. This is the single most important operational safeguard for a
//!   contract holding other people's money.
//! - The upgrade timelock prevents a stolen upgrade key from instantly
//!   swapping the code; there is a mandatory delay during which ADMIN can
//!   veto by pausing.

use soroban_sdk::{contracttype, Address, Bytes, BytesN, Env, Symbol};

use crate::errors::EscrowError;
use crate::types::SessionData;

#[contracttype]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
pub enum Role {
    Admin = 0,
    Relayer = 1,
    Upgrader = 2,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UpgradeProposal {
    pub new_wasm_hash: BytesN<32>,
    pub proposed_at: u64,
}

const KEY_ADMIN: &str = "admin";
const KEY_RELAYER: &str = "relayer";
const KEY_UPGRADER: &str = "upgrader";
const KEY_TREASURY: &str = "treasury";
const KEY_PAUSED: &str = "paused";
const KEY_UPGRADE: &str = "upgrade";
const KEY_SUPPLY: &str = "supply";

fn key_admin(env: &Env) -> Symbol {
    Symbol::new(env, KEY_ADMIN)
}
fn key_relayer(env: &Env) -> Symbol {
    Symbol::new(env, KEY_RELAYER)
}
fn key_upgrader(env: &Env) -> Symbol {
    Symbol::new(env, KEY_UPGRADER)
}
fn key_treasury(env: &Env) -> Symbol {
    Symbol::new(env, KEY_TREASURY)
}
fn key_paused(env: &Env) -> Symbol {
    Symbol::new(env, KEY_PAUSED)
}
fn key_upgrade(env: &Env) -> Symbol {
    Symbol::new(env, KEY_UPGRADE)
}
fn key_supply(env: &Env) -> Symbol {
    Symbol::new(env, KEY_SUPPLY)
}

pub const UPGRADE_TIMELOCK_SECS: u64 = 1_209_600; // 14 days

// ----------------------------- instance config -----------------------------

pub fn set_admin(env: &Env, addr: &Address) {
    env.storage().instance().set(&key_admin(env), addr);
}

pub fn admin(env: &Env) -> Option<Address> {
    env.storage().instance().get(&key_admin(env))
}

pub fn set_relayer(env: &Env, addr: &Address) {
    env.storage().instance().set(&key_relayer(env), addr);
}

pub fn relayer(env: &Env) -> Option<Address> {
    env.storage().instance().get(&key_relayer(env))
}

pub fn set_upgrader(env: &Env, addr: &Address) {
    env.storage().instance().set(&key_upgrader(env), addr);
}

pub fn upgrader(env: &Env) -> Option<Address> {
    env.storage().instance().get(&key_upgrader(env))
}

pub fn set_treasury(env: &Env, addr: &Address) {
    env.storage().instance().set(&key_treasury(env), addr);
}

pub fn treasury(env: &Env) -> Option<Address> {
    env.storage().instance().get(&key_treasury(env))
}

pub fn set_paused(env: &Env, paused: bool) {
    env.storage().instance().set(&key_paused(env), &paused);
}

pub fn is_paused(env: &Env) -> bool {
    env.storage().instance().get(&key_paused(env)).unwrap_or(false)
}

pub fn set_upgrade_proposal(env: &Env, proposal: &UpgradeProposal) {
    env.storage().instance().set(&key_upgrade(env), proposal);
}

pub fn upgrade_proposal(env: &Env) -> Option<UpgradeProposal> {
    env.storage().instance().get(&key_upgrade(env))
}

pub fn clear_upgrade_proposal(env: &Env) {
    env.storage().instance().remove(&key_upgrade(env));
}

// ------------------------------- auth helpers -------------------------------

/// Require ADMIN auth, then return the stored admin address. Reverts with
/// `UnauthorizedAdmin` if unset or if the caller is not the admin.
pub fn require_admin(env: &Env) -> Address {
    let a = admin(env).unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::NotInitialized));
    a.require_auth();
    a
}

/// Require RELAYER auth. The relayer is the only principal allowed to move
/// escrowed funds, because it is the backend's fee-bumped signing key.
pub fn require_relayer(env: &Env) -> Address {
    let r = relayer(env).unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::NotInitialized));
    r.require_auth();
    r
}

pub fn require_upgrader(env: &Env) -> Address {
    let u = upgrader(env).unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::NotInitialized));
    u.require_auth();
    u
}

/// Reverts if the contract is paused. Call at the top of every mutating
/// entrypoint.
pub fn ensure_not_paused(env: &Env) {
    if is_paused(env) {
        soroban_sdk::panic_with_error!(env, EscrowError::ContractPaused);
    }
}

// ------------------------------- session store ------------------------------

pub fn put_session(env: &Env, session_id: &Bytes, data: &SessionData) {
    let key = (Symbol::new(env, "sess"), session_id.clone());
    env.storage().persistent().set(&key, data);
}

pub fn get_session(env: &Env, session_id: &Bytes) -> Option<SessionData> {
    let key = (Symbol::new(env, "sess"), session_id.clone());
    env.storage().persistent().get(&key)
}

pub fn has_session(env: &Env, session_id: &Bytes) -> bool {
    let key = (Symbol::new(env, "sess"), session_id.clone());
    env.storage().persistent().has(&key)
}

// ------------------------------- credit ledger ------------------------------
//
// The credit wallet. `balance(user)` is the spendable/earned credit balance for
// any address (riders spend, hosts earn, treasury accrues the service fee).
// `total_supply` is a conservation counter: it must always equal the sum of all
// balances. `mint` increases both; `redeem` decreases both; internal transfers
// (lock/settle/refund) move credits between balances and leave supply unchanged.

fn balance_key(env: &Env, user: &Address) -> (Symbol, Address) {
    (Symbol::new(env, "bal"), user.clone())
}

pub fn balance(env: &Env, user: &Address) -> i128 {
    env.storage()
        .persistent()
        .get(&balance_key(env, user))
        .unwrap_or(0)
}

fn set_balance(env: &Env, user: &Address, amount: i128) {
    let key = balance_key(env, user);
    if amount == 0 {
        env.storage().persistent().remove(&key);
    } else {
        env.storage().persistent().set(&key, &amount);
    }
}

/// Add `amount` (may be positive) to a user's balance. Reverts on overflow.
pub fn add_balance(env: &Env, user: &Address, amount: i128) {
    let current = balance(env, user);
    let next = current
        .checked_add(amount)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));
    set_balance(env, user, next);
}

/// Subtract `amount` from a user's balance. Reverts with `InsufficientBalance`
/// if the balance would go negative.
pub fn sub_balance(env: &Env, user: &Address, amount: i128) {
    let current = balance(env, user);
    if current < amount {
        soroban_sdk::panic_with_error!(env, EscrowError::InsufficientBalance);
    }
    let next = current
        .checked_sub(amount)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));
    set_balance(env, user, next);
}

pub fn total_supply(env: &Env) -> i128 {
    env.storage().instance().get(&key_supply(env)).unwrap_or(0)
}

fn set_total_supply(env: &Env, amount: i128) {
    env.storage().instance().set(&key_supply(env), &amount);
}

/// Increase total supply (on mint). Reverts on overflow.
pub fn add_supply(env: &Env, amount: i128) {
    let next = total_supply(env)
        .checked_add(amount)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));
    set_total_supply(env, next);
}

/// Decrease total supply (on redeem/burn). Reverts on underflow.
pub fn sub_supply(env: &Env, amount: i128) {
    let current = total_supply(env);
    if current < amount {
        soroban_sdk::panic_with_error!(env, EscrowError::InsufficientBalance);
    }
    let next = current
        .checked_sub(amount)
        .unwrap_or_else(|| soroban_sdk::panic_with_error!(env, EscrowError::MathOverflow));
    set_total_supply(env, next);
}
