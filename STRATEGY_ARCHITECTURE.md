# Ultra-Simplified Strategy Architecture

## Overview

This ultra-simplified architecture is a pure passthrough system where vaults execute arbitrary calls to external protocols. The manager provides all call data directly and specifies any token approvals needed, eliminating complexity while maintaining security.

## Core Concept

**The vault is simply a secure passthrough that:**
1. Validates the caller is the authorized manager
2. Validates the target contract is in an approved strategy (whitelist)
3. Handles token approvals for the target contract
4. Executes the exact call data provided by the manager

## Architecture Components

### 1. **VaultFactory** (Trusted Contract Registry)
- Stores approved target contracts (whitelist)
- Manages single authorized manager
- Minimal configuration - just contract addresses and names

### 2. **Vault** (Secure Passthrough + Approval Handler)
- Executes any call data to approved target contracts
- Handles token approvals before contract calls
- Resets approvals on failure for security

## Key Benefits

### **Maximum Simplicity**
- No helper libraries to maintain
- No complex call data templating  
- Manager has full control over exact calls
- Just a whitelist of trusted contracts

### **Automatic Token Handling**
- Manager specifies which tokens need approval
- Vault handles approvals before contract calls
- Automatic approval reset on failed calls

### **Ultimate Flexibility**
- Supports any function on any protocol
- No predefined function signatures
- Complete runtime control

## Usage Examples

### 1. Adding Strategies (Factory Owner)

```solidity
// Add Aave V3 strategy - just the contract address
factory.addStrategy(
    keccak256("AAVE_V3"),
    "Aave V3 Pool",
    0x794a61358D6845594F94dc1DB02A252b5b4814aD // Aave V3 Pool address
);

// Add DEX strategy  
factory.addStrategy(
    keccak256("UNISWAP_V2"),
    "Uniswap V2 Router",
    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D // Uniswap V2 Router
);
```

### 2. Executing Strategies (Authorized Manager)

```solidity
// Aave V3 supply - needs USDC approval
bytes memory supplyCall = abi.encodeWithSignature(
    "supply(address,uint256,address,uint16)",
    usdcAddress, 100e6, vaultAddress, 0
);

// Specify token approval needed
Vault.TokenApproval[] memory approvals = new Vault.TokenApproval[](1);
approvals[0] = Vault.TokenApproval({
    token: usdcAddress,
    amount: 100e6
});

Vault(vault).executeStrategy(
    keccak256("AAVE_V3"), 
    supplyCall, 
    approvals
);

// Aave V3 withdraw - no approval needed
bytes memory withdrawCall = abi.encodeWithSignature(
    "withdraw(address,uint256,address)",
    usdcAddress, 50e6, vaultAddress
);

// No approvals needed
Vault.TokenApproval[] memory noApprovals = new Vault.TokenApproval[](0);

Vault(vault).executeStrategy(
    keccak256("AAVE_V3"), 
    withdrawCall, 
    noApprovals
);

// Uniswap swap - needs token approval
bytes memory swapCall = abi.encodeWithSignature(
    "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
    100e6, 95e6, path, vaultAddress, deadline
);

// Approve input token
Vault.TokenApproval[] memory swapApprovals = new Vault.TokenApproval[](1);
swapApprovals[0] = Vault.TokenApproval({
    token: inputToken,
    amount: 100e6
});

Vault(vault).executeStrategy(
    keccak256("UNISWAP_V2"), 
    swapCall, 
    swapApprovals
);
```

## Token Approval System

### **Automatic Approval Management**
- Manager specifies which tokens need approval and amounts
- Vault approves tokens to target contract before call
- Vault resets approvals to zero on failed calls
- No manual approval management needed

### **Approval Structure**
```solidity
struct TokenApproval {
    address token;    // Token to approve
    uint256 amount;   // Amount to approve
}
```

### **Examples by Protocol**

