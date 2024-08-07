// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

/// @notice Interface for a price oracle preconfigured to return the price of an asset.
/// @dev Price can be in any denomination, depending on the preconfiguration.
interface IAssetPriceOracle {
    function getPrice() external view returns (uint256 price);
}
