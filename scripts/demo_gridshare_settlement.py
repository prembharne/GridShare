"""
Practical Live Demo Script for GridShare Energy Settlement System.
Simulates IoT telemetry polling from a Wipro 16A Smart Plug, accumulates kWh,
and invokes the Soroban smart contract on Stellar Testnet!
"""

import asyncio
import os
import sys
import time

# Add src/telemetry to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src", "telemetry")))

from gridshare_telemetry import GridShareTelemetry, calculate_kwh_delta
from soroban_bridge import SorobanSettlementBridge


async def main():
    print("=" * 65)
    print("GRIDSHARE DECENTRALIZED ENERGY SETTLEMENT DEMO")
    print("=" * 65)

    # -------------------------------------------------------------
    # Step 1: Initialize Soroban Settlement Bridge
    # -------------------------------------------------------------
    rpc_url = "https://soroban-testnet.stellar.org"
    network_passphrase = "Test SDF Network ; September 2015"
    contract_id = "CD65ABMSSFQNJ6KP2BJCJ344NGZOE5FSV3OSCDW4OXLTPQAY3XDBTQQR"
    secret_key = "SDWAMBMHF66ZMK7ZO65N6SPBOOLHJ2DEUEBIRQAZPMTB2GQCSDUYMC2H"

    print("\n[Bridge] Initializing Soroban Bridge...")
    bridge = SorobanSettlementBridge(
        rpc_url=rpc_url,
        network_passphrase=network_passphrase,
        contract_id=contract_id,
        secret_key=secret_key,
    )
    bridge.start_worker()

    # -------------------------------------------------------------
    # Step 2: Initialize IoT Telemetry Accumulator
    # -------------------------------------------------------------
    state_file = "demo_telemetry_state.json"
    print(f"[Telemetry] Initializing Telemetry Accumulator ({state_file})...")
    
    # Clean up old state file for fresh demo
    if os.path.exists(state_file):
        os.remove(state_file)

    telemetry = GridShareTelemetry(
        device_id="DEMO_WIPRO_16A_PLUG",
        ip="127.0.0.1",
        local_key="0000000000000000",
        state_file=state_file,
    )

    # -------------------------------------------------------------
    # Step 3: Simulate 5 Polling Ticks at 3600W (16A EV Fast Charge)
    # -------------------------------------------------------------
    print("\n[IoT Plug] Simulating EV Charging Session at 3600 W (230 V, 15.6 A)...")
    start_ts = time.time()
    
    for tick in range(1, 6):
        await asyncio.sleep(1.0)
        current_ts = start_ts + (tick * 10)  # Simulate 10 seconds per tick
        
        # Process sample: 3600W for 10 seconds = 0.01 kWh per tick
        cumulative_kwh = telemetry._process_sample(power_watts=3600.0, timestamp=current_ts)
        telemetry.state.save()

        print(f"  -> Tick #{tick}: Instant Power = 3600 W | Cumulative = {cumulative_kwh:.4f} kWh")

    total_kwh_int = int(round(telemetry.state.cumulative_kwh * 100))  # Scale to whole units
    print(f"\n[Telemetry] Total accumulated kWh payload for settlement: {total_kwh_int} units")

    # -------------------------------------------------------------
    # Step 4: Enqueue On-Chain Settlement (Non-blocking)
    # -------------------------------------------------------------
    meter_id = "WIPRO_16A_DEMO_01"
    timestamp_epoch = int(time.time())

    print(f"\n[Bridge] Enqueuing non-blocking Soroban settlement task for {meter_id}...")
    await bridge.enqueue_settlement(
        meter_id=meter_id,
        kwh_consumed=total_kwh_int,
        timestamp=timestamp_epoch,
    )
    print("  [OK] Task enqueued in sub-millisecond! (Telemetry loop not blocked)")

    # -------------------------------------------------------------
    # Step 5: Wait for Soroban Worker to Confirm On-Chain Settlement
    # -------------------------------------------------------------
    print("\n[Soroban Network] Waiting for testnet ledger confirmation...")
    await bridge.queue.join()  # Wait until worker finishes processing
    
    print("\n[State Check] Verifying local state file content...")
    with open(state_file, "r") as f:
        print(f.read())

    await bridge.stop_worker()
    print("\n" + "=" * 65)
    print("PRACTICAL TEST COMPLETE: Telemetry integrated & settled on-chain!")
    print("=" * 65)


if __name__ == "__main__":
    asyncio.run(main())
