#!/usr/bin/env bash

# Project-specific keychain secrets configuration
# Similar to Python KEYCHAIN_SECRETS array
#
# This file defines which secrets should be loaded from the macOS keychain
# when LOAD_KEYCHAIN_SECRETS=1 is set in the environment.
#
# Usage:
#   LOAD_KEYCHAIN_SECRETS=1 ./scripts/run.sh YourScript.s.sol
#
# To add secrets to keychain manually:
#   security add-generic-password -s "service" -a "account" -w "secret_value"

# Define keychain secrets for this project
# Format: "service:account:env_var" (env_var optional, defaults to account)
KEYCHAIN_SECRETS=(
    "demether:PRIVATE_KEY"
)

# Function to load keychain secrets for this project
load_keychain_secrets() {
    # Source the generic keychain utilities
    local script_dir="$(dirname "${BASH_SOURCE[0]}")"
    source "$script_dir/keychain_utils.sh"
    
    # Load the secrets using the generic utility
    load_secrets "${KEYCHAIN_SECRETS[@]}"
} 