"""
Live Hardware Polling & Soroban Settlement for Wipro 16A Smart Plug
Device ID: d72c4dd24f074a08fdwvz4
"""

import asyncio
import os
import sys
import time

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src", "telemetry")))

from gridshare_telemetry import GridShareTelemetry
from soroban_bridge import SorobanSettlementBridge


async def run_live_settlement(ip: str, local_key: str):
    device_id = "d72c4dd24f074a08fdwvz4"
    
    print("=" * 65)
    print(f"LIVE HARDWARE SETTLEMENT FOR PLUG {device_id}")
    print("=" * 65)

    # 1. Start Soroban Testnet Bridge
    bridge = SorobanSettlementBridge(
        rpc_url="https://soroban-testnet.stellar.org",
        network_passphrase="Test SDF Network ; September 2015",
        contract_id="CD65ABMSSFQNJ6KP2BJCJ344NGZOE5FSV3OSCDW4OXLTPQAY3XDBTQQR",
        secret_key="SDWAMBMHF66ZMK7ZO65N6SPBOOLHJ2DEUEBIRQAZPMTB2GQCSDUYMC2H",
    )
    bridge.start_worker()

    # 2. Connect to Wipro 16A Smart Plug over LAN
    telemetry = GridShareTelemetry(
        device_id=device_id,
        ip=ip,
        local_key=local_key,
        state_file="live_wipro_plug_state.json"
    )

    print(f"\n[LAN] Polling plug at IP {ip} every 2 seconds...")
    print("Plug in an appliance (e.g. EV charger) to see live power & on-chain settlement!\n")

    try:
        last_settled_units = 0
        while True:
            sample = telemetry.poll_once()
            if sample:
                voltage = sample['voltage_v']
                current = sample['current_a']
                power = sample['power_w']
                kwh = sample['cumulative_kwh']
                
                print(f"[Telemetry] {voltage:.1f} V | {current:.2f} A | {power:.1f} W | Total: {kwh:.4f} kWh")

                units = int(round(kwh * 100))
                if units > last_settled_units:
                    print(f"  [Settlement] New energy accumulated! Enqueuing {units} units on Soroban...")
                    await bridge.enqueue_settlement(
                        meter_id=device_id,
                        kwh_consumed=units,
                        timestamp=int(time.time())
                    )
                    last_settled_units = units

            await asyncio.sleep(2.0)

    except KeyboardInterrupt:
        print("\nStopping live hardware poller...")
    finally:
        await bridge.stop_worker()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python scripts/live_wipro_plug_settlement.py <PLUG_LOCAL_IP> <PLUG_LOCAL_KEY>")
        print("Example: python scripts/live_wipro_plug_settlement.py 192.168.1.150 a1b2c3d4e5f67890")
    else:
        asyncio.run(run_live_settlement(sys.argv[1], sys.argv[2]))
