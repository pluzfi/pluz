// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

library AccountLib {
    /// @notice The type of account that can be created
    enum Type {
        EXTERNAL, // Accounts that allow taking funds out of the protocol
        INTERNAL // Accounts that require funds remain in the protocol

    }

    /// @notice The health of the account
    /// The collateral and equity values are all denominated in the debt amount.
    struct Health {
        uint256 debtAmount;
        uint256 collateralValue;
        uint256 investmentValue;
        bool isLiquidatable;
        bool hasBadDebt;
    }

    /// @notice Expected values resulting from a collateral liquidation.
    /// @param actualDebtToLiquidate the amount of debt to cover for the account
    /// @param collateralAmount the amount of collateral to receive
    /// @param bonusCollateral the amount of bonus collateral included in the collateralAmount
    struct CollateralLiquidation {
        uint256 actualDebtToLiquidate;
        uint256 collateralAmount;
        uint256 bonusCollateral;
    }

    /// @notice The state of an account's lending pool loan
    struct Loan {
        /// @notice The amount of debt the borrower has
        uint256 debtAmount;
        /// @notice The value of the borrowers collateral in debt token
        uint256 collateralValue;
        /// @notice The current loan to value ratio of the borrower
        UD60x18 ltv;
        /// @notice Borrower cannot perform a borrow if it puts their ltv over this amount
        UD60x18 maxLtv;
    }

    struct LiquidationStatus {
        bool isLiquidating;
        uint256 liquidationStartTime;
    }

    /*  @notice Liquidator fee.
        @dev protocolShare + liquidatorShare = liquidationFee.
        liquidationFee is % deducted from liquidated funds before they are used towards repayment.
    */
    struct LiquidationFee {
        UD60x18 protocolShare;
        UD60x18 liquidatorShare;
    }

    /// @notice
    struct CreateAccountProps {
        address owner;
        AccountLib.Type accountType;
    }

    /// @notice Custom meta txn for creating an account
    struct CreateAccountData {
        address owner;
        uint256 accountType;
        bytes signature;
    }

    /// @notice Data to sign when creating an account gaslessly
    struct CreateAccount {
        address owner;
        uint256 accountType;
    }
}
