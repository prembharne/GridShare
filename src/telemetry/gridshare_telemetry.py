"""
Module 1: IoT Telemetry & Accumulator (gridshare_telemetry.py)
Polls Wipro 16A Smart Plug locally via tinytuya over LAN.
Parses DPs: DP 18 (Current mA), DP 19 (Power 0.1W), DP 20 (Voltage 0.1V).
Integrates instantaneous power (W) over elapsed time deltas to accumulate energy (kWh).
Persists state atomically to local JSON to handle restarts and power-cycles.
"""

import json
import os
import time
import logging
from typing import Dict, Any, Optional

try:
    import tinytuya
except ImportError:
    tinytuya = None

logger = logging.getLogger("gridshare.telemetry")


def parse_dps(dps: Dict[str, Any]) -> Dict[str, float]:
    """
    Parse raw Tuya Data Points into standard units.
    - DP 18: Current (mA -> A)
    - DP 19: Power (0.1W -> W)
    - DP 20: Voltage (0.1V -> V)
    """
    raw_current_ma = dps.get("18", 0) or 0
    raw_power_01w = dps.get("19", 0) or 0
    raw_voltage_01v = dps.get("20", 0) or 0

    return {
        "current_a": float(raw_current_ma) / 1000.0,
        "power_w": float(raw_power_01w) / 10.0,
        "voltage_v": float(raw_voltage_01v) / 10.0,
    }


def calculate_kwh_delta(power_watts: float, delta_seconds: float) -> float:
    """
    Integrate instantaneous power (Watts) over elapsed time (seconds) into kWh.
    kWh = (Power_W * Delta_t_sec) / 3,600,000
    """
    if power_watts <= 0.0 or delta_seconds <= 0.0:
        return 0.0
    joules = power_watts * delta_seconds
    kwh = joules / 3_600_000.0
    return kwh


class TelemetryState:
    """
    Persistent state manager for local accumulated energy (kWh).
    Uses atomic temp file replacement to prevent corrupt JSON on abrupt shutdown.
    """

    def __init__(self, state_file: str = "telemetry_state.json"):
        self.state_file = state_file
        self.cumulative_kwh: float = 0.0
        self.last_updated_ts: float = 0.0
        self.total_samples: int = 0

    def load(self) -> bool:
        if not os.path.exists(self.state_file):
            return False
        try:
            with open(self.state_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                self.cumulative_kwh = float(data.get("cumulative_kwh", 0.0))
                self.last_updated_ts = float(data.get("last_updated_ts", 0.0))
                self.total_samples = int(data.get("total_samples", 0))
                logger.info(f"Loaded telemetry state: {self.cumulative_kwh:.4f} kWh")
                return True
        except Exception as e:
            logger.error(f"Failed to load telemetry state file {self.state_file}: {e}")
            return False

    def save(self) -> None:
        data = {
            "cumulative_kwh": self.cumulative_kwh,
            "last_updated_ts": self.last_updated_ts,
            "total_samples": self.total_samples,
        }
        tmp_file = f"{self.state_file}.tmp"
        try:
            with open(tmp_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
            os.replace(tmp_file, self.state_file)
        except Exception as e:
            logger.error(f"Failed to atomically save telemetry state: {e}")

    def update_energy(self, delta_kwh: float, timestamp: Optional[float] = None) -> None:
        self.cumulative_kwh += delta_kwh
        self.last_updated_ts = timestamp or time.time()
        self.total_samples += 1


class GridShareTelemetry:
    """
    LAN Polling service & Energy Accumulator for Wipro 16A Smart Plugs.
    """

    def __init__(
        self,
        device_id: str,
        ip: str,
        local_key: str,
        state_file: str = "telemetry_state.json",
        version: float = 3.3,
    ):
        self.device_id = device_id
        self.ip = ip
        self.local_key = local_key
        self.version = version

        self.state = TelemetryState(state_file=state_file)
        self.state.load()

        self.last_sample_ts: Optional[float] = None
        self._device = None

        if tinytuya is not None:
            self._init_device()

    def _init_device(self) -> None:
        try:
            self._device = tinytuya.OutletDevice(
                dev_id=self.device_id,
                address=self.ip,
                local_key=self.local_key,
                version=self.version,
            )
            self._device.set_socketRetryLimit(2)
            self._device.set_socketTimeout(3)
        except Exception as e:
            logger.error(f"Failed to initialize tinytuya device: {e}")

    def _process_sample(self, power_watts: float, timestamp: float) -> float:
        """Process instantaneous sample, integrate over time delta, and accumulate kWh."""
        if self.last_sample_ts is not None and timestamp > self.last_sample_ts:
            delta_t = timestamp - self.last_sample_ts
            delta_kwh = calculate_kwh_delta(power_watts, delta_t)
            self.state.update_energy(delta_kwh, timestamp)
        else:
            self.state.last_updated_ts = timestamp

        self.last_sample_ts = timestamp
        return self.state.cumulative_kwh

    def poll_once(self) -> Optional[Dict[str, float]]:
        """Poll device over LAN, parse DPs, update accumulator, and persist state."""
        if self._device is None:
            logger.warning("Tinytuya device not initialized.")
            return None

        try:
            data = self._device.status()
            if not data or "dps" not in data:
                logger.warning("No DPS returned from plug.")
                return None

            dps = data["dps"]
            parsed = parse_dps(dps)
            now = time.time()

            cumulative_kwh = self._process_sample(parsed["power_w"], now)
            self.state.save()

            parsed["cumulative_kwh"] = cumulative_kwh
            parsed["timestamp"] = now
            return parsed

        except Exception as e:
            logger.error(f"Error polling Tuya LAN device: {e}")
            return None
