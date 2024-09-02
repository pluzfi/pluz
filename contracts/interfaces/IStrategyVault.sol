// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { UD60x18 } from "@prb/math/src/UD60x18.sol";

/// @title Omega Strategy Vault Interface
///
/// @notice These vaults accept USDC and invest them into a strategy.
/// The deposit is done in USDC but the shares are in the underlying asset.
/// The underlying asset is referred to as `asset` in the contract.
/// These vaults implement _some_ ERC4626 methods.
/// There is one significant change for these vaults: the deposit is
/// done using USDC instead of the `asset` (i.e. the underlying asset).
///
/// @dev Shares are priced in units of the `asset` NOT in USDC
///
interface IStrategyVault {
    function setTotalDepositCap(uint256 newDepositCap) external;
    function setMaxDepositPerAccount(uint256 newMaxDeposit) external;
    function setDepositFee(UD60x18 newDepositFee) external;
    function setWithdrawalFee(UD60x18 newWithdrawalFee) external;

    /// @notice Estimate the ETH execution fee needed for this withdrawal
    function estimateExecuteDepositGasLimit() external view returns (uint256);
    function estimateExecuteWithdrawalGasLimit() external view returns (uint256);

    /// @notice Deposits USDC into the vault
    /// @param assets The amount of USDC to deposit
    /// @param data encoded data for the strategy to process the deposit
    /// @param recipient The address to send the share tokens to
    function deposit(
        uint256 assets,
        bytes memory data,
        address recipient
    )
        external
        payable
        returns (uint256 receivedShares);

    /// @notice Withdraws `msg.sender` shares from the vault and sends baseAsset to self.
    /// @param shares The amount of vault shares to withdraw
    /// @param data encoded data for the strategy to process the withdrawal
    function withdraw(uint256 shares, bytes memory data) external payable returns (uint256 receivedAmount);

    /// @notice Performs a complete withdrawal for `msg.sender` and sends funds to receiver.
    function liquidate(address receiver, uint256 minAmount, bytes memory data) external payable returns (uint256);

    /// @notice claimRewards
    function claimRewards() external returns (uint256[] memory);

    /// @notice This function allows users to simulate the effects of their withdrawal at the current block.
    /// @dev Use this to calculate the minAmount of lend token to withdraw during withdrawal
    /// @param shareAmount The amount of shares to redeem
    /// @return The amount of lend token that would be redeemed for the amount of shares provided
    function previewWithdraw(uint256 shareAmount) external view returns (uint256);

    /// @notice This function allows users to simulate the effects of their deposit at the current block.
    /// @dev Use this to calculate the minAmount of shares to mint during deposit
    /// @param assetAmount The amount of assets to deposit
    /// @return The amount of shares that would be minted for the amount of asset provided
    function previewDeposit(uint256 assetAmount) external view returns (uint256);

    /// @notice Returns value of the position of the account denominated in lending token.
    function getPositionValue(address account) external view returns (uint256);
}
