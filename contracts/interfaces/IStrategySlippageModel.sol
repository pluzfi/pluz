// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { UD60x18 } from "@prb/math/src/UD60x18.sol";

// TODO: in the future, we will adjust this based off how long the account has been in liquidation
// Note: This slippage tolerance might be better to increase as a function of elapse
// time. That is, the slippage is higher the longer the account is in liquidation.
// A static slippage like this means we'd need to manually increase the value if the
// position can't be liquidate with the set slippage tolerance.

/// @notice This contract returns the slippageTolerance for a strategy liquidation as a function of how long that
/// strategy has been in
/// liquidation mode.
interface IStrategySlippageModel {
    function calculateSlippage(uint256 timeSinceLiquidationStarted) external view returns (UD60x18 slippageTolerance);
}
