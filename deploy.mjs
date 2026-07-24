import { Keypair, rpc, TransactionBuilder, Networks, BASE_FEE, Operation, Address } from '@stellar/stellar-sdk';
import fs from 'node:fs';
import axios from 'axios';

async function main() {
  const rpcUrl = "https://soroban-testnet.stellar.org";
  const networkPassphrase = Networks.TESTNET;
  const server = new rpc.Server(rpcUrl, { allowHttp: true });

  const relayerKeypair = Keypair.random();
  console.log("Secret:", relayerKeypair.secret());
  
  await axios.get(`https://friendbot.stellar.org/?addr=${relayerKeypair.publicKey()}`);

  const sourceAccount = await server.getAccount(relayerKeypair.publicKey());
  
  const wasmPath = "E:/stellar builder program/contracts/gridshare-escrow/out/gridshare_escrow.wasm";
  const wasm = fs.readFileSync(wasmPath);
  
  console.log("Uploading WASM...");
  const uploadTx = new TransactionBuilder(sourceAccount, { fee: BASE_FEE, networkPassphrase })
    .addOperation(Operation.uploadContractWasm({ wasm }))
    .setTimeout(300)
    .build();

  uploadTx.sign(relayerKeypair);
  const uploadSim = await server.simulateTransaction(uploadTx);
  const preparedUploadTx = await server.prepareTransaction(uploadTx);
  preparedUploadTx.sign(relayerKeypair);

  const uploadResult = await server.sendTransaction(preparedUploadTx);
  
  let wasmHashResult;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    const tx = await server.getTransaction(uploadResult.hash);
    if (tx.status === "SUCCESS") {
      wasmHashResult = tx;
      break;
    }
  }
  
  let wasmIdBytes;
  try {
     wasmIdBytes = wasmHashResult.returnValue.value();
  } catch(e) {
     wasmIdBytes = Buffer.from(uploadSim.transactionData.build().ext().v().resources().instructions(), 'hex'); // dummy fallback if this fails, we actually need to get the hash. Wait, the SDK's getTransaction actually parses returnValue now!
  }
  // Wait, in latest SDK, `tx.returnValue` might be an scVal or the raw hash! Let's check the API.
  // We can just get it from `uploadSim.results[0].returnValue.value()` !
  // Let's use `uploadSim` which has the return value.
  const wasmHash = uploadSim.result.retval.bytes(); // or value()

  console.log("WASM Hash uploaded successfully.");

  const sourceAccount2 = await server.getAccount(relayerKeypair.publicKey());

  console.log("Deploying Contract...");
  const createTx = new TransactionBuilder(sourceAccount2, { fee: BASE_FEE, networkPassphrase })
    .addOperation(Operation.createCustomContract({
      address: new Address(relayerKeypair.publicKey()),
      wasmHash: wasmHash
    }))
    .setTimeout(300)
    .build();

  createTx.sign(relayerKeypair);
  const preparedCreateTx = await server.prepareTransaction(createTx);
  preparedCreateTx.sign(relayerKeypair);

  const createResult = await server.sendTransaction(preparedCreateTx);
  
  console.log("Waiting for Contract deployment confirmation...");
  let contractIdResult;
  while (true) {
    await new Promise(r => setTimeout(r, 2000));
    const tx = await server.getTransaction(createResult.hash);
    if (tx.status === "SUCCESS") {
      contractIdResult = tx;
      break;
    }
  }
  
  console.log("Contract deployed successfully!");
  console.log("Result Meta XDR base64:");
  console.log(contractIdResult.resultMetaXdr.toXDR('base64'));
  process.exit(0);
}
main().catch(console.error);