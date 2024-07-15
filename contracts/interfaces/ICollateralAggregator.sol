// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

/// @notice Provides aggregated information about collateral supported by the system.
interface ICollateralAggregator {
    function getTotalCollateralValue(address account) external view returns (uint256 totalValue);
    function getCollateralAmount(address account, address asset) external view returns (uint256 amount);
    function getSupportedCollateralAssets() external view returns (address[] memory assets);
    function isCollateralAsset(address asset) external view returns (bool);
}
