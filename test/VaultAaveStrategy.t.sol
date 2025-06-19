// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/VaultFactory.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IVault } from "../src/interfaces/IVault.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

// Mock aToken (interest bearing token from Aave)
contract MockAToken is ERC20 {
    IERC20 public immutable underlyingAsset;
    uint256 public exchangeRate = 1e18; // 1:1 initially

    constructor(string memory name, string memory symbol, address _underlyingAsset) ERC20(name, symbol) {
        underlyingAsset = IERC20(_underlyingAsset);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setExchangeRate(uint256 _rate) external {
        exchangeRate = _rate;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return (super.balanceOf(account) * exchangeRate) / 1e18;
    }
}

// Mock Aave Pool contract
contract MockAavePool {
    mapping(address => address) public aTokens;
    mapping(address => uint256) public reserves;

    event Supply(address indexed asset, uint256 amount, address indexed onBehalfOf, uint16 referralCode);
    event Withdraw(address indexed asset, uint256 amount, address indexed to);

    function setAToken(address asset, address aToken) external {
        aTokens[asset] = aToken;
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        require(aTokens[asset] != address(0), "aToken not set");

        // Transfer underlying asset from caller (strategy manager gets approval from vault)
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Mint aTokens to the onBehalfOf address (the vault)
        MockAToken(aTokens[asset]).mint(onBehalfOf, amount);

        // Update reserves
        reserves[asset] += amount;

        emit Supply(asset, amount, onBehalfOf, referralCode);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(aTokens[asset] != address(0), "aToken not set");
        require(reserves[asset] >= amount, "Insufficient reserves");

        // Burn aTokens from caller
        MockAToken(aTokens[asset]).burn(msg.sender, amount);

        // Transfer underlying asset to recipient
        IERC20(asset).transfer(to, amount);

        // Update reserves
        reserves[asset] -= amount;

        emit Withdraw(asset, amount, to);

        return amount;
    }

    function getReserveData(address asset) external view returns (uint256) {
        return reserves[asset];
    }
}

// Strategy Manager contract to handle Aave interactions
contract AaveStrategyManager {
    MockAavePool public immutable aavePool;

    constructor(address _aavePool) {
        aavePool = MockAavePool(_aavePool);
    }

    function supplyToAave(address asset, uint256 amount, address onBehalfOf) external {
        // Transfer tokens from the vault to this contract first
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Approve the pool to spend our tokens
        IERC20(asset).approve(address(aavePool), amount);

        // Supply to Aave on behalf of the vault
        aavePool.supply(asset, amount, onBehalfOf, 0);
    }

    function withdrawFromAave(address asset, uint256 amount, address to) external returns (uint256) {
        // Get the corresponding aToken
        address aToken = aavePool.aTokens(asset);
        require(aToken != address(0), "aToken not found");

        // Transfer aTokens from the vault to this contract first
        IERC20(aToken).transferFrom(msg.sender, address(this), amount);

        // Call withdraw on the pool (this will burn our aTokens and send underlying to 'to')
        return aavePool.withdraw(asset, amount, to);
    }
}

contract VaultAaveStrategyTest is Test {
    VaultFactory public factory;
    Vault public vault;
    MockERC20 public usdc;
    MockAToken public aUSDC;
    MockAavePool public aavePool;
    AaveStrategyManager public strategyManager;

    address public factoryOwner = makeAddr("factoryOwner");
    address public vaultOwner = makeAddr("vaultOwner");
    address public authorizedManager = makeAddr("authorizedManager");

    // Events
    event TokenDeposited(address indexed token, uint256 amount);
    event TokenWithdrawn(address indexed token, uint256 amount);
    event StrategyExecuted(address indexed targetContract, bytes data);
    event TokenApproved(address indexed token, address indexed spender, uint256 amount);

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC");
        aUSDC = new MockAToken("Aave USDC", "aUSDC", address(usdc));

        // Deploy mock Aave pool
        aavePool = new MockAavePool();
        aavePool.setAToken(address(usdc), address(aUSDC));

        // Deploy strategy manager
        strategyManager = new AaveStrategyManager(address(aavePool));

        // Deploy vault implementation and factory
        Vault vaultImplementation = new Vault();
        VaultFactory factoryImplementation = new VaultFactory();

        // Deploy factory behind a proxy
        bytes memory initData = abi.encodeWithSignature("initialize(address,address)", factoryOwner, address(vaultImplementation));

        ERC1967Proxy factoryProxy = new ERC1967Proxy(address(factoryImplementation), initData);
        factory = VaultFactory(address(factoryProxy));

        // Set authorized manager
        vm.prank(factoryOwner);
        factory.setManager(authorizedManager);

        // Create vault for user
        address vaultAddress = factory.deployVault(vaultOwner);
        vault = Vault(vaultAddress);

        // Mint tokens to vault owner
        usdc.mint(vaultOwner, 10000 * 10 ** 6); // 10,000 USDC
    }

    function test_AaveStrategyFullFlow() public {
        uint256 depositAmount = 1000 * 10 ** 6; // 1,000 USDC
        uint256 supplyAmount = 800 * 10 ** 6; // 800 USDC to Aave
        uint256 withdrawAmount = 500 * 10 ** 6; // 500 USDC from Aave

        // Step 1: User deposits USDC into vault
        vm.startPrank(vaultOwner);
        usdc.approve(address(vault), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit TokenDeposited(address(usdc), depositAmount);

        vault.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        // Verify deposit
        assertEq(vault.getTokenBalance(address(usdc)), depositAmount);
        assertEq(usdc.balanceOf(address(vault)), depositAmount);
        assertEq(usdc.balanceOf(vaultOwner), 10000 * 10 ** 6 - depositAmount);

        // Step 2: Authorized manager executes strategy to supply to Aave
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](1);
        approvals[0] = IVault.TokenApproval({ token: address(usdc), amount: supplyAmount });

        bytes memory supplyData = abi.encodeWithSignature("supplyToAave(address,uint256,address)", address(usdc), supplyAmount, address(vault));

        vm.prank(authorizedManager);

        vm.expectEmit(true, true, false, true);
        emit TokenApproved(address(usdc), address(strategyManager), supplyAmount);

        vm.expectEmit(true, false, false, true);
        emit StrategyExecuted(address(strategyManager), supplyData);

        vault.executeStrategy(address(strategyManager), supplyData, approvals);

        // Verify supply to Aave
        assertEq(vault.getTokenBalance(address(usdc)), depositAmount - supplyAmount); // Remaining USDC in vault
        assertEq(aUSDC.balanceOf(address(vault)), supplyAmount); // aUSDC received
        assertEq(aavePool.getReserveData(address(usdc)), supplyAmount); // USDC in Aave reserves
        assertEq(usdc.balanceOf(address(aavePool)), supplyAmount); // USDC transferred to Aave

        // Step 3: Simulate some yield accrual by increasing aToken exchange rate
        aUSDC.setExchangeRate(1.1e18); // 10% yield

        // Verify yield accrual
        uint256 expectedATokenBalance = (supplyAmount * 1.1e18) / 1e18;
        assertEq(aUSDC.balanceOf(address(vault)), expectedATokenBalance);

        // Step 4: Authorized manager executes strategy to withdraw from Aave
        IVault.TokenApproval[] memory withdrawApprovals = new IVault.TokenApproval[](1);
        withdrawApprovals[0] = IVault.TokenApproval({ token: address(aUSDC), amount: withdrawAmount });

        bytes memory withdrawData = abi.encodeWithSignature("withdrawFromAave(address,uint256,address)", address(usdc), withdrawAmount, address(vault));

        vm.prank(authorizedManager);
        vault.executeStrategy(address(strategyManager), withdrawData, withdrawApprovals);

        // Verify withdrawal from Aave
        assertEq(vault.getTokenBalance(address(usdc)), depositAmount - supplyAmount + withdrawAmount); // USDC back in vault
        assertEq(aUSDC.balanceOf(address(vault)), ((supplyAmount - withdrawAmount) * 1.1e18) / 1e18); // aUSDC burned, accounting for exchange rate
        assertEq(aavePool.getReserveData(address(usdc)), supplyAmount - withdrawAmount); // Reduced Aave reserves

        // Step 5: User withdraws all USDC from vault
        uint256 finalVaultBalance = vault.getTokenBalance(address(usdc));

        vm.prank(vaultOwner);
        vm.expectEmit(true, false, false, true);
        emit TokenWithdrawn(address(usdc), finalVaultBalance);

        vault.withdraw(address(usdc), finalVaultBalance);

        // Verify final state
        assertEq(vault.getTokenBalance(address(usdc)), 0);
        assertEq(usdc.balanceOf(vaultOwner), 10000 * 10 ** 6 - (supplyAmount - withdrawAmount)); // Original minus what's still in Aave
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    function test_RevertStrategyExecutionUnauthorized() public {
        uint256 depositAmount = 1000 * 10 ** 6;

        // User deposits USDC into vault
        vm.startPrank(vaultOwner);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        // Non-authorized user tries to execute strategy
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](1);
        approvals[0] = IVault.TokenApproval({ token: address(usdc), amount: 500 * 10 ** 6 });

        bytes memory supplyData = abi.encodeWithSignature("supplyToAave(address,uint256,address)", address(usdc), 500 * 10 ** 6, address(vault));

        vm.prank(vaultOwner);
        vm.expectRevert(IVault.OnlyAuthorizedManager.selector);
        vault.executeStrategy(address(strategyManager), supplyData, approvals);
    }

    function test_RevertStrategyExecutionZeroAddress() public {
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](0);
        bytes memory data = "";

        vm.prank(authorizedManager);
        vm.expectRevert(IVault.ZeroAddress.selector);
        vault.executeStrategy(address(0), data, approvals);
    }

    function test_RevertStrategyExecutionWhenPaused() public {
        uint256 depositAmount = 1000 * 10 ** 6;

        // User deposits USDC into vault
        vm.startPrank(vaultOwner);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        // Factory owner pauses the vault through the factory
        vm.prank(factoryOwner);
        factory.pauseVault(address(vault));

        // Try to execute strategy on paused vault
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](1);
        approvals[0] = IVault.TokenApproval({ token: address(usdc), amount: 500 * 10 ** 6 });

        bytes memory supplyData = abi.encodeWithSignature("supplyToAave(address,uint256,address)", address(usdc), 500 * 10 ** 6, address(vault));

        vm.prank(authorizedManager);
        vm.expectRevert();
        vault.executeStrategy(address(strategyManager), supplyData, approvals);
    }

    function test_StrategyExecutionWithMultipleTokenApprovals() public {
        // Deploy second token
        MockERC20 dai = new MockERC20("DAI", "DAI");
        MockAToken aDAI = new MockAToken("Aave DAI", "aDAI", address(dai));
        aavePool.setAToken(address(dai), address(aDAI));

        uint256 usdcAmount = 1000 * 10 ** 6;
        uint256 daiAmount = 1000 * 10 ** 18;

        // Mint and deposit both tokens
        dai.mint(vaultOwner, 5000 * 10 ** 18);

        vm.startPrank(vaultOwner);
        usdc.approve(address(vault), usdcAmount);
        vault.deposit(address(usdc), usdcAmount);

        dai.approve(address(vault), daiAmount);
        vault.deposit(address(dai), daiAmount);
        vm.stopPrank();

        // Create strategy with multiple token approvals
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](2);
        approvals[0] = IVault.TokenApproval({ token: address(usdc), amount: 500 * 10 ** 6 });
        approvals[1] = IVault.TokenApproval({ token: address(dai), amount: 500 * 10 ** 18 });

        // Execute strategy for USDC
        bytes memory supplyData = abi.encodeWithSignature("supplyToAave(address,uint256,address)", address(usdc), 500 * 10 ** 6, address(vault));

        vm.prank(authorizedManager);
        vault.executeStrategy(address(strategyManager), supplyData, approvals);

        // Verify USDC was supplied to Aave
        assertEq(vault.getTokenBalance(address(usdc)), usdcAmount - 500 * 10 ** 6);
        assertEq(aUSDC.balanceOf(address(vault)), 500 * 10 ** 6);

        // Verify DAI approval was set but not used
        assertEq(vault.getTokenBalance(address(dai)), daiAmount);
        assertEq(dai.allowance(address(vault), address(strategyManager)), 500 * 10 ** 18);
    }

    function test_StrategyExecutionWithZeroApproval() public {
        uint256 depositAmount = 1000 * 10 ** 6;

        // User deposits USDC into vault
        vm.startPrank(vaultOwner);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        // Create approvals with zero amount (should be skipped)
        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](2);
        approvals[0] = IVault.TokenApproval({ token: address(usdc), amount: 500 * 10 ** 6 });
        approvals[1] = IVault.TokenApproval({
            token: address(usdc),
            amount: 0 // This should be skipped
        });

        bytes memory supplyData = abi.encodeWithSignature("supplyToAave(address,uint256,address)", address(usdc), 500 * 10 ** 6, address(vault));

        vm.prank(authorizedManager);
        vault.executeStrategy(address(strategyManager), supplyData, approvals);

        // Verify strategy executed successfully
        assertEq(vault.getTokenBalance(address(usdc)), depositAmount - 500 * 10 ** 6);
        assertEq(aUSDC.balanceOf(address(vault)), 500 * 10 ** 6);
    }

    function test_GetTokenBalanceAfterStrategyExecution() public {
        uint256 depositAmount = 1000 * 10 ** 6;
        uint256 supplyAmount = 600 * 10 ** 6;

        // Deposit and supply to Aave
        vm.startPrank(vaultOwner);
        usdc.approve(address(vault), depositAmount);
        vault.deposit(address(usdc), depositAmount);
        vm.stopPrank();

        IVault.TokenApproval[] memory approvals = new IVault.TokenApproval[](1);
        approvals[0] = IVault.TokenApproval({ token: address(usdc), amount: supplyAmount });

        bytes memory supplyData = abi.encodeWithSignature("supplyToAave(address,uint256,address)", address(usdc), supplyAmount, address(vault));

        vm.prank(authorizedManager);
        vault.executeStrategy(address(strategyManager), supplyData, approvals);

        // Verify balances through getter functions
        assertEq(vault.getTokenBalance(address(usdc)), depositAmount - supplyAmount);
        assertEq(vault.getTokenBalance(address(aUSDC)), supplyAmount);

        // Verify factory and vault owner relationships
        assertEq(vault.getFactory(), address(factory));
        assertEq(vault.vaultOwner(), vaultOwner);
    }
}
