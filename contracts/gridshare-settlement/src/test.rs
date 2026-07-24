#![cfg(test)]

use super::*;
use soroban_sdk::{Env, String};

#[test]
fn test_settle_energy_first_time() {
    let env = Env::default();
    let contract_id = env.register_contract(None, SettlementContract);
    let client = SettlementContractClient::new(&env, &contract_id);

    let meter_id = String::from_str(&env, "WIPRO_16A_001");
    let record = client.settle_energy(&meter_id, &15, &1700000000);

    assert_eq!(record.total_kwh, 15);
    assert_eq!(record.last_timestamp, 1700000000);
    assert_eq!(record.settlement_count, 1);

    // Verify view function returns the same record
    let stored = client.get_meter(&meter_id).unwrap();
    assert_eq!(stored.total_kwh, 15);
    assert_eq!(stored.settlement_count, 1);
}

#[test]
fn test_settle_energy_accumulation() {
    let env = Env::default();
    let contract_id = env.register_contract(None, SettlementContract);
    let client = SettlementContractClient::new(&env, &contract_id);

    let meter_id = String::from_str(&env, "WIPRO_16A_002");

    client.settle_energy(&meter_id, &10, &1700000000);
    client.settle_energy(&meter_id, &25, &1700003600);
    let record3 = client.settle_energy(&meter_id, &5, &1700007200);

    assert_eq!(record3.total_kwh, 40); // 10 + 25 + 5 = 40 kWh
    assert_eq!(record3.last_timestamp, 1700007200);
    assert_eq!(record3.settlement_count, 3);
}
