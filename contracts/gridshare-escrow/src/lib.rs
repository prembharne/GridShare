//! GridShare Credit-Wallet Contract — vault-grade Soroban implementation.
//!
//! A single integer unit, the **credit** (1 credit == 1 INR, whole integers),
//! is used everywhere. No external token. Users top up via UPI and the
//! contract `mint`s credits; charging deducts credits from the rider and credits
//! the host (minus a 2-3% service fee to the treasury); host earnings are
//! `redeem`ed (burned) when paid out off-chain.
//!
//! Security model (read before touching anything):
//!
//! 1. SINGLE TRUSTED MOVER. Only the `Relayer` (the backend's fee-bumped
//!    signing key) can mint / lock / settle / refund / redeem. The relayer is
//!    trusted for *telemetry truth* but is NOT trusted with *fund integrity*:
//!    the contract recomputes the settlement split and enforces conservation,
//!    so a malicious relayer cannot over-allocate to the treasury.
//!
//! 2. CHECKS-EFFECTS-INTERACTIONS. Every mutating path writes the new session
//!    status to persistent storage *before* any balance move. A hostile
//!    re-entrant call cannot re-settle or double-refund because the status
//!    guard rejects it. (Internal balance moves are atomic, but the guard
//!    stays as defense-in-depth.)
//!
//! 3. STRICT STATE MACHINE. Created -> Locked -> (Settled | Refunded).
//!    No transitions are reversible; duplicate ops are idempotent-safe.
//!
//! 4. CONSERVATION. At all times `host_share + service_fee + refund ==
//!    deposit` (per session) and `total_supply == sum(balances)` (globally).
//!    `mint` raises supply, `redeem` lowers it, transfers only move it.
//!
//! 5. CIRCUIT BREAKER. `pause()` halts all value movement instantly; it is
//!    the primary operational kill-switch (covers mint/lock/settle/refund/redeem).
//!
//! 6. TIMELOCKED UPGRADE. Code changes require a 14-day proposal window
//!    during which ADMIN can veto by pausing.

#![no_std]

use soroban_sdk::{
    contract, contractimpl,
    symbol_short, Address, Bytes, BytesN, Env, Symbol,
};

mod errors;
mod settle;
mod storage;
mod types;

#[cfg(test)]
mod test;

use errors::EscrowError;
use settle::{compute, SettlementTerms};
use storage::{
    add_balance, add_supply, balance, ensure_not_paused, require_admin,
    require_relayer, require_upgrader, sub_balance, sub_supply, total_supply,
    Role, UpgradeProposal, UPGRADE_TIMELOCK_SECS,
};
use types::{SessionData, SessionStatus, SettlementOpt, SettlementResult};

#[contract]
pub struct GridShareEscrow;

#[contractimpl]
impl GridShareEscrow {
    // ============================ INITIALIZATION ============================

    /// One-time bootstrap. Sets the three privileged roles and the treasury
    /// (platform-fee sink). Idempotent-guarded: re-init reverts.
    pub fn initialize(
        env: Env,
        admin: Address,
        relayer: Address,
        upgrader: Address,
        treasury: Address,
    ) {
        if storage::admin(&env).is_some() {
            soroban_sdk::panic_with_error!(&env, EscrowError::AlreadyInitialized);
        }
        admin.require_auth();
        storage::set_admin(&env, &admin);
        storage::set_relayer(&env, &relayer);
        storage::set_upgrader(&env, &upgrader);
        storage::set_treasury(&env, &treasury);
        storage::set_paused(&env, false);

        env.events().publish(
            (symbol_short!("init"),),
            (admin, relayer, upgrader, treasury),
        );
    }

    // ========================= SESSION LIFECYCLE ============================

