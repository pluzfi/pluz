// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../forge-std/src/console2.sol";

// @notice Collections of protocol error messages.
library Errors {
    // GENERAL

    /// @notice Unauthorized access
    error Unauthorized();
    /// @notice Disabled functionality
    error FunctionalityDisabled();
    /// @notice Functionality not supported
    error FunctionalityNotSupported();
    /// @notice Invalid parameters passed to function
    error InvalidParams();
    /// @notice ZeroAddress
    error ZeroAddress();
    /// @notice Contract does not exist
    error ContractDoesNotExist();
    /// @notice Invalid amount requested by caller
    error InvalidAmount();
    /// @notice when parameter cannot be equal to zero
    error ParamCannotBeZero();
    /// @notice ERC20 is not transferrable
    error TransferDisabled();
    /// @notice Address doesn't have role
    error UnauthorizedRole(address account, string role);
    /// @notice Action disabled because contract is deprecated
    error Deprecated();

    // ACCESS
    // NOTE: maybe this should be refactored into a generic Errors
    /// @notice Only the lending pool can call this function
    error OnlyLendingPool();

    // COLLATERAL
    /// @notice Invalid collateral monitor update
    error InvalidCollateralMonitorUpdate();
    error NoTellorValueRetrieved(uint256 timestamp);
    error StaleTellorValue(uint256 value, uint256 timestamp);
    error StaleTellorEVMCallTimestamp(uint256 callTimestamp);
    error CannotGoBackInTime();

    error InvalidYieldClaimed(uint256 expectedYield, uint256 actualYield);

    // LENDING
    /// @notice Insufficient liquidity to fulfill action
    error InsufficientLiquidity();
    /// @notice User doesn't have enough collateral backing their position
    error InsufficientCollateral();
    /// @notice Requested borrow is not greater than minimum open borrow amount
    error InvalidMinimumOpenBorrow();

    /// @notice Deposit cap exceeded
    error DepositCapExceeded();
    /// @notice Max deposit per account exceeded
    error MaxDepositPerAccountExceeded();

    // FLASH LOANS
    /// @notice Invalid flash loan balance
    error InvalidFlashLoanBalance();
    /// @notice Invalid flash loan asset
    error InvalidFlashLoanAsset();
    /// @notice Flash loan unpaid
    error InvalidPostFlashLoanBalance();
    /// @notice Invalid flash loan fee
    error InsufficientFlashLoanFeeAmount();
    /// @notice Flash loan recipient doesn't return success
    error InvalidFlashLoanRecipientReturn();

    // ACCOUNTS
    /// @notice Account failed solvency check after some action.
    /// @dev The account's debt isn't sufficiently collateralized and/or the account is liquidatable.
    error AccountInsolvent();
    /// @dev Account cannot be liquidated
    error AccountHealthy();
    /// @notice Account is being liquidated
    error AccountBeingLiquidated();
    /// @notice Account is not being liquidated
    error AccountNotBeingLiquidated();
    /// @notice Account hasn't been created yet
    error AccountNotCreated();

    // INVESTMENT
    /// @notice Account is not liquidatable
    error NotLiquidatable();
    /// @notice Account is not repayable
    error NotRepayable();

    /// @notice Account type invalid
    error InvalidAccountType();

    /// @notice Interaction with a strategy that is not approved
    error StrategyNotApproved();
    /// @notice Liquidator has no funds to repay
    error NoLiquidatorFunds();
    /// @notice Requested profit is not claimable from account (if account has debt or not enough profit to fill request
    /// amount)
    error NotClaimableProfit();
    /// @notice Used when Gelato automation task was already started
    error AlreadyStartedTask();
    /// @notice Assets not received
    error WithdrawnAssetsNotReceived();

    ///////////////////////////
    // Multi-step Strategies
    ///////////////////////////

    /// @notice Account is attempting to withdraw more strategy shares than their unlocked share balance.
    /// @dev An account's balanceOf(strategyShareToken) is their totalShareBalance.
    /// Since some strategies are multi-step, when a account withdraws, those shares are added to a separate variable
    /// known
    /// as their lockedShareBalance.
    /// A account's unlocked share balance when it comes to withdrawals is their totalShareBalance - lockedShareBalance.
    error PendingStrategyWithdrawal(address account);

    /// @notice Account cannot deposit into the same multi-step strategy until their previous deposit has cleared.
    error PendingStrategyDeposit(address account);

    //////////////////////////
    /// OmegaGMXStrategyVault
    //////////////////////////

    /// @notice When already exist a depositKey in the vault
    error MustNotHavePendingValue();
    /// @notice When not sending eth to pay for the fee in a deposit or withdrawal
    error MustSendETHForExecutionFee();

    /// Pyth
    error PythPriceFeedNotFound(address asset);
    error PythInvalidNonPositivePrice(address asset);

    // Particle
    error ExistingPosition();
    error NoPosition();
}

library PluzErrors {
    /// @dev For contracts that need to compound claimable yield onto themselves, they cannot claim with themselves as
    /// the recipient.
    /// To get around this, they claim to another contract that reflects the yield back to them.
    error InvalidReflection(uint256 expected, uint256 actual);
}
