// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IStrategyVault } from "../interfaces/IStrategyVault.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

import "./BaseAccount.sol";
import "../libraries/Errors.sol";

abstract contract InternalAccountEvents {
    /// @notice The owner made a deposit of `amount` into `strategy`
    event StrategyDeposit(address strategy, uint256 amount);
    /// @notice The owner withdrew `amount` from `strategy`
    event StrategyWithdraw(address strategy, uint256 amount);
    /// @notice The deposits into `strategy` have been forcibly withdrawn and `receveredAmount` was returned
    /// @dev When strategy == address(0) it indicates a liquidation of the balance in the account
    event StrategyLiquidated(address indexed strategy, uint256 recoveredAmount);
}

/// @title Internal Account
/// @notice This account type is used to manage investments into approved strategies.
/// The account owner can deposit and withdraw from approved strategies to earn profits.
contract InternalAccount is BaseAccount, InternalAccountEvents {
    using SafeERC20 for IERC20;

    /// @notice Initialize this permissioned account
    /// @param owner_  The borrower that owns this account
    function initialize(address owner_) public virtual override initializer {
        _initialize(owner_);
    }

    //////////////////////////
    // Investment Methods
    //////////////////////////
    /// @notice These methods are used to manage permissioned investment into approved investment strategies

    /// @notice Deposit into a Omega Strategy Vault
    /// @dev The `minShares` can be calculated using the `previewDeposit` method on the vault
    /// @param strategy The address of the strategy to deposit into
    /// @param amount The amount to deposit in USDC
    /// @param data encode data for the strategy to process the deposit
    function strategyDeposit(
        address strategy,
        uint256 amount,
        bytes memory data
    )
        external
        payable
        virtual
        onlyOwner
        whenNotPaused
        returns (uint256 receivedShares)
    {
        asset.safeIncreaseAllowance(strategy, amount);

        uint256 executionGasLimit = 0;
        if (strategy != address(0)) {
            executionGasLimit = IStrategyVault(strategy).estimateExecuteDepositGasLimit();
        }

        uint256 executionFee = 0;

        if (executionGasLimit > 0) {
            executionFee = executionGasLimit * tx.gasprice;
        }

        receivedShares = _manager.strategyDeposit{ value: executionFee }(owner, strategy, amount, data);
        emit StrategyDeposit(strategy, amount);
    }

    /// @notice Withdraw from a Omega Strategy Vault
    /// @dev The `minUsdc` can be calculated using the `previewWithdraw` method on the vault
    /// @param strategy The address of the strategy to withdraw from
    /// @param shares The amount to withdraw in vault shares
    /// @param data encoded data for the strategy to process the withdrawal
    function strategyWithdraw(
        address strategy,
        uint256 shares,
        bytes memory data
    )
        external
        payable
        onlyOwner
        whenNotPaused
        returns (uint256 receivedAssets)
    {
        uint256 executionGasLimit = 0;
        if (strategy != address(0)) {
            executionGasLimit = IStrategyVault(strategy).estimateExecuteWithdrawalGasLimit();
        }

        uint256 executionFee = 0;

        if (executionGasLimit > 0) {
            executionFee = executionGasLimit * tx.gasprice;
        }

        receivedAssets = IStrategyVault(strategy).withdraw{ value: executionFee }(shares, data);

        _manager.strategyWithdrawal(owner, strategy, receivedAssets);

        emit StrategyWithdraw(strategy, shares);
    }

    //////////////////////////
    // View Methods
    //////////////////////////
    /// @notice These methods are used to view information about this account

    function getKind() external pure virtual returns (bytes32) {
        return keccak256(abi.encode("OMEGA_INTERNAL_ACCOUNT"));
    }

    //////////////////////////
    // Liquidator Methods
    //////////////////////////

    function _preStrategyLiquidation(address recipient) internal view returns (uint256 amountBefore) {
        // Track the amount liquidate by checking the asset balance of the liquidator before and after
        amountBefore = asset.balanceOf(recipient);
    }

    function _postStrategyLiquidation(
        address strategy,
        address recipient,
        uint256 expectedReceived,
        uint256 amountBefore
    )
        internal
    {
        if (asset.balanceOf(address(recipient)) < (expectedReceived + amountBefore)) {
            revert Errors.WithdrawnAssetsNotReceived();
        }

        // When strategy == address(0) it indicates a liquidation of the balance in the account
        emit StrategyLiquidated(strategy, expectedReceived);
    }

    function liquidateStrategy(
        address strategy,
        address recipient,
        uint256 minAmount,
        bytes memory data
    )
        external
        payable
        onlyAccountManager
    {
        uint256 amountBefore = _preStrategyLiquidation(recipient);

        uint256 receivedAssets = 0;

        uint256 executionGasLimit = 0;
        if (strategy != address(0)) {
            executionGasLimit = IStrategyVault(strategy).estimateExecuteDepositGasLimit();
        }

        uint256 executionFee = 0;

        if (executionGasLimit > 0) {
            executionFee = executionGasLimit * tx.gasprice;
        }

        if (strategy != address(0)) {
            receivedAssets = IStrategyVault(strategy).liquidate{ value: executionFee }(recipient, minAmount, data);
            _postStrategyLiquidation(strategy, recipient, receivedAssets, amountBefore);
        }
    }

    receive() external payable { }
}
