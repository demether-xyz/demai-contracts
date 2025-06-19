// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IVaultFactory } from "./interfaces/IVaultFactory.sol";

/**
 * @title VaultFactory
 * @dev Factory contract for deploying and managing Vault contracts using beacon pattern
 * @dev Implements UUPSUpgradeable for factory upgradeability
 * @dev Controls administrative functions (pause/unpause, upgrades) while users control their deposits/withdrawals
 * @dev Uses CREATE2 for deterministic vault addresses across chains
 * @dev Each user can only have one vault per chain
 * @dev Manages single authorized manager for strategy execution
 * @dev CROSS-CHAIN STRATEGY: Deploy factories at the same address using CREATE2 for true determinism
 */
contract VaultFactory is IVaultFactory, Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /// @dev The beacon contract that holds the implementation address
    UpgradeableBeacon public beacon;

    /// @dev Mapping of vault owner to their single vault address
    mapping(address => address) public userVault;

    /// @dev Mapping to check if an address is a vault deployed by this factory
    mapping(address => bool) public isVault;

    /// @dev Array of all deployed vaults
    address[] public allVaults;

    /// @dev Single authorized manager who can execute strategies
    address public authorizedManager;

    /// @dev Fixed identifier for cross-chain vault address consistency
    /// @dev This ensures vault addresses are predictable across chains when factories have same address
    bytes32 public constant VAULT_DEPLOYER_ID = keccak256("DEMAI_VAULT_FACTORY_V1");

    /// @dev Fixed dummy implementation bytecode that never changes across vault versions
    /// @dev This is a minimal contract that just returns true for any call
    /// @dev Bytecode: constructor + runtime code for a contract that does nothing
    bytes public constant FIXED_DUMMY_BYTECODE =
        hex"608060405234801561001057600080fd5b5060358061001f6000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c806301ffc9a714602d575b600080fd5b60336047565b604051603e9190604e565b60405180910390f35b60006001905090565b605d81606a565b82525050565b6000602082019050607660008301846054565b92915050565b6000819050919050565b607b81607c565b8114608557600080fd5b5056fea2646970667358221220d1a9e8f7c6b5a4d3c2b1a0e9f8c7b6a5d4c3b2a1e0f9d8c7b6a5d4c3b2a164736f6c63430008130033";

    /// @dev Events
    event VaultDeployed(address indexed vaultOwner, address indexed vaultAddress, uint256 vaultIndex);
    event BeaconUpgraded(address indexed oldImplementation, address indexed newImplementation);
    event VaultPaused(address indexed vault);
    event VaultUnpaused(address indexed vault);
    event ManagerSet(address indexed oldManager, address indexed newManager);

    /// @dev Errors
    error ZeroAddress();
    error VaultNotFound();
    error BeaconNotSet();
    error VaultAlreadyExists();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the factory contract
     * @param _owner The owner of the factory
     * @param _vaultImplementation The initial vault implementation address
     */
    function initialize(address _owner, address _vaultImplementation) public initializer {
        if (_owner == address(0)) revert ZeroAddress();
        if (_vaultImplementation == address(0)) revert ZeroAddress();

        __UUPSUpgradeable_init();
        __Ownable_init();
        _transferOwnership(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();

        // Deploy fixed dummy implementation using hardcoded bytecode
        // This bytecode NEVER changes regardless of vault version updates
        bytes32 dummySalt = keccak256(abi.encodePacked(VAULT_DEPLOYER_ID, "FIXED_DUMMY"));
        address dummyImpl = Create2.deploy(0, dummySalt, FIXED_DUMMY_BYTECODE);

        // Deploy the beacon deterministically using the fixed dummy implementation
        // This ensures beacon addresses are identical across chains and vault versions
        bytes32 beaconSalt = keccak256(abi.encodePacked(VAULT_DEPLOYER_ID, "BEACON"));
        bytes memory beaconBytecode = abi.encodePacked(
            type(UpgradeableBeacon).creationCode,
            abi.encode(dummyImpl) // Always the same dummy implementation
        );

        address beaconAddress = Create2.deploy(0, beaconSalt, beaconBytecode);
        beacon = UpgradeableBeacon(beaconAddress);

        // Now upgrade to the actual implementation (V1, V2, V3, etc.)
        beacon.upgradeTo(_vaultImplementation);
    }

    /**
     * @dev Creates a new vault for a user using CREATE2 for deterministic address
     * @param vaultOwner The address that will own the vault (can deposit/withdraw)
     * @return The address of the newly deployed vault
     */
    function deployVault(address vaultOwner) external nonReentrant whenNotPaused returns (address) {
        if (vaultOwner == address(0)) revert ZeroAddress();
        if (address(beacon) == address(0)) revert BeaconNotSet();
        if (userVault[vaultOwner] != address(0)) revert VaultAlreadyExists();

        // Create deterministic salt using only vault deployer ID and user address
        // This ensures same vault address across chains when factories are at same address
        bytes32 salt = keccak256(abi.encodePacked(VAULT_DEPLOYER_ID, vaultOwner));

        // Encode the initialization data for the vault
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(this), // Factory is the admin owner
            vaultOwner // User is the vault owner
        );

        // Get bytecode for BeaconProxy with our beacon
        bytes memory bytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(beacon), initData));

        // Deploy using CREATE2 for deterministic address
        address vaultAddress = Create2.deploy(0, salt, bytecode);

        // Update mappings and arrays
        userVault[vaultOwner] = vaultAddress;
        isVault[vaultAddress] = true;
        allVaults.push(vaultAddress);

        emit VaultDeployed(vaultOwner, vaultAddress, allVaults.length - 1);

        return vaultAddress;
    }

    /**
     * @dev Sets the authorized manager (only owner)
     * @param newManager The address of the new authorized manager
     */
    function setManager(address newManager) external onlyOwner {
        if (newManager == address(0)) revert ZeroAddress();
        address oldManager = authorizedManager;
        authorizedManager = newManager;
        emit ManagerSet(oldManager, newManager);
    }

    /**
     * @dev Gets the beacon address
     * @return The beacon address
     */
    function getBeacon() external view returns (address) {
        return address(beacon);
    }

    /**
     * @dev Gets the current vault implementation address
     * @return The implementation address
     */
    function getImplementation() external view returns (address) {
        if (address(beacon) == address(0)) return address(0);
        return beacon.implementation();
    }

    /**
     * @dev Predicts the address of a vault before deployment
     * @param vaultOwner The address that will own the vault
     * @return The predicted vault address
     */
    function predictVaultAddress(address vaultOwner) external view returns (address) {
        // Use the same salt logic as deployVault
        bytes32 salt = keccak256(abi.encodePacked(VAULT_DEPLOYER_ID, vaultOwner));

        // Encode the initialization data for the vault
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(this), // Factory is the admin owner
            vaultOwner // User is the vault owner
        );

        // Get bytecode for BeaconProxy with our beacon
        bytes memory bytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(beacon), initData));

        return Create2.computeAddress(salt, keccak256(bytecode), address(this));
    }

    /**
     * @dev Upgrades the beacon to a new implementation (only owner)
     * @param newImplementation The address of the new vault implementation
     */
    function upgradeBeacon(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
        if (address(beacon) == address(0)) revert BeaconNotSet();

        address oldImplementation = beacon.implementation();
        beacon.upgradeTo(newImplementation);

        emit BeaconUpgraded(oldImplementation, newImplementation);
    }

    /**
     * @dev Pauses a specific vault (only owner)
     * @param vault The address of the vault to pause
     */
    function pauseVault(address vault) external onlyOwner {
        if (!isVault[vault]) revert VaultNotFound();

        (bool success, ) = vault.call(abi.encodeWithSignature("pause()"));
        require(success, "Failed to pause vault");

        emit VaultPaused(vault);
    }

    /**
     * @dev Unpauses a specific vault (only owner)
     * @param vault The address of the vault to unpause
     */
    function unpauseVault(address vault) external onlyOwner {
        if (!isVault[vault]) revert VaultNotFound();

        (bool success, ) = vault.call(abi.encodeWithSignature("unpause()"));
        require(success, "Failed to unpause vault");

        emit VaultUnpaused(vault);
    }

    /**
     * @dev Pauses the factory (prevents new vault deployments)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the factory
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Gets the vault owned by a user
     * @param user The user address
     * @return The vault address (or address(0) if no vault exists)
     */
    function getUserVault(address user) external view returns (address) {
        return userVault[user];
    }

    /**
     * @dev Checks if a user has a vault
     * @param user The user address
     * @return True if the user has a vault, false otherwise
     */
    function hasVault(address user) external view returns (bool) {
        return userVault[user] != address(0);
    }

    /**
     * @dev Gets the total number of deployed vaults
     * @return The total number of vaults
     */
    function getTotalVaults() external view returns (uint256) {
        return allVaults.length;
    }

    /**
     * @dev Required by UUPSUpgradeable - authorizes upgrades
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // Only owner can authorize upgrades
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    /**
     * @dev Gets all vault addresses (for batch operations)
     * @return An array of all vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }
}
