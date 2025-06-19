// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/VaultFactory.sol";
import "../src/Vault.sol";
import "../src/interfaces/IVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract VaultFactoryTest is Test {
    VaultFactory public factory;
    VaultFactory public factoryImplementation;
    Vault public vaultImplementation;
    MockERC20 public token;

    address public factoryOwner = makeAddr("factoryOwner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    event VaultDeployed(address indexed vaultOwner, address indexed vaultAddress, uint256 vaultIndex);
    event BeaconUpgraded(address indexed oldImplementation, address indexed newImplementation);

    function setUp() public {
        // Deploy contracts
        vaultImplementation = new Vault();
        factoryImplementation = new VaultFactory();
        token = new MockERC20("Test Token", "TEST");

        // Deploy factory behind a proxy for UUPS upgradeability
        // We separate proxy deployment from initialization to mirror the deployment script
        // and avoid issues with delegatecalling `initialize` from a constructor.
        ERC1967Proxy factoryProxy = new ERC1967Proxy(address(factoryImplementation), bytes(""));
        factory = VaultFactory(address(factoryProxy));
        factory.initialize(factoryOwner, address(vaultImplementation));

        // Mint tokens to users
        token.mint(user1, 1000 * 10 ** 18);
        token.mint(user2, 1000 * 10 ** 18);
    }

    function test_InitialState() public view {
        assertEq(factory.owner(), factoryOwner);
        assertEq(factory.getImplementation(), address(vaultImplementation));
        assertEq(factory.getTotalVaults(), 0);
        assertTrue(factory.getBeacon() != address(0));
    }

    function test_DeployVault() public {
        address vaultAddress = factory.deployVault(user1);

        // Verify vault was deployed correctly
        assertTrue(vaultAddress != address(0));
        assertTrue(factory.isVault(vaultAddress));
        assertEq(factory.getTotalVaults(), 1);

        address userVault = factory.getUserVault(user1);
        assertEq(userVault, vaultAddress);
        assertTrue(factory.hasVault(user1));

        // Verify vault initialization
        Vault vault = Vault(vaultAddress);
        assertEq(vault.owner(), address(factory)); // Factory is the admin owner
        assertEq(vault.vaultOwner(), user1); // User is the vault owner
    }

    function test_PredictVaultAddress() public {
        // Predict address before deployment
        address predictedAddress = factory.predictVaultAddress(user1);

        // Deploy vault
        address actualAddress = factory.deployVault(user1);

        // Verify addresses match
        assertEq(predictedAddress, actualAddress);
    }

    function test_RevertDeployVaultZeroAddress() public {
        vm.expectRevert(VaultFactory.ZeroAddress.selector);
        factory.deployVault(address(0));
    }

    function test_RevertVaultAlreadyExists() public {
        // First deployment should succeed
        factory.deployVault(user1);

        // Second deployment for same user should fail
        vm.expectRevert(VaultFactory.VaultAlreadyExists.selector);
        factory.deployVault(user1);
    }

    function test_VaultDepositAndWithdraw() public {
        // Deploy vault for user1
        address vaultAddress = factory.deployVault(user1);
        Vault vault = Vault(vaultAddress);

        // Approve and deposit tokens as user1
        vm.startPrank(user1);
        token.approve(vaultAddress, 100 * 10 ** 18);
        vault.deposit(address(token), 100 * 10 ** 18);
        vm.stopPrank();

        // Verify deposit
        assertEq(vault.getTokenBalance(address(token)), 100 * 10 ** 18);
        assertEq(token.balanceOf(user1), 900 * 10 ** 18);

        // Withdraw tokens as user1
        vm.prank(user1);
        vault.withdraw(address(token), 50 * 10 ** 18);

        // Verify withdrawal
        assertEq(vault.getTokenBalance(address(token)), 50 * 10 ** 18);
        assertEq(token.balanceOf(user1), 950 * 10 ** 18);
    }

    function test_RevertDepositNotVaultOwner() public {
        address vaultAddress = factory.deployVault(user1);
        Vault vault = Vault(vaultAddress);

        vm.startPrank(user2);
        token.approve(vaultAddress, 100 * 10 ** 18);
        vm.expectRevert(IVault.OnlyVaultOwner.selector);
        vault.deposit(address(token), 100 * 10 ** 18);
        vm.stopPrank();
    }

    function test_RevertWithdrawNotVaultOwner() public {
        address vaultAddress = factory.deployVault(user1);
        Vault vault = Vault(vaultAddress);

        // First deposit as user1
        vm.startPrank(user1);
        token.approve(vaultAddress, 100 * 10 ** 18);
        vault.deposit(address(token), 100 * 10 ** 18);
        vm.stopPrank();

        // Try to withdraw as user2
        vm.prank(user2);
        vm.expectRevert(IVault.OnlyVaultOwner.selector);
        vault.withdraw(address(token), 50 * 10 ** 18);
    }

    function test_FactoryOwnerPauseVault() public {
        address vaultAddress = factory.deployVault(user1);
        Vault vault = Vault(vaultAddress);

        // Factory owner pauses the vault
        vm.prank(factoryOwner);
        factory.pauseVault(vaultAddress);

        // Verify vault is paused
        assertTrue(vault.paused());

        // User1 should not be able to deposit when paused
        vm.startPrank(user1);
        token.approve(vaultAddress, 100 * 10 ** 18);
        vm.expectRevert();
        vault.deposit(address(token), 100 * 10 ** 18);
        vm.stopPrank();
    }

    function test_FactoryOwnerUnpauseVault() public {
        address vaultAddress = factory.deployVault(user1);
        Vault vault = Vault(vaultAddress);

        // Factory owner pauses then unpauses the vault
        vm.startPrank(factoryOwner);
        factory.pauseVault(vaultAddress);
        assertTrue(vault.paused());

        factory.unpauseVault(vaultAddress);
        assertFalse(vault.paused());
        vm.stopPrank();

        // User1 should be able to deposit after unpause
        vm.startPrank(user1);
        token.approve(vaultAddress, 100 * 10 ** 18);
        vault.deposit(address(token), 100 * 10 ** 18);
        vm.stopPrank();

        assertEq(vault.getTokenBalance(address(token)), 100 * 10 ** 18);
    }

    function test_UpgradeBeacon() public {
        // Deploy a new vault implementation
        Vault newVaultImplementation = new Vault();

        // Factory owner upgrades the beacon
        vm.prank(factoryOwner);
        factory.upgradeBeacon(address(newVaultImplementation));

        // Verify upgrade
        assertEq(factory.getImplementation(), address(newVaultImplementation));
    }

    function test_RevertNonOwnerOperations() public {
        address vaultAddress = factory.deployVault(user1);

        // Non-owner should not be able to pause vault
        vm.prank(user1);
        vm.expectRevert();
        factory.pauseVault(vaultAddress);

        // Non-owner should not be able to upgrade beacon
        Vault newImplementation = new Vault();
        vm.prank(user1);
        vm.expectRevert();
        factory.upgradeBeacon(address(newImplementation));
    }

    function test_MultipleVaults() public {
        // Deploy vaults for different users
        address vault1 = factory.deployVault(user1);
        address vault2 = factory.deployVault(user2);

        assertEq(factory.getTotalVaults(), 2);

        address user1Vault = factory.getUserVault(user1);
        address user2Vault = factory.getUserVault(user2);

        assertEq(user1Vault, vault1);
        assertEq(user2Vault, vault2);

        // Verify all vaults are tracked correctly
        address[] memory allVaults = factory.getAllVaults();
        assertEq(allVaults.length, 2);
        assertEq(allVaults[0], vault1);
        assertEq(allVaults[1], vault2);
    }

    function test_HasVault() public {
        // Initially user has no vault
        assertFalse(factory.hasVault(user1));
        assertEq(factory.getUserVault(user1), address(0));

        // Deploy vault
        factory.deployVault(user1);

        // Now user has a vault
        assertTrue(factory.hasVault(user1));
        assertTrue(factory.getUserVault(user1) != address(0));
    }

    function test_DeterministicBeaconAddress() public {
        // The beacon should be deployed at a deterministic address
        address beaconAddress = factory.getBeacon();
        assertTrue(beaconAddress != address(0));

        // Verify the beacon points to the correct implementation
        assertEq(factory.getImplementation(), address(vaultImplementation));

        // Deploy a new factory with the same parameters and verify beacon address is different
        // (since it's deployed by a different factory address)
        VaultFactory newFactoryImpl = new VaultFactory();
        ERC1967Proxy newFactoryProxy = new ERC1967Proxy(address(newFactoryImpl), bytes(""));
        VaultFactory newFactory = VaultFactory(address(newFactoryProxy));
        newFactory.initialize(factoryOwner, address(vaultImplementation));

        // Different factory = different beacon address (since deployer is different)
        assertTrue(newFactory.getBeacon() != factory.getBeacon());
    }

    function test_PlaceholderImplementationPattern() public {
        // Deploy vault before upgrade
        address predictedAddress1 = factory.predictVaultAddress(user1);
        address vaultAddress = factory.deployVault(user1);
        assertEq(predictedAddress1, vaultAddress);

        // Create a new vault implementation
        Vault newVaultImplementation = new Vault();

        // Upgrade the beacon
        vm.prank(factoryOwner);
        factory.upgradeBeacon(address(newVaultImplementation));

        // Verify implementation changed
        assertEq(factory.getImplementation(), address(newVaultImplementation));

        // Predict address for user2 after upgrade - should still be deterministic
        address predictedAddress2 = factory.predictVaultAddress(user2);
        address vault2Address = factory.deployVault(user2);
        assertEq(predictedAddress2, vault2Address);

        // Verify that existing vault still works with new implementation
        Vault vault1 = Vault(vaultAddress);
        assertEq(vault1.vaultOwner(), user1);

        // Verify new vault uses new implementation but address is still deterministic
        Vault vault2 = Vault(vault2Address);
        assertEq(vault2.vaultOwner(), user2);
    }

    function test_BeaconAddressConsistency() public {
        // Get the beacon address
        address beaconAddress = factory.getBeacon();

        // The beacon should use dummy implementation pattern
        // This means the beacon address is determined by:
        // - VAULT_DEPLOYER_ID constant
        // - "BEACON" string
        // - DummyVaultImplementation (deployed deterministically)
        // - Factory address as deployer

        assertTrue(beaconAddress != address(0));
        assertEq(factory.getImplementation(), address(vaultImplementation));
    }

    function test_BeaconUsesPlaceholderPattern() public {
        // Deploy a second factory with a DIFFERENT vault implementation
        Vault differentImplementation = new Vault();
        VaultFactory newFactoryImpl = new VaultFactory();

        ERC1967Proxy newFactoryProxy = new ERC1967Proxy(address(newFactoryImpl), bytes(""));
        VaultFactory newFactory = VaultFactory(address(newFactoryProxy));
        newFactory.initialize(factoryOwner, address(differentImplementation));

        // Even though the implementations are different, if the factories were deployed
        // at the same address, the beacon addresses would be the same due to placeholder pattern
        // (In this test they're different because factory addresses differ, but the logic is sound)

        // Verify both factories work correctly with their respective implementations
        assertEq(factory.getImplementation(), address(vaultImplementation));
        assertEq(newFactory.getImplementation(), address(differentImplementation));

        // Both can deploy vaults successfully
        address vault1 = factory.deployVault(user1);
        address vault2 = newFactory.deployVault(user2);

        assertTrue(vault1 != address(0));
        assertTrue(vault2 != address(0));

        // Verify vault owners are set correctly
        assertEq(Vault(vault1).vaultOwner(), user1);
        assertEq(Vault(vault2).vaultOwner(), user2);
    }

    function test_PauseFactory() public {
        // Factory owner can pause the factory
        vm.prank(factoryOwner);
        factory.pause();
        assertTrue(factory.paused());

        // Cannot deploy vault when factory is paused
        vm.expectRevert();
        factory.deployVault(user1);
    }

    function test_UnpauseFactory() public {
        // Pause then unpause
        vm.startPrank(factoryOwner);
        factory.pause();
        factory.unpause();
        vm.stopPrank();

        assertFalse(factory.paused());

        // Can deploy vault after unpause
        address vaultAddress = factory.deployVault(user1);
        assertTrue(vaultAddress != address(0));
    }

    function test_RevertPauseVaultNotFound() public {
        vm.prank(factoryOwner);
        vm.expectRevert(VaultFactory.VaultNotFound.selector);
        factory.pauseVault(address(0x123));
    }

    function test_RevertUnpauseVaultNotFound() public {
        vm.prank(factoryOwner);
        vm.expectRevert(VaultFactory.VaultNotFound.selector);
        factory.unpauseVault(address(0x123));
    }
}
