import { Keypair, rpc, TransactionBuilder, Networks, BASE_FEE, Operation, Address, nativeToScVal, Contract } from '@stellar/stellar-sdk';
import fs from 'node:fs';

async function main() {
  const rpcUrl = "https://soroban-testnet.stellar.org";
  const networkPassphrase = Networks.TESTNET;
  const server = new rpc.Server(rpcUrl, { allowHttp: true });

  const env = fs.readFileSync('.env', 'utf8').split('\n').reduce((acc, line) => {
    const [k, ...v] = line.split('=');
    if (k && v.length) acc[k] = v.join('=').trim().replace(/"/g, '');
    return acc;
  }, {});

  const relayerSecretKey = env.STELLAR_RELAYER_SECRET_KEY;
  const contractId = env.SOROBAN_CONTRACT_ID;

  if (!relayerSecretKey || !contractId) {
    throw new Error("Missing env vars");
  }

  const relayerKeypair = Keypair.fromSecret(relayerSecretKey);
  const relayerAddress = relayerKeypair.publicKey();
  console.log("Relayer:", relayerAddress);
  console.log("Contract:", contractId);

  const contract = new Contract(contractId);
  const sourceAccount = await server.getAccount(relayerAddress);

  const submitFeeBumped = async (op) => {
    let source = await server.getAccount(relayerAddress);
    const inner = new TransactionBuilder(source, { fee: BASE_FEE, networkPassphrase })
      .addOperation(op)
      .setTimeout(60)
      .build();

    inner.sign(relayerKeypair);

    // simulate for footprint
    const sim = await server.simulateTransaction(inner);
    if (sim.error) throw new Error("Simulate error: " + sim.error);

    const prepared = await server.prepareTransaction(inner);
    prepared.sign(relayerKeypair);

    const result = await server.sendTransaction(prepared);
    if (result.status === "ERROR") throw new Error("Send failed");

    let finalRes;
    while(true) {
       await new Promise(r => setTimeout(r, 2000));
       const tx = await server.getTransaction(result.hash);
       if (tx.status === "SUCCESS") {
         finalRes = tx;
         break;
       }
       if (tx.status === "FAILED") throw new Error("TX failed on chain");
    }
    return finalRes;
  };

  try {
    console.log("Initializing...");
    const initOp = contract.call(
      "initialize",
      new Address(relayerAddress).toScVal(), // admin
      new Address(relayerAddress).toScVal(), // relayer
      new Address(relayerAddress).toScVal(), // upgrader
      new Address(relayerAddress).toScVal(), // treasury
    );
    await submitFeeBumped(initOp);
    console.log("Initialized!");
  } catch (e) {
    console.log("Initialization probably already done or failed:", e.message);
  }

  console.log("Minting 1000 credits to Relayer...");
  const mintOp = contract.call(
    "mint",
    new Address(relayerAddress).toScVal(),
    nativeToScVal(1000, { type: "i128" })
  );
  await submitFeeBumped(mintOp);
  console.log("Mint successful!");

  console.log("Checking total supply...");
  const supplyOp = contract.call("total_supply");
  let source2 = await server.getAccount(relayerAddress);
  const supplyTx = new TransactionBuilder(source2, { fee: BASE_FEE, networkPassphrase })
    .addOperation(supplyOp)
    .setTimeout(60)
    .build();
  
  const supplySim = await server.simulateTransaction(supplyTx);
  console.log("Total Supply:", supplySim.result.retval.value().toString());

}
main().catch(console.error);
