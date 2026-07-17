import fs from 'node:fs';
import crypto from 'node:crypto';
import {
  SorobanRpc,
  TransactionBuilder,
  Networks,
  BASE_FEE,
  Keypair,
  xdr,
} from '@stellar/stellar-sdk';

async function main() {
  const rpcUrl = "https://soroban-testnet.stellar.org";
  const networkPassphrase = Networks.TESTNET;
  const server = new SorobanRpc.Server(rpcUrl, { allowHttp: true });

  // Relayer keypair
  const relayerSecret = "SAHPIJXQSQNQXPNUVMTH5RMPEKXZ4D6DG2RW4UFUGTGLYHJURTJQGD6O";
  const relayerKeypair = Keypair.fromSecret(relayerSecret);
  const relayerPublicKey = relayerKeypair.publicKey();

  // Get account
  const sourceAccount = await server.getAccount(relayerPublicKey);
  console.log("Account sequence:", sourceAccount.sequenceNumber());

  // Read and hash the WASM
  const wasmPath = "E:/stellar builder program/contracts/gridshare-escrow/target/wasm32-unknown-unknown/release/gridshare_escrow.optimized.wasm";
  const wasm = fs.readFileSync(wasmPath);
  const wasmHash = crypto.createHash('sha256').update(wasm).digest();

  console.log("WASM size:", wasm.length);
  console.log("WASM hash:", wasmHash.toString('hex'));

  // Create the CreateContractArgs
  const createContractArgs = new xdr.CreateContractArgs({
    contractIdPreimage: new xdr.ContractIdPreimage({
      type: xdr.ContractIdPreimageType.contractIdPreimageFromAddress(),
      fromAddress: new xdr.ContractIdPreimageFromAddress({
        address: new xdr.Address({
          address: new xdr.ScAddress({
            type: xdr.ScAddressType.scAddressTypeAccount(),
            accountId: relayerKeypair.publicKey()
          })
        }),
        salt: new xdr.Uint256(Buffer.alloc(32))
      })
    }),
    executable: new xdr.ContractExecutable({
      type: xdr.ContractExecutableType.contractExecutableWasm(),
      wasmHash: new xdr.Hash(wasmHash)
    })
  });

  // Create HostFunction
  const hostFunction = new xdr.HostFunction({
    type: xdr.HostFunctionType.hostFunctionTypeCreateContract(),
    createContract: createContractArgs
  });

  // Create InvokeHostFunctionOp
  const invokeOp = new xdr.InvokeHostFunctionOp({
    hostFunction: hostFunction,
    auth: []
  });

  // Create Operation
  const op = new xdr.Operation({
    body: new xdr.OperationBody({
      type: xdr.OperationType.invokeHostFunction(),
      invokeHostFunctionOp: invokeOp
    })
  });

  // Build transaction
  const deployTx = new TransactionBuilder(sourceAccount, {
    fee: BASE_FEE,
    networkPassphrase,
  })
    .addOperation(op)
    .setTimeout(300)
    .build();

  // Sign
  deployTx.sign(relayerKeypair);

  // Simulate
  console.log("Simulating...");
  const deploySim = await server.simulateTransaction(deployTx);
  console.log("Simulation:", JSON.stringify(deploySim, null, 2));

  if (deploySim.error) {
    console.error("Simulation error:", deploySim.error);
    return;
  }

  // Prepare transaction with simulation results
  deployTx.setSorobanTransactionData(deploySim.transactionData);

  // Build fee bump
  const feeBumpTx = TransactionBuilder.buildFeeBumpTransaction(
    relayerKeypair,
    BASE_FEE,
    deployTx.toEnvelope(),
    networkPassphrase
  );
  feeBumpTx.sign(relayerKeypair);

  // Submit
  console.log("Submitting...");
  const sendResult = await server.sendTransaction(feeBumpTx);
  console.log("Send result:", sendResult);

  if (sendResult.status === "ERROR") {
    console.error("Deploy failed:", sendResult.errorResult);
    return;
  }

  // Wait for confirmation
  const hash = sendResult.hash;
  console.log("Transaction hash:", hash);

  let result;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    const tx = await server.getTransaction(hash);
    console.log("Transaction status:", tx.status);
    if (tx.status === "SUCCESS") {
      result = tx;
      break;
    }
    if (tx.status === "FAILED" || tx.status === "NOT_FOUND") {
      console.error("Transaction failed:", tx);
      return;
    }
  }

  // Get contract ID from result
  const contractId = result.resultMetaXdr?.v3?.sorobanMeta?.returnValue?.address?.contractId;
  if (contractId) {
    const contractIdStr = Buffer.from(contractId).toString('hex').toUpperCase();
    console.log('Contract deployed successfully!');
    console.log('Contract ID: C' + contractIdStr);
  } else {
    console.log('Could not extract contract ID from result');
    console.log('Result meta:', JSON.stringify(result.resultMetaXdr, null, 2));
  }
}

main().catch(console.error);