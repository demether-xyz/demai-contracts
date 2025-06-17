// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { IBeacon } from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
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
        __Ownable_init(_owner);
        __Pausable_init();
        __ReentrancyGuard_init();

        // Deploy the beacon with the initial implementation
        beacon = new UpgradeableBeacon(_vaultImplementation, address(this));
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

        // Use address-only salt for cross-chain consistency
        // This means one vault per user, but same address on all chains
        bytes32 salt = bytes32(uint256(uint160(vaultOwner)));

        // Encode the initialization data for the vault
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(this), // Factory is the admin owner
            vaultOwner // User is the vault owner
        );

        // Get bytecode for BeaconProxy
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
     * @dev Predicts the address of a vault before deployment
     * @param vaultOwner The address that will own the vault
     * @return The predicted vault address
     */
    function predictVaultAddress(address vaultOwner) external view returns (address) {
        // Use the same salt logic as createVault
        bytes32 salt = bytes32(uint256(uint160(vaultOwner)));

        // Encode the initialization data for the vault
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(this), // Factory is the admin owner
            vaultOwner // User is the vault owner
        );

        // Get bytecode for BeaconProxy
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
     * @dev Gets the current vault implementation address
     * @return The implementation address
     */
    function getImplementation() external view returns (address) {
        if (address(beacon) == address(0)) return address(0);
        return beacon.implementation();
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

    /**
     * @dev Gets the creation bytecode for the BeaconProxy contract.
     * @dev Useful for off-chain address prediction.
     * @return The creation bytecode.
     */
    function getBeaconProxyCreationCode() external pure returns (bytes memory) {
        return type(BeaconProxy).creationCode;
    }
}
