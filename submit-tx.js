import { SorobanRpc, TransactionBuilder, Networks, BASE_FEE } from '@stellar/stellar-sdk';

async function main() {
  // The XDR from --build-only
  const txXdr = "AAAAAgAAAADdSjSlCZ5JYd0lQ2KiF8PVKVhGVJ4ioAwJXkwIjnb2NgAAAGQAN7m9AAAAAQAAAAAAAAAAAAAAAQAAAAAAAAAYAAAAAQAAAAAAAAAAAAAAAN1KNKUJnklh3SVDYqIXw9UpWEZUniKgDAleTAiOdvY2ldZDLYo6sZmMa4yPh6sSmz9PiyAnbx8XQx8dJdW7Ln4AAAAAHIdzr/UCMBaX+sqUy4HyM9Nmmhz4WIWBBFGkxEg2z1sAAAAAAAAAAAAAAAA=";

  const rpcUrl = "https://soroban-testnet.stellar.org";
  const networkPassphrase = Networks.TESTNET;
  const server = new SorobanRpc.Server(rpcUrl, { allowHttp: true });

  // Submit the transaction
  console.log("Submitting transaction...");
  const sendResult = await server.sendTransaction(txXdr);
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