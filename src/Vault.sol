// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Vault
 * @dev A multi-token vault contract that allows users to deposit various ERC20 tokens
 * @dev Implements beacon pattern for upgradeability with security features
 * @dev Uses dual ownership: factory (admin) and vault owner (user)
 */
contract Vault is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev The vault owner (user) who can deposit and withdraw
    address public vaultOwner;

    /// @dev Events
    event TokenDeposited(address indexed token, uint256 amount);
    event TokenWithdrawn(address indexed token, uint256 amount);

    /// @dev Errors
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error OnlyVaultOwner();

    /// @dev Modifier to check if caller is the vault owner (user)
    modifier onlyVaultOwner() {
        if (msg.sender != vaultOwner) revert OnlyVaultOwner();
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
     * @dev Gets the vault's balance for a specific token
     * @param token The address of the token
     * @return The vault's balance
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
