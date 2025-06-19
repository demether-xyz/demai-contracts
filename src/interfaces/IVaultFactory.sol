// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IVaultFactory
 * @dev Interface for the VaultFactory contract
 */
interface IVaultFactory {
    /// @dev Returns the authorized manager address
    function authorizedManager() external view returns (address);

    /// @dev Creates a new vault for the specified owner
    function deployVault(address vaultOwner) external returns (address);

    /// @dev Sets the authorized manager (only owner)
    function setManager(address manager) external;

    /// @dev Gets the beacon address
    function getBeacon() external view returns (address);

    /// @dev Predicts the vault address before deployment
    function predictVaultAddress(address vaultOwner) external view returns (address);
}
