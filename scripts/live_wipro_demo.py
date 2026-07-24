"""
Production Live Demo Script for GridShare Energy Settlement System
Interfacing with Prem's Wipro 16A Smart Plug (d72c4dd24f074a08fdwvz4).

Integrates:
1. Live Tuya IoT Telemetry (Voltage, Current, Power)
2. kWh Numerical Accumulator & Atomic State Persistence
3. Stellar Soroban Smart Contract Settlement on Testnet
"""

import asyncio
import logging
import os
import sys
import time

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src", "telemetry")))

import tinytuya
from gridshare_telemetry import calculate_kwh_delta, TelemetryState
from soroban_bridge import SorobanSettlementBridge

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("gridshare.demo")


async def main():
    print("=" * 70)
    print("GRIDSHARE LIVE DEMO: WIPRO 16A SMART PLUG -> SOROBAN SMART CONTRACT")
    print("=" * 70)

    device_id = "d72c4dd24f074a08fdwvz4"
    client_id = "gkhvgvc5s88wxva7ehtn"
    client_secret = "0edb6c2eab14403abec539ce6250a164"
    local_key = "!m/bF91M&l|}P}}?"
    region = "in"

    # 1. Initialize Soroban Testnet Bridge
    rpc_url = "https://soroban-testnet.stellar.org"
    network_passphrase = "Test SDF Network ; September 2015"
    contract_id = "CD65ABMSSFQNJ6KP2BJCJ344NGZOE5FSV3OSCDW4OXLTPQAY3XDBTQQR"
    secret_key = "SDWAMBMHF66ZMK7ZO65N6SPBOOLHJ2DEUEBIRQAZPMTB2GQCSDUYMC2H"

    print("\n[1/3] Initializing Soroban Blockchain Bridge...")
    bridge = SorobanSettlementBridge(
        rpc_url=rpc_url,
        network_passphrase=network_passphrase,
        contract_id=contract_id,
        secret_key=secret_key,
    )
    bridge.start_worker()

    # 2. Initialize Telemetry Accumulator State
    state_file = "live_wipro_state.json"
    state = TelemetryState(state_file=state_file)
    state.load()
    print(f"[2/3] Loaded local state: {state.cumulative_kwh:.4f} kWh cumulative")

    # 3. Connect to Tuya Cloud API
    print(f"[3/3] Connecting to Tuya Cloud API (Device ID: {device_id})...")
    cloud = tinytuya.Cloud(
        apiRegion=region,
        apiKey=client_id,
        apiSecret=client_secret
    )

    print("\n" + "=" * 70)
    print("LIVE TELEMETRY POLLING RUNNING (Press Ctrl+C to stop)")
    print("=" * 70 + "\n")

    last_sample_ts = time.time()
    last_settled_units = 0

    try:
        while True:
            resp = cloud.getstatus(device_id)
            if resp and resp.get("success") and "result" in resp:
                dps_list = resp["result"]
                dp_map = {item["code"]: item["value"] for item in dps_list}
                
                # Parse DPs
                is_on = dp_map.get("switch_1", False)
                cur_voltage_01v = dp_map.get("cur_voltage", 0) or 0
                cur_current_ma = dp_map.get("cur_current", 0) or 0
                cur_power_01w = dp_map.get("cur_power", 0) or 0

                voltage_v = float(cur_voltage_01v) / 10.0
                current_a = float(cur_current_ma) / 1000.0
                power_w = float(cur_power_01w) / 10.0

                now = time.time()
                delta_t = now - last_sample_ts
                last_sample_ts = now

                # Accumulate energy
                delta_kwh = calculate_kwh_delta(power_w, delta_t)
                state.update_energy(delta_kwh, now)
                state.save()

                plug_state_str = "ON" if is_on else "OFF (Plug in load & turn on)"
                print(f"[Plug Status: {plug_state_str}] Voltage: {voltage_v:.1f} V | Current: {current_a:.2f} A | Power: {power_w:.1f} W | Accumulated: {state.cumulative_kwh:.4f} kWh")

                # Enqueue on-chain settlement when cumulative energy increases
                units = int(round(state.cumulative_kwh * 100))
                if units > last_settled_units:
                    print(f"  [Settlement] Enqueuing {units} units on Soroban Testnet...")
                    await bridge.enqueue_settlement(
                        meter_id=device_id,
                        kwh_consumed=units,
                        timestamp=int(now)
                    )
                    last_settled_units = units

            await asyncio.sleep(2.5)

    except KeyboardInterrupt:
        print("\nStopping poller...")
    finally:
        await bridge.stop_worker()
        print("\nDemo poller stopped cleanly.")


if __name__ == "__main__":
    asyncio.run(main())