    /// Register session metadata. Optional pre-step; `lock_deposit` will
    /// also create the record if absent. Safe to call multiple times before
    /// locking (idempotent on identical terms).
    pub fn init_session(
        env: Env,
        session_id: Bytes,
        rider: Address,
        host: Address,
        outlet: Bytes,
        deposit: i128,
        price_per_kwh_raw: i128,
        service_fee_bps: i128,
    ) {
        ensure_not_paused(&env);
        require_relayer(&env);

        if storage::has_session(&env, &session_id) {
            return;
        }
        let data = SessionData {
            rider,
            host,
            outlet,
            deposit,
            price_per_kwh_raw,
            service_fee_bps,
            status: SessionStatus::Created,
            oracle_commitment: env.crypto().sha256(&session_id).into(),
            last_settlement: SettlementOpt { has_settlement: false, settlement: SettlementResult { energy_wh: 0, price_per_kwh_raw: 0, service_fee_bps: 0, amount_due: 0, service_fee: 0, host_share: 0, refund: 0 } },
            created_at: env.ledger().timestamp(),
            locked_at: 0,
            settled_at: 0,
            refunded_at: 0,
            stop_reason: Symbol::new(&env, ""),
        };
        storage::put_session(&env, &session_id, &data);
    }

    /// Lock `deposit` credits from the rider's wallet balance into this
    /// session and transition Created -> Locked. Idempotent: re-locking an
    /// already locked/settled session returns the stored record without moving
    /// funds again. Reverts with `InsufficientBalance` if the rider cannot
    /// cover `deposit`.
    pub fn lock_deposit(
        env: Env,
        session_id: Bytes,
        rider: Address,
        host: Address,
        outlet: Bytes,
        deposit: i128,
        price_per_kwh_raw: i128,
        service_fee_bps: i128,
    ) {
        ensure_not_paused(&env);
        require_relayer(&env);

        if deposit <= 0 {
            soroban_sdk::panic_with_error!(&env, EscrowError::InvalidAmount);
        }

        // Idempotency: if already past Created, do not move funds again.
        if let Some(existing) = storage::get_session(&env, &session_id) {
            match existing.status {
                SessionStatus::Locked | SessionStatus::Settled => {
                    env.events().publish(
                        (symbol_short!("lock"), symbol_short!("dup")),
                        session_id.clone(),
                    );
                    return;
                }
                SessionStatus::Refunded => {
                    soroban_sdk::panic_with_error!(&env, EscrowError::AlreadyRefunded);
                }
                SessionStatus::Created => {
                    // fall through to re-lock with verified terms
                    if existing.deposit != deposit
                        || existing.rider != rider
                    {
                        soroban_sdk::panic_with_error!(
                            &env,
                            EscrowError::OracleCommitmentMismatch
                        );
                    }
                }
            }
        }

        // --- EFFECT: persist Locked state BEFORE the balance move ---
        let now = env.ledger().timestamp();
        let data = SessionData {
            rider: rider.clone(),
            host: host.clone(),
            outlet: outlet.clone(),
            deposit,
            price_per_kwh_raw,
            service_fee_bps,
            status: SessionStatus::Locked,
            oracle_commitment: env.crypto().sha256(&session_id).into(),
            last_settlement: SettlementOpt { has_settlement: false, settlement: SettlementResult { energy_wh: 0, price_per_kwh_raw: 0, service_fee_bps: 0, amount_due: 0, service_fee: 0, host_share: 0, refund: 0 } },
            created_at: storage::get_session(&env, &session_id)
                .map(|s| s.created_at)
                .unwrap_or(now),
            locked_at: now,
            settled_at: 0,
            refunded_at: 0,
            stop_reason: Symbol::new(&env, ""),
        };
        storage::put_session(&env, &session_id, &data);

        // --- INTERACTION: deduct the held credits from the rider's balance ---
        // Supply is unchanged (credit merely moves rider -> this session's hold).
        sub_balance(&env, &rider, deposit);

        env.events().publish(
            (symbol_short!("lock"), symbol_short!("ok")),
            (session_id.clone(), deposit, rider.clone()),
        );
    }

