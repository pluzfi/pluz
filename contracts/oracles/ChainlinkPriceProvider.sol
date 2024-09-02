// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { ProtocolModule, ProtocolGovernor } from "../system/ProtocolModule.sol";
import { IAssetPriceProvider } from "../interfaces/IAssetPriceProvider.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../libraries/Errors.sol";

/// @notice Fetches prices from Chainlink AggregatorV3 interfaces and normalizes price to 18 decimals.
contract ChainlinkPriceProvider is ProtocolModule, IAssetPriceProvider {
    event AggregatorUpdated(address indexed asset, address aggregator, uint256 heartbeat);

    error UnsupportedAsset(address asset);
    error PriceRetrievalFailed(address asset, address aggregator, uint256 lastUpdated, uint256 heartbeat);

    struct AggregatorData {
        AggregatorV3Interface instance;
        uint256 heartbeat;
    }

    mapping(address => AggregatorData) internal _aggregators;

    constructor(
        address protocolGovernor_,
        address[] memory assets,
        AggregatorData[] memory aggregators
    )
        ProtocolModule(protocolGovernor_)
    {
        _setAggregators(assets, aggregators);
    }

    function getAggregatorData(address asset) external view returns (AggregatorData memory) {
        return _aggregators[asset];
    }

    /// @notice External function called by protocol admin to set or replace aggregators of assets
    function setAggregators(address[] memory assets, AggregatorData[] memory aggregators) external onlyOwner {
        _setAggregators(assets, aggregators);
    }

    /// @notice Internal function to set or replace aggregators for each asset
    /// @param assets the assets
    function _setAggregators(address[] memory assets, AggregatorData[] memory aggregators) internal {
        if (assets.length != aggregators.length) {
            revert Errors.InvalidParams();
        }

        for (uint256 i = 0; i < assets.length; i++) {
            _aggregators[assets[i]] = aggregators[i];

            if (address(aggregators[i].instance) == address(0)) {
                revert Errors.InvalidParams();
            }

            emit AggregatorUpdated(assets[i], address(aggregators[i].instance), aggregators[i].heartbeat);
        }
    }

    function getAssetPrice(address asset) external view returns (uint256 assetPrice) {
        AggregatorData memory data = _aggregators[asset];

        if (address(data.instance) == address(0)) {
            revert UnsupportedAsset(asset);
        }

        (uint80 roundId, int256 answer,, uint256 updatedAt,) = data.instance.latestRoundData();
        if (roundId != 0 && answer >= 0 && updatedAt != 0 && updatedAt <= block.timestamp) {
            if (block.timestamp - updatedAt > data.heartbeat) {
                revert PriceRetrievalFailed(asset, address(data.instance), updatedAt, data.heartbeat);
            } else {
                uint8 priceDecimals = data.instance.decimals();
                uint8 targetDecimals = 18;

                if (targetDecimals >= priceDecimals) {
                    assetPrice = uint256(answer) * 10 ** uint32(targetDecimals - priceDecimals);
                } else {
                    assetPrice = uint256(answer) / 10 ** uint32(priceDecimals - targetDecimals);
                }
            }
        } else {
            revert PriceRetrievalFailed(asset, address(data.instance), updatedAt, data.heartbeat);
        }
    }
}
