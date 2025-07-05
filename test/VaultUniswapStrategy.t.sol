// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Vm } from "forge-std/Vm.sol";

import { Vault } from "../src/Vault.sol";
import { VaultFactory } from "../src/VaultFactory.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// --- Mainnet Fork Configuration ---
string constant ARBITRUM_RPC = "https://arbitrum-one-rpc.publicnode.com";

// --- Token Addresses (Arbitrum) ---
address constant USDC_ADDRESS = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // Arbitrum USDC
address constant WBTC_ADDRESS = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // Arbitrum WBTC

// --- Protocol Addresses (Arbitrum) ---
address constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // SwapRouter

contract VaultUniswapStrategyTest is Test {
    using SafeERC20 for IERC20;

    // --- Contract Instances ---
    VaultFactory public factory;
    Vault public vault;
    IERC20 public usdc = IERC20(USDC_ADDRESS);
    IERC20 public wbtc = IERC20(WBTC_ADDRESS);

    // --- Actors ---
    address public factoryOwner = makeAddr("factoryOwner");
    address public vaultOwner = makeAddr("vaultOwner");
    address public authorizedManager = makeAddr("authorizedManager");

    // --- Amounts ---
    uint256 constant USDC_DEPOSIT_AMOUNT = 0.01 * 1e6; // 0.01 USDC

    function setUp() public {
        // --- Fork Setup ---
        vm.createSelectFork(ARBITRUM_RPC);

        // --- Deploy Contracts ---
        Vault vaultImplementation = new Vault();
        VaultFactory factoryImplementation = new VaultFactory();

        bytes memory factoryInitData = abi.encodeWithSignature("initialize(address,address)", factoryOwner, address(vaultImplementation));
        ERC1967Proxy factoryProxy = new ERC1967Proxy(address(factoryImplementation), factoryInitData);
        factory = VaultFactory(address(factoryProxy));
        
        // --- Configure Roles ---
        vm.prank(factoryOwner);
        factory.setManager(authorizedManager);

        // --- Create Vault ---
        address vaultAddress = factory.deployVault(vaultOwner);
        vault = Vault(vaultAddress);

        // --- Fund User Account ---
        // Deal USDC to the vault owner for the deposit
        deal(USDC_ADDRESS, vaultOwner, USDC_DEPOSIT_AMOUNT);

        // --- User Deposits into Vault ---
        vm.startPrank(vaultOwner);
        usdc.approve(address(vault), USDC_DEPOSIT_AMOUNT);
        vault.deposit(USDC_ADDRESS, USDC_DEPOSIT_AMOUNT);
        vm.stopPrank();

        // --- Verification ---
        assertEq(usdc.balanceOf(address(vault)), USDC_DEPOSIT_AMOUNT, "Initial deposit failed");
    }

    function test_Swap_USDC_for_WBTC_Via_Vault() public {
        // --- Test Parameters ---
        uint256 amountIn = USDC_DEPOSIT_AMOUNT;
        uint256 amountOutMinimum = 0; // For simplicity, we don't check slippage in this test
        uint24 fee = 500; // 0.05% fee tier for USDC/WBTC

        // --- Prepare Calldata for exactInputSingle ---
        // Correctly encode as struct parameter (ExactInputSingleParams)
        bytes memory swapCalldata = abi.encodeWithSignature(
            "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
            USDC_ADDRESS,
            WBTC_ADDRESS,
            fee,
            address(vault), // Recipient is the vault itself
            block.timestamp,
            amountIn,
            amountOutMinimum,
            uint160(0)
        );

        // --- Prepare Approvals for executeStrategy ---
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](1);
        approvals[0] = IVault.TokenApproval({
            token: USDC_ADDRESS,
            amount: amountIn
        });

        // --- Pre-swap balances ---
        uint256 vaultUsdcBefore = usdc.balanceOf(address(vault));
        uint256 vaultWbtcBefore = wbtc.balanceOf(address(vault));
        
        console.log("Vault USDC before swap:", vaultUsdcBefore);
        console.log("Vault WBTC before swap:", vaultWbtcBefore);

        // --- Execute Swap as Authorized Manager ---
        vm.prank(authorizedManager);
        vault.executeStrategy(UNISWAP_V3_ROUTER, swapCalldata, approvals);

        // --- Post-swap balances ---
        uint256 vaultUsdcAfter = usdc.balanceOf(address(vault));
        uint256 vaultWbtcAfter = wbtc.balanceOf(address(vault));

        console.log("Vault USDC after swap:", vaultUsdcAfter);
        console.log("Vault WBTC after swap:", vaultWbtcAfter);

        // --- Assertions ---
        assertTrue(vaultUsdcAfter < vaultUsdcBefore, "USDC balance should decrease after swap");
        assertTrue(vaultWbtcAfter > vaultWbtcBefore, "WBTC balance should increase after swap");
        assertEq(vaultUsdcAfter, 0, "Vault should have spent all its USDC");
    }
}
