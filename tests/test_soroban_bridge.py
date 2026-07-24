"""
Unit tests for Module 2: Soroban Blockchain Bridge (soroban_bridge.py)
Tests stellar-sdk v15+ transaction construction, InvokeHostFunctionOp, MEMO_NONE, and non-blocking async retries.
"""

import asyncio
import os
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src", "telemetry")))

from soroban_bridge import SorobanSettlementBridge, SettlementTask


class TestSorobanBridgeTransactionBuilding:
    """Test stellar-sdk transaction building constraints."""

    @pytest.mark.asyncio
    async def test_build_settlement_transaction_structure(self):
        bridge = SorobanSettlementBridge(
            rpc_url="https://soroban-testnet.stellar.org",
            network_passphrase="Test SDF Network ; September 2015",
            contract_id="CD65ABMSSFQNJ6KP2BJCJ344NGZOE5FSV3OSCDW4OXLTPQAY3XDBTQQR",
            secret_key="SDWAMBMHF66ZMK7ZO65N6SPBOOLHJ2DEUEBIRQAZPMTB2GQCSDUYMC2H",
        )

        with patch.object(bridge, "_fetch_account_sequence") as mock_seq:
            mock_seq.return_value = 1000

            tx = await bridge.build_settle_transaction(
                meter_id="meter_001",
                kwh_consumed=15,
                timestamp=1700000000,
            )

            # Check Memo is explicitly NONE
            from stellar_sdk import NoneMemo
            assert isinstance(tx.transaction.memo, NoneMemo)

            # Check operation type is InvokeHostFunction
            assert len(tx.transaction.operations) == 1
            op = tx.transaction.operations[0]
            from stellar_sdk import InvokeHostFunction
            assert isinstance(op, InvokeHostFunction)


class TestSorobanBridgeAsyncQueueAndRetry:
    """Test non-blocking async queue and retry behavior."""

    @pytest.mark.asyncio
    async def test_enqueue_non_blocking(self):
        bridge = SorobanSettlementBridge(
            rpc_url="https://soroban-testnet.stellar.org",
            network_passphrase="Test SDF Network ; September 2015",
            contract_id="CD65ABMSSFQNJ6KP2BJCJ344NGZOE5FSV3OSCDW4OXLTPQAY3XDBTQQR",
            secret_key="SDWAMBMHF66ZMK7ZO65N6SPBOOLHJ2DEUEBIRQAZPMTB2GQCSDUYMC2H",
        )

        # Enqueue should return immediately without waiting for RPC network call
        start_time = asyncio.get_event_loop().time()
        success = await bridge.enqueue_settlement(
            meter_id="meter_001",
            kwh_consumed=10,
            timestamp=1700000000,
        )
        elapsed = asyncio.get_event_loop().time() - start_time

        assert success is True
        assert elapsed < 0.05  # Sub-50ms non-blocking return
        assert bridge.queue.qsize() == 1

    @pytest.mark.asyncio
    async def test_retry_on_rpc_failure(self):
        bridge = SorobanSettlementBridge(
            rpc_url="https://soroban-testnet.stellar.org",
            network_passphrase="Test SDF Network ; September 2015",
            contract_id="CD65ABMSSFQNJ6KP2BJCJ344NGZOE5FSV3OSCDW4OXLTPQAY3XDBTQQR",
            secret_key="SDWAMBMHF66ZMK7ZO65N6SPBOOLHJ2DEUEBIRQAZPMTB2GQCSDUYMC2H",
            max_retries=2,
            retry_base_delay=0.01,
        )

        task = SettlementTask(meter_id="m1", kwh_consumed=5, timestamp=1000)

        with patch.object(bridge, "_fetch_account_sequence") as mock_seq, \
             patch.object(bridge, "_submit_to_network", new_callable=AsyncMock) as mock_submit:
            mock_seq.return_value = 1000
            # Simulate 2 network failures followed by success
            mock_submit.side_effect = [
                Exception("Network timeout"),
                Exception("RPC Rate limit"),
                {"status": "SUCCESS", "hash": "abc123hash"},
            ]

            result = await bridge._process_settlement_with_retry(task)

            assert result["status"] == "SUCCESS"
            assert mock_submit.call_count == 3
