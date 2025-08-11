# DemAI Contracts

Smart contract system for secure, multi-token vault management with upgradeable architecture and cross-chain deterministic deployment.

## Architecture

### Core Contracts

#### VaultFactory (`src/VaultFactory.sol`)
- **Pattern**: UUPS upgradeable proxy with beacon pattern for vault instances
- **Features**:
  - CREATE2 deterministic deployment for cross-chain address consistency
  - Single vault per user limitation
  - Centralized beacon upgrade mechanism
  - Manager authorization system for strategy execution

#### Vault (`src/Vault.sol`)
- **Pattern**: Beacon proxy implementation
- **Features**:
  - Multi-token ERC20 support
  - Dual ownership model (factory admin + user owner)
  - Strategy execution framework
  - Token approval management
  - Pausable operations

### Key Design Decisions

1. **Beacon Pattern**: All vaults share a single implementation, enabling gas-efficient upgrades
2. **CREATE2 Deployment**: Deterministic addresses across chains when factories deployed at same address
3. **Dual Ownership**: 
   - Factory owner: Administrative control (pause, upgrade)
   - Vault owner: Asset control (deposit, withdraw)
4. **Manager System**: Single authorized manager can execute strategies across all vaults

## Deployment

### Supported Networks
- Arbitrum (42161)
- Core Testnet (1116)

### Scripts
- `DeployVaultFactory.s.sol`: Deploys factory with initial implementation
- `UpgradeVault.s.sol`: Upgrades beacon to new vault implementation
- `SetManager.s.sol`: Sets authorized strategy manager
- `ExecuteUniswapSwap.s.sol`: Example strategy execution

## Security Features

- **ReentrancyGuard**: Protection against reentrancy attacks
- **Pausable**: Emergency pause mechanism
- **SafeERC20**: Safe token transfers
- **Access Control**: Role-based permissions
- **Initializable**: Protection against implementation initialization

## Testing

```bash
forge test
```

Test coverage includes:
- Vault deployment and initialization
- Token deposits/withdrawals
- Strategy execution
- Access control
- Upgrade mechanisms

## Contract Addresses

Latest deployments stored in:
- `deployments/chain-{chainId}-latest.txt`
- `deployments/latest-deployment.txt`

## Strategy Integration

Vaults support generic strategy execution through:
1. Token approvals to target protocols
2. Arbitrary call data execution
3. Manager-only access control

Example integrations:
- Uniswap swaps
- Aave lending
- Custom DeFi protocols