#### **Aave V3**
```solidity
// Supply (needs approval)
Vault.TokenApproval[] memory approvals = new Vault.TokenApproval[](1);
approvals[0] = Vault.TokenApproval(usdcAddress, 100e6);

// Withdraw (no approval needed)
Vault.TokenApproval[] memory noApprovals = new Vault.TokenApproval[](0);
```

#### **Uniswap V2**
```solidity
// Swap (needs input token approval)
Vault.TokenApproval[] memory approvals = new Vault.TokenApproval[](1);
approvals[0] = Vault.TokenApproval(inputTokenAddress, amountIn);
```

#### **Curve**
```solidity
// Add liquidity (needs approval for both tokens)
Vault.TokenApproval[] memory approvals = new Vault.TokenApproval[](2);
approvals[0] = Vault.TokenApproval(token0Address, amount0);
approvals[1] = Vault.TokenApproval(token1Address, amount1);
```

## Manager Implementation Example

```solidity
contract StrategyManager {
    VaultFactory public factory;
    
    function executeAaveSupply(
        address vault, 
        address asset, 
        uint256 amount
    ) external onlyOwner {
        // Encode Aave supply call
        bytes memory callData = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)",
            asset, amount, vault, 0
        );
        
        // Setup token approval
        Vault.TokenApproval[] memory approvals = new Vault.TokenApproval[](1);
        approvals[0] = Vault.TokenApproval(asset, amount);
        
        // Execute strategy
        Vault(vault).executeStrategy(
            keccak256("AAVE_V3"), 
            callData, 
            approvals
        );
    }
    
    function executeUniswapSwap(
        address vault,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path
    ) external onlyOwner {
        // Encode swap call
        bytes memory callData = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            amountIn, amountOutMin, path, vault, block.timestamp + 3600
        );
        
        // Setup token approval
        Vault.TokenApproval[] memory approvals = new Vault.TokenApproval[](1);
        approvals[0] = Vault.TokenApproval(tokenIn, amountIn);
        
        // Execute strategy
        Vault(vault).executeStrategy(
            keccak256("UNISWAP_V2"), 
            callData, 
            approvals
        );
    }
}
```

## Security Model

### **Factory Level** 
- Factory owner maintains whitelist of trusted contracts
- Factory owner sets authorized manager
- Only whitelisted contracts can be called

### **Vault Level**
- Only authorized manager can execute strategies
- Only whitelisted target contracts can be called
- Automatic approval management prevents stuck approvals
- Vault owner retains deposit/withdrawal control

### **Manager Level**
- Manager responsible for call data safety
- Manager specifies token approvals needed
- Manager handles protocol-specific requirements

## Error Handling

```solidity
error UnauthorizedManager();     // Caller not the authorized manager
error StrategyNotFound();        // Strategy doesn't exist  
error StrategyInactive();        // Strategy has been deactivated
error StrategyExecutionFailed(); // Protocol call failed
```

## Events

```solidity
event StrategyAdded(bytes32 indexed strategyId, string name, address targetContract);
event StrategyExecuted(bytes32 indexed strategyId, address indexed targetContract, bytes data);
event TokenApproved(address indexed token, address indexed spender, uint256 amount);
event ManagerSet(address indexed oldManager, address indexed newManager);
```

## Why This Final Approach?

### **Pure Simplicity**
- Strategies are just a whitelist of trusted contract addresses
- No complex configuration or call data storage
- Manager provides everything at runtime

### **Safe Token Handling**
- Automatic approval management
- No stuck approvals on failed calls
- Manager controls exact approval amounts

### **Maximum Security**
- Only whitelisted contracts can be called
- Only authorized manager can execute
- Failed calls reset approvals automatically

### **Zero Maintenance**
- No libraries to update
- No complex configuration to manage
- Works with any current or future protocol

This ultra-simplified approach treats the vault as a secure proxy with automatic token approval handling, giving the manager complete control while maintaining a minimal attack surface. 