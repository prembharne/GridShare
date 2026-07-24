#!/usr/bin/env node
/**
 * scripts/setup-usdc-testnet.mjs
 *
 * One-shot idempotent setup for the USDC receiving account on Stellar testnet:
 *   1. Friendbot-fund the account (no-op if already funded).
 *   2. Establish a USDC trustline to the testnet issuer (no-op if already trusted).
 *
 * Usage:
 *   node scripts/setup-usdc-testnet.mjs
 *
 * Reads from environment (or .env):
 *   STELLAR_USDC_RECEIVE_PUBLIC   – G... public key of the receiving account
 *   STELLAR_USDC_RECEIVE_SECRET   – S... secret key of the receiving account
 *   STELLAR_USDC_ISSUER           – USDC issuer (default: Circle testnet issuer)
 *   STELLAR_HORIZON_URL           – Horizon endpoint (default: testnet)
 *   STELLAR_USDC_ASSET_CODE       – Asset code (default: USDC)
 *
 * If STELLAR_USDC_RECEIVE_PUBLIC/SECRET are absent the script generates a NEW
 * keypair, prints the pubkey, and exits with a reminder to save the secret.
 */

import {
  Keypair,
  Networks,
  Horizon,
  TransactionBuilder,
  BASE_FEE,
  Operation,
  Asset,
} from "@stellar/stellar-sdk";

// ── Config ────────────────────────────────────────────────────────────────────

const HORIZON_URL =
  process.env.STELLAR_HORIZON_URL ?? "https://horizon-testnet.stellar.org";
const NETWORK_PASSPHRASE =
  process.env.STELLAR_NETWORK_PASSPHRASE ?? Networks.TESTNET;
const USDC_ISSUER =
  process.env.STELLAR_USDC_ISSUER ??
  "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5";
const USDC_CODE = process.env.STELLAR_USDC_ASSET_CODE ?? "USDC";

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log("[setup-usdc-testnet] Starting…");
  console.log(`  Horizon : ${HORIZON_URL}`);
  console.log(`  USDC    : ${USDC_CODE}:${USDC_ISSUER}`);

  // ── Keypair resolution ────────────────────────────────────────────────────
  let keypair;
  if (process.env.STELLAR_USDC_RECEIVE_SECRET) {
    keypair = Keypair.fromSecret(process.env.STELLAR_USDC_RECEIVE_SECRET);
    console.log(`  Account : ${keypair.publicKey()} (from env)`);
  } else if (process.env.STELLAR_USDC_RECEIVE_PUBLIC) {
    console.error(
      "[setup-usdc-testnet] ERROR: STELLAR_USDC_RECEIVE_PUBLIC is set but " +
        "STELLAR_USDC_RECEIVE_SECRET is missing. Cannot sign trustline tx.\n" +
        "  Either set both, or set neither to auto-generate a fresh keypair."
    );
    process.exit(1);
  } else {
    keypair = Keypair.random();
    console.log("\n  ⚠️  No keypair supplied — generated a fresh testnet keypair:");
    console.log(`  Public : ${keypair.publicKey()}`);
    console.log(`  Secret : ${keypair.secret()}`);
    console.log(
      "\n  Add these to your .env as STELLAR_USDC_RECEIVE_PUBLIC / STELLAR_USDC_RECEIVE_SECRET"
    );
    console.log("  then re-run this script.\n");
  }

  const server = new Horizon.Server(HORIZON_URL);
  const publicKey = keypair.publicKey();

  // ── Step 1: Friendbot funding (idempotent) ────────────────────────────────
  let account;
  try {
    account = await server.loadAccount(publicKey);
    const xlmBalance =
      account.balances.find((b) => b.asset_type === "native")?.balance ?? "0";
    console.log(`[setup-usdc-testnet] Account already funded (XLM: ${xlmBalance}). Skipping Friendbot.`);
  } catch (err) {
    if (err?.response?.status !== 404) throw err;
    console.log("[setup-usdc-testnet] Account not found — calling Friendbot…");
    const friendbotUrl = `https://friendbot.stellar.org?addr=${encodeURIComponent(publicKey)}`;
    const fbRes = await fetch(friendbotUrl);
    if (!fbRes.ok) {
      const body = await fbRes.text().catch(() => "");
      throw new Error(`Friendbot failed (${fbRes.status}): ${body}`);
    }
    console.log("[setup-usdc-testnet] Friendbot funded account ✓");
    account = await server.loadAccount(publicKey);
  }

  // ── Step 2: USDC trustline (idempotent) ───────────────────────────────────
  const usdcAsset = new Asset(USDC_CODE, USDC_ISSUER);
  const hasTrustline = account.balances.some(
    (b) =>
      b.asset_type !== "native" &&
      b.asset_code === USDC_CODE &&
      b.asset_issuer === USDC_ISSUER
  );

  if (hasTrustline) {
    console.log("[setup-usdc-testnet] USDC trustline already established. Skipping.");
  } else {
    console.log("[setup-usdc-testnet] Establishing USDC trustline…");
    if (!keypair.secret) {
      // keypair was created from public key only (shouldn't reach here due to
      // earlier check, but guard defensively)
      throw new Error("Cannot sign: no secret key available.");
    }
    const tx = new TransactionBuilder(account, {
      fee: BASE_FEE,
      networkPassphrase: NETWORK_PASSPHRASE,
    })
      .addOperation(
        Operation.changeTrust({
          asset: usdcAsset,
          // Default limit (unlimited) is fine for testnet receives
        })
      )
      .setTimeout(30)
      .build();

    tx.sign(keypair);
    const result = await server.submitTransaction(tx);
    console.log(
      `[setup-usdc-testnet] Trustline established ✓  (tx: ${result.hash})`
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  const finalAccount = await server.loadAccount(publicKey);
  const xlm =
    finalAccount.balances.find((b) => b.asset_type === "native")?.balance ?? "?";
  const usdc =
    finalAccount.balances.find(
      (b) => b.asset_code === USDC_CODE && b.asset_issuer === USDC_ISSUER
    )?.balance ?? "0";

  console.log("\n[setup-usdc-testnet] ✅  Setup complete:");
  console.log(`  Public key : ${publicKey}`);
  console.log(`  XLM balance: ${xlm}`);
  console.log(`  USDC balance: ${usdc} (trustline established)`);
  console.log("\n  Set in .env:");
  console.log(`  STELLAR_USDC_RECEIVE_PUBLIC=${publicKey}`);
  if (keypair.secret) {
    console.log(`  STELLAR_USDC_RECEIVE_SECRET=${keypair.secret()}`);
  }
}

main().catch((err) => {
  console.error("[setup-usdc-testnet] FAILED:", err?.message ?? err);
  process.exit(1);
});
