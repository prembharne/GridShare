"""
Unit tests for Module 1: IoT Telemetry & Accumulator (gridshare_telemetry.py)
Tests DP mapping, numerical integration of power over time, state persistence, and recovery.
"""

import json
import os
import time
import pytest
from unittest.mock import MagicMock, patch

# Import telemetry module (will be implemented in src/telemetry/gridshare_telemetry.py)
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src", "telemetry")))

from gridshare_telemetry import (
    TelemetryState,
    GridShareTelemetry,
    parse_dps,
    calculate_kwh_delta,
)


class TestTelemetryDataPointParsing:
    """Test scaling and parsing of raw Tuya DP values."""

    def test_parse_dps_valid(self):
        # Raw DP 18 = Current in mA (16000 mA -> 16.0 A)
        # Raw DP 19 = Power in 0.1W units (35000 -> 3500.0 W)
        # Raw DP 20 = Voltage in 0.1V units (2300 -> 230.0 V)
        raw_dps = {
            "18": 16000,
            "19": 35000,
            "20": 2300,
        }
        parsed = parse_dps(raw_dps)
        assert parsed["current_a"] == pytest.approx(16.0)
        assert parsed["power_w"] == pytest.approx(3500.0)
        assert parsed["voltage_v"] == pytest.approx(230.0)

    def test_parse_dps_zero_and_missing(self):
        raw_dps = {"18": 0}
        parsed = parse_dps(raw_dps)
        assert parsed["current_a"] == 0.0
        assert parsed["power_w"] == 0.0
        assert parsed["voltage_v"] == 0.0


class TestEnergyAccumulatorIntegration:
    """Test mathematical integration of power over elapsed time deltas."""

    def test_calculate_kwh_delta(self):
        # 1000 Watts for 1 hour (3600 seconds) = 1.0 kWh
        kwh = calculate_kwh_delta(power_watts=1000.0, delta_seconds=3600.0)
        assert kwh == pytest.approx(1.0)

    def test_calculate_kwh_delta_short_interval(self):
        # 1000 Watts for 1 second = 1000 / 3,600,000 kWh
        kwh = calculate_kwh_delta(power_watts=1000.0, delta_seconds=1.0)
        assert kwh == pytest.approx(1.0 / 3600.0)

    def test_accumulator_integration_loop(self, tmp_path):
        state_file = str(tmp_path / "test_state.json")
        telemetry = GridShareTelemetry(
            device_id="test_dev_123",
            ip="192.168.1.100",
            local_key="0123456789abcdef",
            state_file=state_file,
        )

        assert telemetry.state.cumulative_kwh == 0.0

        # Simulate 10 seconds at 3600W
        now = time.time()
        telemetry._process_sample(power_watts=3600.0, timestamp=now)
        telemetry._process_sample(power_watts=3600.0, timestamp=now + 10.0)

        # 3600W * 10s = 36,000 Joules = 0.01 kWh
        assert telemetry.state.cumulative_kwh == pytest.approx(0.01)


class TestStatePersistenceAndRecovery:
    """Test local JSON state persistence and recovery across power cycles."""

    def test_state_save_and_load(self, tmp_path):
        state_file = str(tmp_path / "telemetry_state.json")

        state = TelemetryState(state_file=state_file)
        state.update_energy(0.45)
        state.save()

        assert os.path.exists(state_file)

        # Reload from disk
        loaded_state = TelemetryState(state_file=state_file)
        loaded_state.load()
        assert loaded_state.cumulative_kwh == pytest.approx(0.45)

    def test_power_cycle_resilience(self, tmp_path):
        state_file = str(tmp_path / "telemetry_state.json")

        # Session 1 before power cycle
        tel1 = GridShareTelemetry("dev_123", "127.0.0.1", "key", state_file=state_file)
        now = time.time()
        tel1._process_sample(power_watts=1800.0, timestamp=now)
        tel1._process_sample(power_watts=1800.0, timestamp=now + 3600.0) # 1.8 kWh
        tel1.state.save()

        # Session 2 after restart/power cycle
        tel2 = GridShareTelemetry("dev_123", "127.0.0.1", "key", state_file=state_file)
        tel2.state.load()
        assert tel2.state.cumulative_kwh == pytest.approx(1.8)

        # Continue accumulation
        now2 = time.time()
        tel2._process_sample(power_watts=1800.0, timestamp=now2)
        tel2._process_sample(power_watts=1800.0, timestamp=now2 + 3600.0) # +1.8 kWh = 3.6 kWh
        assert tel2.state.cumulative_kwh == pytest.approx(3.6)
