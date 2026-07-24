"""
Module 2: Soroban Blockchain Bridge (soroban_bridge.py)
Interacts with Stellar Soroban smart contract using stellar-sdk (v15.0.0+).
Constructs InvokeHostFunctionOp targeting `settle_energy`.
Sets memo explicitly to MEMO_NONE.
Implements non-blocking async background worker queue with exponential backoff retries.
"""

import asyncio
import logging
import time
from dataclasses import dataclass
from typing import Optional, Dict, Any

from stellar_sdk import (
    Keypair,
    Account,
    Network,
    TransactionBuilder,
    InvokeHostFunction,
    NoneMemo,
    Address,
    scval,
    xdr,
)
from stellar_sdk.soroban_server import SorobanServer

logger = logging.getLogger("gridshare.bridge")


@dataclass
class SettlementTask:
    meter_id: str
    kwh_consumed: int
    timestamp: int
    retries: int = 0


class SorobanSettlementBridge:
    """
    Stellar Soroban Bridge for Energy Settlement.
    Handles non-blocking task queueing, transaction building with InvokeHostFunction,
    MEMO_NONE enforcement, and resilient exponential retry logic.
    """

    def __init__(
        self,
        rpc_url: str = "https://soroban-testnet.stellar.org",
        network_passphrase: str = "Test SDF Network ; September 2015",
        contract_id: str = "",
        secret_key: str = "",
        max_retries: int = 5,
        retry_base_delay: float = 1.0,
    ):
        self.rpc_url = rpc_url
        self.network_passphrase = network_passphrase
        self.contract_id = contract_id
        self.secret_key = secret_key
        self.max_retries = max_retries
        self.retry_base_delay = retry_base_delay

        if secret_key:
            self.keypair = Keypair.from_secret(secret_key)
            self.public_key = self.keypair.public_key
        else:
            self.keypair = None
            self.public_key = ""

        self.soroban_server = SorobanServer(self.rpc_url)
        self.queue: asyncio.Queue[SettlementTask] = asyncio.Queue()
        self._worker_task: Optional[asyncio.Task] = None
        self._running = False

    def _fetch_account_sequence(self) -> int:
        """Fetch latest sequence number for relayer account."""
        account = self.soroban_server.load_account(self.public_key)
        return account.sequence

    async def build_settle_transaction(
        self, meter_id: str, kwh_consumed: int, timestamp: int
    ) -> Any:
        """
        Construct a transaction invoking `settle_energy` on Soroban contract.
        Uses `InvokeHostFunction` operation and explicitly sets `NoneMemo()`.
        """
        sequence = await asyncio.to_thread(self._fetch_account_sequence)
        account = Account(account=self.public_key, sequence=sequence)

        # Construct ScVal arguments for settle_energy(meter_id: String, kwh_consumed: u32, timestamp: u64)
        args = [
            scval.to_string(meter_id),
            scval.to_uint32(int(kwh_consumed)),
            scval.to_uint64(int(timestamp)),
        ]

        # Construct InvokeHostFunction operation
        invoke_contract = xdr.InvokeContractArgs(
            contract_address=Address(self.contract_id).to_xdr_sc_address(),
            function_name=scval.to_symbol("settle_energy").sym,
            args=args,
        )
        host_fn = xdr.HostFunction(
            type=xdr.HostFunctionType.HOST_FUNCTION_TYPE_INVOKE_CONTRACT,
            invoke_contract=invoke_contract,
        )
        op = InvokeHostFunction(host_function=host_fn)

        # Build Transaction with NONE Memo
        builder = (
            TransactionBuilder(
                source_account=account,
                network_passphrase=self.network_passphrase,
                base_fee=100,
            )
            .append_operation(op)
            .set_timeout(30)
            .add_memo(NoneMemo())  # Explicitly set MEMO_NONE
        )

        tx = builder.build()
        return tx

    async def _submit_to_network(self, tx: Any) -> Dict[str, Any]:
        """Simulate, prepare, sign, submit, and poll transaction on Soroban network."""
        tx.sign(self.keypair)

        # Step 1: Simulate
        sim = await asyncio.to_thread(self.soroban_server.simulate_transaction, tx)
        if getattr(sim, "error", None):
            raise RuntimeError(f"Soroban simulation failed: {sim.error}")

        # Step 2: Prepare
        prepared_tx = await asyncio.to_thread(self.soroban_server.prepare_transaction, tx)
        prepared_tx.sign(self.keypair)

        # Step 3: Send
        send_resp = await asyncio.to_thread(self.soroban_server.send_transaction, prepared_tx)
        if send_resp.status == "ERROR":
            raise RuntimeError(f"Soroban submission failed: {send_resp}")

        tx_hash = send_resp.hash

        # Step 4: Poll status
        for _ in range(15):
            await asyncio.sleep(2)
            status_resp = await asyncio.to_thread(self.soroban_server.get_transaction, tx_hash)
            if status_resp.status == "SUCCESS":
                return {"status": "SUCCESS", "hash": tx_hash, "ledger": status_resp.ledger}
            if status_resp.status == "FAILED":
                raise RuntimeError(f"On-chain transaction failed: {status_resp}")

        raise RuntimeError(f"Transaction confirmation timed out for {tx_hash}")

    async def _process_settlement_with_retry(self, task: SettlementTask) -> Dict[str, Any]:
        """Execute settlement with async exponential backoff retry policy."""
        while True:
            try:
                tx = await self.build_settle_transaction(
                    meter_id=task.meter_id,
                    kwh_consumed=task.kwh_consumed,
                    timestamp=task.timestamp,
                )
                res = await self._submit_to_network(tx)
                logger.info(f"Successfully settled {task.kwh_consumed} kWh for {task.meter_id} on-chain: {res.get('hash')}")
                return res
            except Exception as e:
                task.retries += 1
                if task.retries > self.max_retries:
                    logger.error(f"Exceeded max retries for meter {task.meter_id}: {e}")
                    raise e
                delay = self.retry_base_delay * (2 ** (task.retries - 1))
                logger.warning(f"Settlement failed for {task.meter_id} (attempt {task.retries}/{self.max_retries}). Retrying in {delay:.2f}s: {e}")
                await asyncio.sleep(delay)

    async def enqueue_settlement(self, meter_id: str, kwh_consumed: int, timestamp: int) -> bool:
        """
        Non-blocking enqueue method called by telemetry polling loop.
        Returns immediately (sub-millisecond) without blocking on network/RPC latency.
        """
        task = SettlementTask(meter_id=meter_id, kwh_consumed=kwh_consumed, timestamp=timestamp)
        await self.queue.put(task)
        logger.debug(f"Enqueued settlement task for meter {meter_id} ({kwh_consumed} kWh)")
        return True

    async def _worker_loop(self) -> None:
        """Background worker loop processing queue items asynchronously."""
        while self._running:
            try:
                task = await self.queue.get()
                try:
                    await self._process_settlement_with_retry(task)
                except Exception as err:
                    logger.error(f"Failed processing settlement for {task.meter_id}: {err}")
                finally:
                    self.queue.task_done()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Unexpected error in Soroban bridge worker loop: {e}")

    def start_worker(self) -> None:
        if not self._running:
            self._running = True
            self._worker_task = asyncio.create_task(self._worker_loop())
            logger.info("Started Soroban bridge background worker.")

    async def stop_worker(self) -> None:
        if self._running:
            self._running = False
            if self._worker_task:
                self._worker_task.cancel()
                await asyncio.gather(self._worker_task, return_exceptions=True)
            logger.info("Stopped Soroban bridge background worker.")
