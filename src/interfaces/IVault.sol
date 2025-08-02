// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IVault
 * @dev Interface for the Vault contract defining all structs, events, and errors
 */
interface IVault {
    /// @dev Struct for token approval data
    struct TokenApproval {
        address token;
        uint256 amount;
    }

    /// @dev Events
    event TokenDeposited(address indexed token, uint256 amount);
    event TokenWithdrawn(address indexed token, uint256 amount);
    event StrategyExecuted(address indexed targetContract, bytes data);
    event TokenApproved(address indexed token, address indexed spender, uint256 amount);

    /// @dev Errors
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error OnlyVaultOwner();
    error OnlyAuthorizedManager();
    error StrategyExecutionFailed();

    /// @dev Functions
    function initialize(address _factoryOwner, address _vaultOwner) external;
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
    function executeStrategy(address targetContract, bytes calldata data, TokenApproval[] calldata approvals) external;
    function pause() external;
    function unpause() external;
    function getTokenBalance(address token) external view returns (uint256);
    function getMultipleTokenBalances(address[] calldata tokens) external view returns (uint256[] memory balances);
    function getFactory() external view returns (address);
    function vaultOwner() external view returns (address);
    function approveToken(address token, address spender, uint256 amount) external;
}
