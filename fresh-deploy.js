import { Keypair, SorobanRpc, TransactionBuilder, Networks, BASE_FEE, xdr } from '@stellar/stellar-sdk';
import fs from 'node:fs';
import crypto from 'node:crypto';
import axios from 'axios';

async function main() {
  const rpcUrl = "https://soroban-testnet.stellar.org";
  const networkPassphrase = Networks.TESTNET;
  const server = new SorobanRpc.Server(rpcUrl, { allowHttp: true });

  // Generate new keypair
  const relayerKeypair = Keypair.random();
  console.log("Generated Keypair:");
  console.log("Secret:", relayerKeypair.secret());
  console.log("Public:", relayerKeypair.publicKey());

  // Fund account via friendbot
  console.log("Funding via friendbot...");
  await axios.get(`https://friendbot.stellar.org/?addr=${relayerKeypair.publicKey()}`);
  console.log("Funded!");

  // Get account
  const sourceAccount = await server.getAccount(relayerKeypair.publicKey());
  
  // Read and hash WASM
  const wasmPath = "E:/stellar builder program/contracts/gridshare-escrow/target/wasm32-unknown-unknown/release/gridshare_escrow.optimized.wasm";
  const wasm = fs.readFileSync(wasmPath);
  
  // Install WASM
  console.log("Uploading WASM...");
  const uploadOp = new xdr.Operation({
    body: new xdr.OperationBody({
      type: xdr.OperationType.invokeHostFunction(),
      invokeHostFunctionOp: new xdr.InvokeHostFunctionOp({
        hostFunction: new xdr.HostFunction({
          type: xdr.HostFunctionType.hostFunctionTypeUploadContractWasm(),
          wasm: wasm
        }),
        auth: []
      })
    })
  });

  const uploadTx = new TransactionBuilder(sourceAccount, { fee: BASE_FEE, networkPassphrase })
    .addOperation(uploadOp)
    .setTimeout(300)
    .build();

  uploadTx.sign(relayerKeypair);
  
  console.log("Simulating Upload...");
  const uploadSim = await server.simulateTransaction(uploadTx);
  if (uploadSim.error) {
    console.error("Upload Simulation error:", uploadSim.error);
    return;
  }
  
  uploadTx.setSorobanTransactionData(uploadSim.transactionData);
  const feeBumpUploadTx = TransactionBuilder.buildFeeBumpTransaction(relayerKeypair, BASE_FEE, uploadTx.toEnvelope(), networkPassphrase);
  feeBumpUploadTx.sign(relayerKeypair);

  console.log("Submitting Upload...");
  const uploadResult = await server.sendTransaction(feeBumpUploadTx);
  
  if (uploadResult.status === "ERROR") {
    console.error("Upload failed:", uploadResult.errorResult);
    return;
  }
  
  let wasmHashResult;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    const tx = await server.getTransaction(uploadResult.hash);
    if (tx.status === "SUCCESS") {
      wasmHashResult = tx;
      break;
    }
    if (tx.status === "FAILED" || tx.status === "NOT_FOUND") {
      console.error("Upload tx failed:", tx);
      return;
    }
  }
  
  const wasmIdBytes = wasmHashResult.resultMetaXdr?.v3?.sorobanMeta?.returnValue?.bytes;
  if (!wasmIdBytes) {
      console.log("Failed to extract WASM hash from result!");
      return;
  }

  // Create contract using the WASM ID
  console.log("Deploying Contract...");
  // ... using soroban.exe is so much easier ... wait ...
}
main();
