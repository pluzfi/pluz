// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { IAssetPriceOracle } from "./IAssetPriceOracle.sol";

/**
 * @title IAssetPriceProvider interface
 * @notice Interface for the collateral price provider.
 *
 */
interface IAssetPriceProvider {
    /**
     * @dev returns the asset price in debt token
     * @param asset the address of the asset
     * @return the debt token price of the asset
     *
     */
    function getAssetPrice(address asset) external view returns (uint256);

    /**
     * @dev returns the asset oracle address
     * @param asset the address of the asset
     * @return the address of the asset oracle
     */
    function getAssetOracle(address asset) external view returns (IAssetPriceOracle);
}