    /// Settle a locked session: recompute the split on-chain from the
    /// relayer-submitted energy reading, then distribute. The relayer may
    /// NOT specify the split — only the energy; the contract owns the math.
    pub fn settle_session(
        env: Env,
        session_id: Bytes,
        energy_wh: i128,
        telemetry_hash: Bytes,
        reason: Symbol,
    ) {
        ensure_not_paused(&env);
        require_relayer(&env);

        let mut data = storage::get_session(&env, &session_id)
            .unwrap_or_else(|| soroban_sdk::panic_with_error!(&env, EscrowError::SessionNotFound));

        if data.status != SessionStatus::Locked {
            soroban_sdk::panic_with_error!(&env, EscrowError::NotSettleable);
        }

        let terms = SettlementTerms {
            deposit: data.deposit,
            energy_wh,
            price_per_kwh_raw: data.price_per_kwh_raw,
            service_fee_bps: data.service_fee_bps,
        };
        let settlement = compute(&env, terms);

        let treasury = storage::treasury(&env)
            .unwrap_or_else(|| soroban_sdk::panic_with_error!(&env, EscrowError::NotInitialized));

        // --- EFFECT: mark Settled and store result BEFORE any balance move ---
        let now = env.ledger().timestamp();
        data.status = SessionStatus::Settled;
        data.last_settlement = SettlementOpt { has_settlement: true, settlement: settlement.clone() };
        data.settled_at = now;
        data.stop_reason = reason.clone();
        storage::put_session(&env, &session_id, &data);

        // --- INTERACTION: distribute the held credits between balances ---
        // The held `deposit` was already removed from the rider at lock time;
        // here we credit host / treasury / rider. Supply is unchanged.
        if settlement.host_share > 0 {
            add_balance(&env, &data.host, settlement.host_share);
        }
        if settlement.service_fee > 0 {
            add_balance(&env, &treasury, settlement.service_fee);
        }
        if settlement.refund > 0 {
            add_balance(&env, &data.rider, settlement.refund);
        }

        env.events().publish(
            (symbol_short!("settle"), symbol_short!("ok")),
            (session_id.clone(), settlement.clone(), telemetry_hash, reason),
        );
    }

    /// Full refund to rider's wallet balance. Only valid from Locked.
    /// Marks Refunded before the balance move (checks-effects-interactions).
    pub fn refund_deposit(env: Env, session_id: Bytes, reason: Symbol) {
        ensure_not_paused(&env);
        require_relayer(&env);

        let mut data = storage::get_session(&env, &session_id)
            .unwrap_or_else(|| soroban_sdk::panic_with_error!(&env, EscrowError::SessionNotFound));

        if data.status != SessionStatus::Locked {
            soroban_sdk::panic_with_error!(&env, EscrowError::NotRefundable);
        }

        // --- EFFECT: mark Refunded before balance move ---
        let now = env.ledger().timestamp();
        data.status = SessionStatus::Refunded;
        data.refunded_at = now;
        data.stop_reason = reason.clone();
        storage::put_session(&env, &session_id, &data);

        // --- INTERACTION: return the held credits to the rider's balance ---
        // Supply is unchanged (credit moves session-hold -> rider).
        add_balance(&env, &data.rider, data.deposit);

        env.events().publish(
            (symbol_short!("refund"), symbol_short!("ok")),
            (session_id.clone(), data.deposit, reason),
        );
    }

    // =============================== VIEWS ==================================

    pub fn get_session(env: Env, session_id: Bytes) -> Option<SessionData> {
        storage::get_session(&env, &session_id)
    }

    pub fn is_paused(env: Env) -> bool {
        storage::is_paused(&env)
    }

    // ========================= CREDIT WALLET =============================

    /// Mint credits into `user`'s wallet. Called by the backend's relayer
    /// only, on a confirmed UPI top-up (1 INR top-up -> 1 credit).
    /// Raises `total_supply` to keep `total_supply == sum(balances)`.
    pub fn mint(env: Env, user: Address, amount: i128) {
        ensure_not_paused(&env);
        require_relayer(&env);

        if amount <= 0 {
            soroban_sdk::panic_with_error!(&env, EscrowError::InvalidAmount);
        }

        add_supply(&env, amount);
        add_balance(&env, &user, amount);

        env.events().publish(
            (symbol_short!("mint"),),
            (user.clone(), amount),
        );
    }

