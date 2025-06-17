# Deployment Scripts

This directory contains Foundry scripts for deploying the DeMai Vault contracts.

## VaultFactory Deployment

The `DeployVaultFactory.s.sol` script deploys the complete VaultFactory system including:

1. **Vault Implementation**: The implementation contract for individual vaults
2. **VaultFactory Implementation**: The factory contract implementation  
3. **VaultFactory Proxy**: An upgradeable proxy pointing to the factory implementation

### Prerequisites

1. Set up your environment variables:
   ```bash
   export PRIVATE_KEY="your_private_key_here"
   export RPC_URL="your_rpc_endpoint_here"
   ```

2. Make sure you have enough native tokens for gas fees on your target network.

### Usage

#### Deploy to a local network (Anvil):
```bash
# Start Anvil in a separate terminal
anvil

# Deploy (anvil default RPC)
forge script scripts/DeployVaultFactory.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Deploy to a testnet:
```bash
forge script scripts/DeployVaultFactory.s.sol --rpc-url $RPC_URL --broadcast --verify
```

#### Deploy to mainnet:
```bash
forge script scripts/DeployVaultFactory.s.sol --rpc-url $RPC_URL --broadcast --verify --slow
```

### Output

The script will:
- Deploy all contracts
- Initialize the VaultFactory with the signer as owner
- Verify the deployment by checking contract states
- Save deployment info to `deployments/latest-deployment.txt`
- Print a complete summary with all contract addresses

### Post-Deployment

After deployment, you can:
- Use the VaultFactory proxy address to interact with the factory
- Deploy vaults for users using `deployVault(userAddress)` or `deployVault(userAddress, salt)`
- Upgrade the vault implementation using `upgradeBeacon(newImplementation)`
- Pause/unpause individual vaults or the entire factory

The deployer will be the owner of the VaultFactory and can perform administrative functions. 