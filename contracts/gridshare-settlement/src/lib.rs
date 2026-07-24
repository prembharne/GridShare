#![no_std]
use soroban_sdk::{contract, contractimpl, contracttype, symbol_short, Env, String};

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MeterRecord {
    pub total_kwh: u32,
    pub last_timestamp: u64,
    pub settlement_count: u32,
}

#[contracttype]
pub enum DataKey {
    Meter(String),
}

#[contract]
pub struct SettlementContract;

#[contractimpl]
impl SettlementContract {
    /// Record and settle cumulative kWh energy consumption for a given IoT meter_id.
    pub fn settle_energy(env: Env, meter_id: String, kwh_consumed: u32, timestamp: u64) -> MeterRecord {
        let key = DataKey::Meter(meter_id.clone());

        // Fetch existing record or initialize new meter record
        let mut record: MeterRecord = env
            .storage()
            .persistent()
            .get(&key)
            .unwrap_or(MeterRecord {
                total_kwh: 0,
                last_timestamp: 0,
                settlement_count: 0,
            });

        // Accumulate energy & update timestamp and count
        record.total_kwh = record.total_kwh.saturating_add(kwh_consumed);
        record.last_timestamp = timestamp;
        record.settlement_count = record.settlement_count.saturating_add(1);

        // Store updated state on-chain
        env.storage().persistent().set(&key, &record);

        // Emit settlement event log
        env.events().publish(
            (symbol_short!("settle"), meter_id),
            (kwh_consumed, record.total_kwh, timestamp),
        );

        record
    }

    /// View helper to retrieve on-chain record for a meter_id.
    pub fn get_meter(env: Env, meter_id: String) -> Option<MeterRecord> {
        let key = DataKey::Meter(meter_id);
        env.storage().persistent().get(&key)
    }
}

#[cfg(test)]
mod test;