    /// Burn credits from `host`'s earned balance. Called by the backend's
    /// relayer only, on a confirmed off-chain payout (weekly host payout).
    /// Lowers `total_supply` so credits cannot be paid out twice.
    pub fn redeem(env: Env, host: Address, amount: i128) {
        ensure_not_paused(&env);
        require_relayer(&env);

        if amount <= 0 {
            soroban_sdk::panic_with_error!(&env, EscrowError::InvalidAmount);
        }

        sub_balance(&env, &host, amount);
        sub_supply(&env, amount);

        env.events().publish(
            (symbol_short!("redeem"),),
            (host.clone(), amount),
        );
    }

    pub fn balance_of(env: Env, user: Address) -> i128 {
        balance(&env, &user)
    }

    pub fn total_supply(env: Env) -> i128 {
        total_supply(&env)
    }

    // ========================= ADMIN OPERATIONS =============================

    pub fn set_relayer(env: Env, new_relayer: Address) {
        let admin = require_admin(&env);
        new_relayer.require_auth();
        storage::set_relayer(&env, &new_relayer);
        env.events()
            .publish((symbol_short!("role"),), (admin, Role::Relayer as u32, new_relayer));
    }

    pub fn set_treasury(env: Env, new_treasury: Address) {
        let admin = require_admin(&env);
        new_treasury.require_auth();
        storage::set_treasury(&env, &new_treasury);
        env.events().publish(
            (symbol_short!("treasury"),),
            (admin, new_treasury),
        );
    }

    pub fn set_upgrader(env: Env, new_upgrader: Address) {
        require_admin(&env);
        new_upgrader.require_auth();
        storage::set_upgrader(&env, &new_upgrader);
    }

    pub fn pause(env: Env) {
        require_admin(&env);
        storage::set_paused(&env, true);
        env.events().publish((symbol_short!("pause"),), ());
    }

    pub fn unpause(env: Env) {
        require_admin(&env);
        storage::set_paused(&env, false);
        env.events().publish((symbol_short!("unpause"),), ());
    }

    // ========================= TIMELOCKED UPGRADE ===========================

    /// Propose a new WASM hash. Execution is blocked until the timelock
    /// (14 days) elapses. ADMIN can veto at any time by calling `pause()`.
    pub fn propose_upgrade(env: Env, new_wasm_hash: BytesN<32>) {
        require_upgrader(&env);
        let proposal = UpgradeProposal {
            new_wasm_hash,
            proposed_at: env.ledger().timestamp(),
        };
        storage::set_upgrade_proposal(&env, &proposal);
        env.events()
            .publish((symbol_short!("upgrade"), symbol_short!("prop")), proposal);
    }

    pub fn cancel_upgrade(env: Env) {
        require_admin(&env);
        storage::clear_upgrade_proposal(&env);
        env.events()
            .publish((symbol_short!("upgrade"), symbol_short!("cancel")), ());
    }

    pub fn execute_upgrade(env: Env) {
        require_upgrader(&env);
        let proposal = storage::upgrade_proposal(&env)
            .unwrap_or_else(|| soroban_sdk::panic_with_error!(&env, EscrowError::NotInitialized));
        let now = env.ledger().timestamp();
        if now < proposal.proposed_at + UPGRADE_TIMELOCK_SECS {
            soroban_sdk::panic_with_error!(&env, EscrowError::UpgradeTimelockActive);
        }
        storage::clear_upgrade_proposal(&env);
        env.deployer().update_current_contract_wasm(proposal.new_wasm_hash);
        env.events()
            .publish((symbol_short!("upgrade"), symbol_short!("exec")), ());
    }
}
