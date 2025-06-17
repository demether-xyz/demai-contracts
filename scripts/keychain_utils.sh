#!/usr/bin/env bash

# Generic keychain utility functions for managing secrets
# Reusable across projects without modification

# Function to get a secret from iCloud Keychain
get_secret() {
    local service="$1"
    local account="$2"
    
    if [ -z "$service" ] || [ -z "$account" ]; then
        echo "Error: Service and account are required" >&2
        return 1
    fi
    
    # Use security command to get password from keychain
    local secret
    secret=$(security find-generic-password -s "$service" -a "$account" -w 2>/dev/null)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$secret" ]; then
        echo "$secret"
        return 0
    else
        echo "Error: Could not retrieve secret for account '$account' from service '$service'" >&2
        return 1
    fi
}

# Function to load secrets from keychain into environment variables
# Takes an array of secrets configuration as parameter
load_secrets() {
    local secrets_array=("$@")
    local success=true
    
    if [ ${#secrets_array[@]} -eq 0 ]; then
        echo "No secrets configuration provided" >&2
        return 1
    fi
    
    echo "Loading secrets from keychain..."
    
    for secret_config in "${secrets_array[@]}"; do
        # Parse the configuration: "service:account:env_var"
        IFS=':' read -r service account env_var <<< "$secret_config"
        
        # If env_var is not specified, use account name
        if [ -z "$env_var" ]; then
            env_var="$account"
        fi
        
        # Get secret from keychain
        local secret_value
        if secret_value=$(get_secret "$service" "$account"); then
            export "$env_var"="$secret_value"
            echo "✓ Loaded $env_var from keychain"
        else
            echo "✗ Failed to load $env_var from keychain" >&2
            success=false
        fi
    done
    
    if [ "$success" = true ]; then
        echo "Successfully loaded all secrets from keychain"
        return 0
    else
        echo "Failed to load some secrets from keychain" >&2
        return 1
    fi
}

# Main function for command line usage
main() {
    case "${1:-}" in
        "get")
            if [ $# -ne 3 ]; then
                echo "Usage: $0 get <service> <account>" >&2
                exit 1
            fi
            get_secret "$2" "$3"
            ;;
        *)
            echo "Usage: $0 {get}" >&2
            echo "  get <service> <account>  - Get a specific secret"
            echo ""
            echo "Note: To load secrets, source this script and call load_secrets with your configuration array"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi 