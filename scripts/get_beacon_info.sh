#!/bin/bash

# Get Beacon Info Script
# This script retrieves the beacon address and creation code from the deployed VaultFactory

echo "=== Getting Beacon Information from VaultFactory ==="

# Check if RPC_URL is set
if [ -z "$RPC_URL" ]; then
    echo "Error: RPC_URL environment variable not set"
    echo "Please set it with: export RPC_URL=<your_arbitrum_rpc_url>"
    exit 1
fi

echo "Using RPC URL: $RPC_URL"
echo "Running on Arbitrum (Chain ID: 42161)"
echo ""

# Run the Forge script
forge script scripts/GetBeaconInfo.s.sol:GetBeaconInfo \
    --rpc-url $RPC_URL \
    --via-ir

echo ""
echo "=== Beacon Info Retrieval Complete ===" 