// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/VaultFactory.sol";
import "../src/Vault.sol";
import "../src/interfaces/IVault.sol";

contract ExecuteUniswapSwap is Script {
    using SafeERC20 for IERC20;

    // --- Deployed Contract Addresses (Arbitrum) ---
    address constant VAULT_FACTORY_ADDRESS = 0x5C97F0a08a1c8a3Ed6C1E1dB2f7Ce08a4BFE53C7;
    address constant AUTHORIZED_MANAGER = 0x55b3d73e525227A7F0b25e28e17c1E94006A25dd;

    // --- Token Addresses (Arbitrum) ---
    address constant USDC_ADDRESS = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant WBTC_ADDRESS = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

    // --- Protocol Addresses (Arbitrum) ---
    address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // --- Swap Parameters ---
    uint256 constant SWAP_AMOUNT = 0.01 * 1e6; // 0.01 USDC
    uint24 constant POOL_FEE = 500; // 0.05% fee tier

    function run() external {
        console.log("=== Executing Uniswap Swap on Arbitrum ===" );

        // Get the private key and derive the address
        uint256 managerPrivateKey = vm.envUint("PRIVATE_KEY");
        address manager = vm.addr(managerPrivateKey);

        console.log("Manager Address:");
        console.logAddress(manager);
        console.log("Chain ID:");
        console.logUint(block.chainid);

        // Verify we're on Arbitrum
        require(block.chainid == 42161, "This script is for Arbitrum only");

        // Connect to the VaultFactory
        VaultFactory vaultFactory = VaultFactory(VAULT_FACTORY_ADDRESS);
        console.log("VaultFactory Address:");
        console.logAddress(VAULT_FACTORY_ADDRESS);

        // Verify manager is authorized
        address currentManager = vaultFactory.authorizedManager();
        console.log("Current Authorized Manager:");
        console.logAddress(currentManager);

        require(currentManager == manager, "Caller is not the authorized manager");

        // Get the existing vault for the manager
        address vaultAddress = vaultFactory.predictVaultAddress(manager);
        require(vaultAddress != address(0), "No vault exists for this manager");
        Vault vault = Vault(vaultAddress);
        
        console.log("Vault Address:");
        console.logAddress(vaultAddress);

        // Get token interfaces
        IERC20 usdc = IERC20(USDC_ADDRESS);
        IERC20 wbtc = IERC20(WBTC_ADDRESS);

        // Check manager's USDC balance
        uint256 managerUsdcBalance = usdc.balanceOf(manager);
        console.log("Manager USDC Balance:");
        console.logUint(managerUsdcBalance);

        require(managerUsdcBalance >= SWAP_AMOUNT, "Insufficient USDC balance");

        vm.startBroadcast(managerPrivateKey);

        // Step 1: Deposit USDC into the vault
        console.log("\n--- Depositing USDC into Vault ---");
        usdc.approve(vaultAddress, SWAP_AMOUNT);
        vault.deposit(USDC_ADDRESS, SWAP_AMOUNT);

        // Verify deposit
        uint256 vaultUsdcBalance = usdc.balanceOf(vaultAddress);
        console.log("Vault USDC Balance after deposit:");
        console.logUint(vaultUsdcBalance);

        // Step 2: Prepare swap calldata
        console.log("\n--- Preparing Swap Parameters ---");
        bytes memory swapCalldata = abi.encodeWithSignature(
            "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
            USDC_ADDRESS,
            WBTC_ADDRESS,
            POOL_FEE,
            vaultAddress, // Recipient is the vault
            block.timestamp + 300, // Add 5 minutes buffer
            SWAP_AMOUNT,
            0, // amountOutMinimum = 0 for simplicity
            uint160(0) // sqrtPriceLimitX96 = 0 for no price limit
        );

        // Step 3: Prepare token approvals
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](1);
        approvals[0] = IVault.TokenApproval({
            token: USDC_ADDRESS,
            amount: SWAP_AMOUNT
        });

        // Step 4: Execute the swap
        console.log("\n--- Executing Swap ---");
        uint256 vaultWbtcBefore = wbtc.balanceOf(vaultAddress);
        console.log("Vault WBTC Balance before swap:");
        console.logUint(vaultWbtcBefore);

        vault.executeStrategy(UNISWAP_V3_ROUTER, swapCalldata, approvals);

        // Step 5: Verify swap results
        uint256 vaultUsdcAfter = usdc.balanceOf(vaultAddress);
        uint256 vaultWbtcAfter = wbtc.balanceOf(vaultAddress);

        console.log("\n--- Swap Results ---");
        console.log("Vault USDC Balance after swap:");
        console.logUint(vaultUsdcAfter);
        console.log("Vault WBTC Balance after swap:");
        console.logUint(vaultWbtcAfter);

        // Verify the swap was successful
        require(vaultUsdcAfter < vaultUsdcBalance, "USDC balance should decrease");
        require(vaultWbtcAfter > vaultWbtcBefore, "WBTC balance should increase");

        console.log("\n--- Swap Summary ---");
        console.log("USDC Spent:");
        console.logUint(vaultUsdcBalance - vaultUsdcAfter);
        console.log("WBTC Received:");
        console.logUint(vaultWbtcAfter - vaultWbtcBefore);

        vm.stopBroadcast();

        console.log("\n=== Swap Execution Complete ===");
        console.log("SUCCESS: USDC to WBTC swap executed successfully");
        console.log("Vault Address: ", vaultAddress);
        console.log("Final USDC Balance: ", vaultUsdcAfter);
        console.log("Final WBTC Balance: ", vaultWbtcAfter);
    }
}
