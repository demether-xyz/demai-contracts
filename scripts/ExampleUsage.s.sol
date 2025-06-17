// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/VaultFactory.sol";
import "../src/Vault.sol";

/**
 * @title ExampleUsage
 * @dev Example script showing how to use the ultra-simplified strategy architecture
 */
contract ExampleUsage is Script {
    VaultFactory public factory;
    address public factoryOwner;
    address public manager;
    address public user;

    // Arbitrum addresses
    address constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant USDC = 0xA0b86a33E6Fd6Ce4D0be5f981cd205e8dC20ba0e;

    function setUp() public {
        factoryOwner = vm.addr(1);
        manager = vm.addr(2);
        user = vm.addr(3);
    }

    function run() public {
        console.log("=== Ultra-Simplified Strategy Architecture Example ===");

        // 1. Deploy Factory (as factory owner)
        vm.startBroadcast(factoryOwner);

        Vault vaultImplementation = new Vault();
        factory = new VaultFactory();

        // Initialize factory with proxy pattern
        factory.initialize(factoryOwner, address(vaultImplementation));

        console.log("Factory deployed at:", address(factory));
        console.log("Vault implementation:", address(vaultImplementation));

        vm.stopBroadcast();

        // 2. Add Strategies (as factory owner)
        vm.startBroadcast(factoryOwner);

        // Add Aave V3 supply strategy
        bytes32 aaveSupplyId = keccak256("AAVE_V3_SUPPLY");
        factory.addStrategy(aaveSupplyId, "Aave V3 Supply", AAVE_V3_POOL);

        console.log("Added Aave V3 Supply strategy with ID:", vm.toString(aaveSupplyId));

        // Add Aave V3 withdraw strategy
        bytes32 aaveWithdrawId = keccak256("AAVE_V3_WITHDRAW");
        factory.addStrategy(aaveWithdrawId, "Aave V3 Withdraw", AAVE_V3_POOL);

        console.log("Added Aave V3 Withdraw strategy with ID:", vm.toString(aaveWithdrawId));

        // Add Uniswap swap strategy
        bytes32 swapStrategyId = keccak256("UNISWAP_SWAP");
        factory.addStrategy(
            swapStrategyId,
            "Uniswap Token Swap",
            address(0x1234) // Example DEX router address
        );

        console.log("Added Uniswap swap strategy with ID:", vm.toString(swapStrategyId));

        vm.stopBroadcast();

        // 3. Set Manager (as factory owner)
        vm.startBroadcast(factoryOwner);

        factory.setManager(manager);
        console.log("Set authorized manager:", manager);

        vm.stopBroadcast();

        // 4. Deploy User Vault (as user)
        vm.startBroadcast(user);

        address userVault = factory.deployVault(user);
        console.log("User vault deployed at:", userVault);

        vm.stopBroadcast();

        // 5. Simulate Strategy Execution (as manager)
        vm.startBroadcast(manager);

        console.log("Simulating strategy execution...");

        // Execute Aave V3 supply strategy - manager encodes call data directly
        bytes memory aaveSupplyCallData = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)",
            USDC, // asset
            100e6, // amount (100 USDC)
            userVault, // onBehalfOf (vault receives aTokens)
            0 // referralCode
        );

        // Create approval for USDC to Aave pool
        Vault.TokenApproval[] memory supplyApprovals = new Vault.TokenApproval[](1);
        supplyApprovals[0] = Vault.TokenApproval({ token: USDC, amount: 100e6 });

        try Vault(userVault).executeStrategy(aaveSupplyId, aaveSupplyCallData, supplyApprovals) {
            console.log("Aave V3 supply strategy execution would succeed");
        } catch Error(string memory reason) {
            console.log("Strategy execution would fail:", reason);
        }

        // Execute Aave V3 withdraw strategy (no approval needed for withdraws)
        bytes memory aaveWithdrawCallData = abi.encodeWithSignature(
            "withdraw(address,uint256,address)",
            USDC, // asset
            50e6, // amount (withdraw 50 USDC)
            userVault // to (vault receives tokens)
        );

        // No approvals needed for withdraw
        Vault.TokenApproval[] memory noApprovals = new Vault.TokenApproval[](0);

        try Vault(userVault).executeStrategy(aaveWithdrawId, aaveWithdrawCallData, noApprovals) {
            console.log("Aave V3 withdraw strategy execution would succeed");
        } catch Error(string memory reason) {
            console.log("Strategy execution would fail:", reason);
        }

        // Execute token swap - completely different protocol
        bytes memory swapCallData = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            100e6, // amountIn
            95e6, // amountOutMin
            getSwapPath(), // path
            userVault, // to
            block.timestamp + 3600 // deadline
        );

        // Create approval for USDC to DEX router
        Vault.TokenApproval[] memory swapApprovals = new Vault.TokenApproval[](1);
        swapApprovals[0] = Vault.TokenApproval({ token: USDC, amount: 100e6 });

        try Vault(userVault).executeStrategy(swapStrategyId, swapCallData, swapApprovals) {
            console.log("Uniswap swap strategy execution would succeed");
        } catch Error(string memory reason) {
            console.log("Strategy execution would fail:", reason);
        }

        vm.stopBroadcast();

        // 6. Show Strategy Information
        showStrategyInfo();

        console.log("=== Example Complete ===");
    }

    function getSwapPath() internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = 0xA0b86a33E6Fd6Ce4D0be5f981cd205e8dC20ba0e; // USDC
        path[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        return path;
    }

    function showStrategyInfo() public view {
        console.log("\n=== Strategy Information ===");

        // Get active strategies
        bytes32[] memory activeStrategies = factory.getActiveStrategies();
        console.log("Number of active strategies:", activeStrategies.length);

        for (uint i = 0; i < activeStrategies.length; i++) {
            VaultFactory.StrategyConfig memory strategy = factory.strategies(activeStrategies[i]);

            console.log("\nStrategy", i + 1);
            console.log("  ID:", vm.toString(activeStrategies[i]));
            console.log("  Name:", strategy.name);
            console.log("  Target Contract:", strategy.targetContract);
            console.log("  Active:", strategy.isActive);
            console.log("  Has Call Data:", strategy.callData.length > 0);
        }

        // Manager info
        console.log("\nManager Information:");
        console.log("  Authorized manager:", factory.authorizedManager());

        // User vault info
        console.log("\nUser Vault:");
        console.log("  User address:", user);
        console.log("  Vault address:", factory.getUserVault(user));
        console.log("  Has vault:", factory.hasVault(user));
    }

    function demonstrateCallDataExamples() public pure {
        console.log("\n=== Call Data Examples ===");

        // Aave V3 supply
        bytes memory aaveSupply = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)",
            0xA0b86a33E6Fd6Ce4D0be5f981cd205e8dC20ba0e, // USDC
            100e6,
            0x1234567890123456789012345678901234567890, // vault
            0
        );
        console.log("Aave V3 supply call data length:", aaveSupply.length);

        // Compound V3 supply
        bytes memory compoundSupply = abi.encodeWithSignature(
            "supply(address,uint256)",
            0xA0b86a33E6Fd6Ce4D0be5f981cd205e8dC20ba0e, // USDC
            100e6
        );
        console.log("Compound V3 supply call data length:", compoundSupply.length);

        // Uniswap V2 swap
        address[] memory path = new address[](2);
        path[0] = 0xA0b86a33E6Fd6Ce4D0be5f981cd205e8dC20ba0e; // USDC
        path[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH

        bytes memory uniswapSwap = abi.encodeWithSignature(
            "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)",
            100e6,
            95e6,
            path,
            0x1234567890123456789012345678901234567890, // vault
            block.timestamp + 3600
        );
        console.log("Uniswap swap call data length:", uniswapSwap.length);

        // Curve add liquidity
        uint256[2] memory amounts = [uint256(100e6), uint256(100e18)];
        bytes memory curveAddLiquidity = abi.encodeWithSignature(
            "add_liquidity(uint256[2],uint256)",
            amounts,
            190e18 // min_mint_amount
        );
        console.log("Curve add liquidity call data length:", curveAddLiquidity.length);
    }
}
