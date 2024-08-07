// SPDX-License-Identifier: GPL-3.0
// Source: Aave V3 Core Protocol
// Permalink:
// https://github.com/aave/aave-v3-core/blob/6070e82d962d9b12835c88e68210d0e63f08d035/contracts/protocol/libraries/math/MathUtils.sol
// Modifications:
// - Added Slither comments to silence warnings from divide-before-multiply
pragma solidity 0.8.24;

import { UD60x18, ud, UNIT, uUNIT, ZERO } from "@prb/math/src/UD60x18.sol";

/**
 * @title MathUtils library
 * @notice Provides functions to perform linear and compounded interest calculations
 */
library MathUtils {
    /// @dev Used in token math to document rounding method being used.
    /// This is useful when we always want to round in favor of the protocol to disallow users to steal funds.
    enum ROUNDING {
        UP,
        DOWN
    }

    /// @dev Ignoring leap years
    uint256 public constant ONE_YEAR = 365 days;

    /**
     * @notice FV = P*e^(r*t) where P is 1
     * @dev Function to calculate the interest using a compounded interest rate formula
     * @param rate The interest rate per anum, 1e18 precision
     * @param lastUpdateTimestamp The timestamp of the last update of the interest
     * @param currentTimestamp The current timestamp
     * @return The interest rate compounded during the timeDelta
     */
    function calculateCompoundedInterest(
        UD60x18 rate,
        uint256 lastUpdateTimestamp,
        uint256 currentTimestamp
    )
        internal
        pure
        returns (UD60x18)
    {
        UD60x18 principal = UNIT;
        uint256 elapsed = currentTimestamp - lastUpdateTimestamp;

        if (elapsed == 0) {
            return principal;
        }

        uint256 exponent = (elapsed * rate.unwrap()) / ONE_YEAR;

        return principal.mul(ud(exponent).exp());
    }

    /**
     * @dev Calculates the compounded interest between the timestamp of the last update and the current block timestamp
     * @param rate The interest rate
     * @param lastUpdateTimestamp The timestamp from which the interest accumulation needs to be calculated
     * @return The interest rate compounded between lastUpdateTimestamp and current block timestamp
     *
     */
    function calculateCompoundedInterest(UD60x18 rate, uint256 lastUpdateTimestamp) internal view returns (UD60x18) {
        return calculateCompoundedInterest(rate, lastUpdateTimestamp, block.timestamp);
    }

    /// @notice Converts a number with `inputDecimals`, to a number with given amount of decimals
    /// @param value The value to convert
    /// @param inputDecimals The amount of decimals the input value has
    /// @param targetDecimals The amount of decimals to convert to
    /// @return The converted value
    function scaleDecimals(uint256 value, uint8 inputDecimals, uint8 targetDecimals) internal pure returns (uint256) {
        if (targetDecimals == inputDecimals) return value;
        if (targetDecimals > inputDecimals) return value * (10 ** (targetDecimals - inputDecimals));

        return value / (10 ** (inputDecimals - targetDecimals));
    }

    /// @notice Converts a number with `inputDecimals`, to a number with given amount of decimals
    /// @param value The value to convert
    /// @param inputDecimals The amount of decimals the input value has
    /// @param targetDecimals The amount of decimals to convert to
    /// @return The converted value
    function scaleDecimals(int256 value, uint8 inputDecimals, uint8 targetDecimals) internal pure returns (int256) {
        if (targetDecimals == inputDecimals) return value;
        if (targetDecimals > inputDecimals) return value * int256(10 ** (targetDecimals - inputDecimals));

        return value / int256(10 ** (inputDecimals - targetDecimals));
    }

    /// @notice Converts a number with `decimals`, to a UD60x18 type
    /// @param value The value to convert
    /// @param decimals The amount of decimals the value has
    /// @return The number as a UD60x18
    function fromTokenDecimals(uint256 value, uint8 decimals) internal pure returns (UD60x18) {
        return ud(scaleDecimals(value, decimals, 18));
    }

    /// @notice Converts a UD60x18 number with `decimals`, to it's uint256 type scaled down.
    /// @param value The value to convert
    /// @param decimals The amount of decimals the value has
    /// @return The number as a scaled down uint256
    function toTokenDecimals(UD60x18 value, uint8 decimals) internal pure returns (uint256) {
        return scaleDecimals(value.unwrap(), 18, decimals);
    }

    /// @notice Truncates a UD60x18 number down to the correct precision.
    /// @param value The value to convert
    /// @param decimals The amount of decimals the value has
    /// @return The truncated UD60x18 number
    function truncate(UD60x18 value, uint8 decimals) internal pure returns (UD60x18) {
        return fromTokenDecimals(toTokenDecimals(value, decimals), decimals);
    }
}
