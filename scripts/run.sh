#!/usr/bin/env bash
set -e

# Check if script name and chain are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Script name or chain not provided"
    echo "Usage: ./scripts/run.sh <ScriptName.s.sol> <chain_name>"
    echo "Available chains: mainnet, sepolia, polygon, arbitrum, optimism, base"
    exit 1
fi

# Load environment variables from .env file (if it exists)
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    # Source and export environment variables
    set -a
    source .env
    set +a
fi

# Load secrets from keychain
echo "Loading secrets from keychain..."
# Source the project-specific keychain configuration
source "$(dirname "$0")/keychain_config.sh"

# Load keychain secrets (this will export them as environment variables)
if load_keychain_secrets; then
    echo "Successfully loaded secrets from keychain"
else
    echo "Warning: Failed to load some secrets from keychain" >&2
fi

# Define RPC URLs for different chains using environment variables or fallback defaults
declare -A RPC_URLS=(
    ["mainnet"]="${MAINNET_RPC_URL:-https://eth.llamarpc.com}"
    ["arbitrum"]="${ARBITRUM_RPC_URL:-https://arb-mainnet.g.alchemy.com/v2/ESrlxBQxB17StnQQKuXeV8V1o4G5aLuW}"
    ["base"]="${BASE_RPC_URL:-https://mainnet.base.org}"
)

# Get the chain name from second parameter
CHAIN_NAME="$2"

# Check if chain is supported
if [ -z "${RPC_URLS[$CHAIN_NAME]}" ]; then
    echo "Error: Unsupported chain '$CHAIN_NAME'"
    echo "Available chains: ${!RPC_URLS[@]}"
    exit 1
fi

# Get RPC URL for the specified chain
RPC_URL="${RPC_URLS[$CHAIN_NAME]}"

echo "Deploying to chain: $CHAIN_NAME"
echo "Using RPC URL: $RPC_URL"



# Extract contract name from script filename (remove .s.sol extension)
CONTRACT_NAME=$(basename "$1" .s.sol)

# Run the script with deploy profile for better optimization
FOUNDRY_PROFILE=deploy forge script "scripts/$1" --tc "$CONTRACT_NAME" --rpc-url "$RPC_URL" --broadcast --ffi -vvv