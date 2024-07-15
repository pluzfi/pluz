// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { ProtocolModule } from "contracts/system/ProtocolModule.sol";
import { IInterestRateStrategy } from "contracts/interfaces/IInterestRateStrategy.sol";
import { ILendingPool } from "contracts/interfaces/ILendingPool.sol";
import { LendingLib } from "contracts/libraries/LendingLib.sol";
import { UD60x18, ud, UNIT } from "@prb/math/src/UD60x18.sol";

interface ILendingPoolExt {
    function reserve() external view returns (LendingLib.Reserve memory);
}

/// @title Interest Rate Strategy
/// @notice Calculates the interest rate based on the utilization rate
contract InterestRateStrategyV2 is IInterestRateStrategy, ProtocolModule {
    UD60x18 public optimalUtilizationRate;
    UD60x18 public baseBorrowRate;
    UD60x18 public borrowRateSlope1;
    UD60x18 public borrowRateSlope2;
    UD60x18 public utilizationRateCap;
    uint256 public minimumLendingPoolBalance;

    struct InitParams {
        address governor;
        UD60x18 optimalUtilizationRate;
        UD60x18 baseBorrowRate;
        UD60x18 borrowRateSlope1;
        UD60x18 borrowRateSlope2;
        UD60x18 utilizationRateCap;
        uint256 minimumLendingPoolBalance;
    }

    error UtilizationRateTooHigh();
    error LendingPoolBalanceTooLow();

    constructor(InitParams memory params) ProtocolModule(params.governor) {
        optimalUtilizationRate = params.optimalUtilizationRate;
        baseBorrowRate = params.baseBorrowRate;
        borrowRateSlope1 = params.borrowRateSlope1;
        borrowRateSlope2 = params.borrowRateSlope2;
        utilizationRateCap = params.utilizationRateCap;
        minimumLendingPoolBalance = params.minimumLendingPoolBalance;
    }

    function updateRateParameters(
        UD60x18 _optimalUtilizationRate,
        UD60x18 _baseBorrowRate,
        UD60x18 _borrowRateSlope1,
        UD60x18 _borrowRateSlope2
    )
        external
        onlyOwner
    {
        optimalUtilizationRate = _optimalUtilizationRate;
        baseBorrowRate = _baseBorrowRate;
        borrowRateSlope1 = _borrowRateSlope1;
        borrowRateSlope2 = _borrowRateSlope2;
    }

    function updateUtilizationRateCap(UD60x18 _utilizationRateCap) external onlyOwner {
        utilizationRateCap = _utilizationRateCap;
    }

    function updateMinimumLendingPoolBalance(uint256 _minimumLendingPoolBalance) external onlyOwner {
        minimumLendingPoolBalance = _minimumLendingPoolBalance;
    }

    /// @notice Calculates the interest rate based on the utilization rate
    /// @param utilization The utilization rate (total borrow / total supplied)
    /// @return liquidityRate The liquidity/deposit interest rate for the given utilization rate
    /// @return borrowRate The borrow interest rate for the given utilization rate
    function calculateInterestRate(UD60x18 utilization)
        external
        view
        returns (UD60x18 liquidityRate, UD60x18 borrowRate)
    {
        _validateLendingPool(msg.sender, utilization);

        // Cap the utilization rate so that interest cannot increase infinitely.
        if (utilization >= UNIT) {
            utilization = UNIT;
        }
        // The interest rate formula follows an interest rate curve. The curve is broken up into 2 sections:
        // When utilization is below the optimal utilization rate, the borrow rate is:
        // max(baseBorrowRate, utilization * borrowRateSlope1)
        if (utilization < optimalUtilizationRate) {
            borrowRate = utilization.mul(borrowRateSlope1);
            if (borrowRate < baseBorrowRate) {
                borrowRate = baseBorrowRate;
            }
        } else {
            // The section section is when utilization is above the optimal utilization rate, the borrow rate increases
            // according to utilization * borrowRateSlope1. After the utilization > optimalUtilizationRate, the
            // slope increases
            // by adding an additional "excess rate." The additional slope is defined by borrowRateSlope2. The formula
            // is as follows:
            borrowRate = utilization.mul(borrowRateSlope1);
            // Excess rate from slope 2
            borrowRate = borrowRate.add((utilization.sub(optimalUtilizationRate)).mul(borrowRateSlope2));
        }

        liquidityRate = borrowRate.mul(utilization);
    }

    function _validateLendingPool(address lendingPool, UD60x18 utilization) internal view {
        try ILendingPoolExt(lendingPool).reserve() returns (LendingLib.Reserve memory reserve) {
            if (utilization > utilizationRateCap) {
                revert UtilizationRateTooHigh();
            }

            if (reserve.assetBalance < minimumLendingPoolBalance) {
                revert LendingPoolBalanceTooLow();
            }
        } catch { }
    }
}
