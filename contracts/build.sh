#!/usr/bin/env bash
# Build the GridShare escrow WASM (optimized) and emit the contract spec.
#
# Prereqs: rustup + wasm32 target + soroban-cli
#   rustup target add wasm32-unknown-unknown
#   cargo install --locked soroban-cli
set -euo pipefail

cd "$(dirname "$0")/gridshare-escrow"

echo "==> Building optimized WASM"
cargo build --target wasm32-unknown-unknown --release

WASM="target/wasm32-unknown-unknown/release/gridshare_escrow.wasm"
echo "==> WASM at $WASM"

if command -v soroban >/dev/null 2>&1; then
  echo "==> Emitting contract spec (typescript bindings source)"
  soroban contract inspect "$WASM" --output json > contract-spec.json || true
fi

echo "==> Done"
