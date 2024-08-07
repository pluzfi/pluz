// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";

library LendingLib {
    /// @notice The reserve state
    struct Reserve {
        /// @notice The address of the underlying asset used for deposits/borrows
        IERC20 asset;
        /// @notice The current balance of the asset in the pool
        uint256 assetBalance;
        /// @notice The current interest rate on borrowing
        UD60x18 borrowRate;
        /// @notice The liquidity rate, as defined in Aave Protocol white paper
        UD60x18 liquidityRate;
        /// @notice Liquidity Index as defined in Aave Protocol white paper
        UD60x18 liquidityIndex;
        /// @notice Borrow Index as defined in Aave Protocol white paper
        UD60x18 borrowIndex;
        /// @notice The last time the reserves state was updated
        uint256 lastUpdateTimestamp;
    }
}
