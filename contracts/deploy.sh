#!/usr/bin/env bash
# Deploy + initialize the GridShare escrow contract on a Stellar network.
#
# Usage:
#   NETWORK=testnet ./deploy.sh
#
# Env:
#   STELLAR_RPC_URL        (default testnet)
#   STELLAR_NETWORK_PASSPHRASE
#   ADMIN_SECRET           identity that owns admin/relayer/upgrader/treasury
#   TREASURY_ADDRESS       platform-fee sink (a Stellar address)
#   WASM                   path to built wasm (default from build.sh)
set -euo pipefail

NETWORK="${NETWORK:-testnet}"
RPC_URL="${STELLAR_RPC_URL:-https://soroban-testnet.stellar.org}"
PASSPHRASE="${STELLAR_NETWORK_PASSPHRASE:-Test SDF Network ; September 2015}"
WASM="${WASM:-gridshare-escrow/target/wasm32-unknown-unknown/release/gridshare_escrow.wasm}"

: "${ADMIN_SECRET:?Set ADMIN_SECRET to the deployer's Stellar secret key}"
: "${TREASURY_ADDRESS:?Set TREASURY_ADDRESS to the platform treasury address}"

echo "==> Deploying to $NETWORK"
CONTRACT_ID=$(soroban contract deploy \
  --network "$NETWORK" \
  --source "$ADMIN_SECRET" \
  --wasm "$WASM")

echo "Contract ID: $CONTRACT_ID"

# Relayer and upgrader are the same operational key as admin in the demo;
# in production split them across distinct secured keys.
ADMIN_ADDRESS=$(soroban config identity address "$ADMIN_SECRET" 2>/dev/null || \
  echo "$ADMIN_SECRET")

echo "==> Initializing roles"
soroban contract invoke \
  --network "$NETWORK" \
  --source "$ADMIN_SECRET" \
  --id "$CONTRACT_ID" \
  -- initialize \
  --admin "$ADMIN_ADDRESS" \
  --relayer "$ADMIN_ADDRESS" \
  --upgrader "$ADMIN_ADDRESS" \
  --treasury "$TREASURY_ADDRESS"

echo "==> Saving contract id for the backend"
echo "$CONTRACT_ID" > .deployed-contract-id

echo "==> Done. Set SOROBAN_CONTRACT_ID=$CONTRACT_ID in the backend .env"
