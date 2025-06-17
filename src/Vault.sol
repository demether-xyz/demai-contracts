// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVault } from "./interfaces/IVault.sol";
import { IVaultFactory } from "./interfaces/IVaultFactory.sol";

/**
 * @title Vault
 * @dev A multi-token vault contract that allows users to deposit various ERC20 tokens
 * @dev Implements beacon pattern for upgradeability with security features
 * @dev Uses dual ownership: factory (admin) and vault owner (user)
 * @dev Supports generic strategy execution for yield generation via external protocols
 */
contract Vault is IVault, Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev The vault owner (user) who can deposit and withdraw
    address public vaultOwner;

    /// @dev Modifier to check if caller is the vault owner (user)
    modifier onlyVaultOwner() {
        if (msg.sender != vaultOwner) revert OnlyVaultOwner();
        _;
    }

    /// @dev Modifier to check if caller is the authorized manager
    modifier onlyAuthorizedManager() {
        IVaultFactory factory = IVaultFactory(owner());
        if (msg.sender != factory.authorizedManager()) revert OnlyAuthorizedManager();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the vault contract
     * @param _factoryOwner The factory owner (admin) of the contract
     * @param _vaultOwner The vault owner (user) who can deposit/withdraw
     */
    function initialize(address _factoryOwner, address _vaultOwner) public initializer {
        if (_factoryOwner == address(0)) revert ZeroAddress();
        if (_vaultOwner == address(0)) revert ZeroAddress();

        __ReentrancyGuard_init();
        __Ownable_init(_factoryOwner);
        __Pausable_init();

        vaultOwner = _vaultOwner;
    }

    /**
     * @dev Deposits tokens into the vault (only vault owner)
     * @param token The address of the ERC20 token to deposit
     * @param amount The amount of tokens to deposit
     */
    function deposit(address token, uint256 amount) external onlyVaultOwner nonReentrant whenNotPaused {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit TokenDeposited(token, amount);
    }

    /**
     * @dev Withdraws tokens from the vault (only vault owner)
     * @param token The address of the ERC20 token to withdraw
     * @param amount The amount of tokens to withdraw
     */
    function withdraw(address token, uint256 amount) external onlyVaultOwner nonReentrant whenNotPaused {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        IERC20(token).safeTransfer(msg.sender, amount);

        emit TokenWithdrawn(token, amount);
    }

    /**
     * @dev Pauses the contract (only factory owner)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract (only factory owner)
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Executes a generic strategy (only authorized manager)
     * @param targetContract The target contract to call
     * @param data The call data to execute
     * @param approvals Array of token approvals needed for the call
     */
    function executeStrategy(
        address targetContract,
        bytes calldata data,
        TokenApproval[] calldata approvals
    ) external onlyAuthorizedManager nonReentrant whenNotPaused {
        if (targetContract == address(0)) revert ZeroAddress();

        // Handle token approvals before executing the call
        for (uint256 i = 0; i < approvals.length; i++) {
            if (approvals[i].token == address(0)) revert ZeroAddress();
            if (approvals[i].amount == 0) continue; // Skip zero approvals
            
            IERC20(approvals[i].token).safeApprove(targetContract, approvals[i].amount);
            emit TokenApproved(approvals[i].token, targetContract, approvals[i].amount);
        }

        // Execute the call to the target contract
        (bool success, ) = targetContract.call(data);
        
        if (!success) {
            revert StrategyExecutionFailed();
        }

        emit StrategyExecuted(targetContract, data);
    }

    /**
     * @dev Gets the vault's balance for a specific token
     * @param token The address of the token
     * @return The vault's balance
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev Gets the factory address
     * @return The factory address
     */
    function getFactory() external view returns (address) {
        return owner();
    }
}
