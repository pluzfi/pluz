// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { ProtocolModule, ProtocolGovernor } from "../system/ProtocolModule.sol";
import { IAssetPriceProvider } from "../interfaces/IAssetPriceProvider.sol";
import { IAssetPriceOracle } from "../interfaces/IAssetPriceOracle.sol";
import "../libraries/Errors.sol";

abstract contract AssetPriceAggregatorEvents {
    event AssetProvidersUpdated(address indexed asset, address primary, address backup);
}

/// @notice Fetches prices from different AssetPriceProviders and normalizes their price to some base asset.
contract AssetPriceAggregator is ProtocolModule, IAssetPriceProvider, AssetPriceAggregatorEvents {
    mapping(address => Providers) internal _providers;

    /// @dev Most price feeds need to be normalized to base asset, but some are already denominated in base asset.
    mapping(address => bool) internal _isNormalized;

    struct Providers {
        IAssetPriceProvider primary;
        IAssetPriceProvider backup;
    }

    error UnsupportedAsset(address asset);
    error PriceRetrievalFailed(address asset, address primary, address backup);

    /// @param base Address used to call IAssetPriceProvider to get BASE/USD Datafeed.
    /// @dev This datafeed is used to normalize USD prices to X prices
    /// @param decimals BASE decimal precision

    struct Props {
        address base;
        uint8 decimals;
    }

    Props internal _props;

    constructor(
        address protocolGovernor_,
        Props memory props_,
        address[] memory assets,
        Providers[] memory providers
    )
        ProtocolModule(protocolGovernor_)
    {
        _props.base = props_.base;
        _props.decimals = props_.decimals;

        _setAssetProviders(assets, providers);

        if (address(_providers[_props.base].primary) == address(0)) {
            revert Errors.InvalidParams();
        }
    }

    function getProps() external view returns (Props memory) {
        return _props;
    }

    /// @dev Is a given asset price expected to be denominated in base asset?
    function getIsNormalized(address asset) external view returns (bool) {
        return _isNormalized[asset];
    }

    function setIsNormalized(address[] memory assets, bool isNormalized) external onlyOwner {
        for (uint256 i = 0; i < assets.length; i++) {
            _isNormalized[assets[i]] = isNormalized;
        }
    }

    /// @notice External function called by protocol admin to set or replace providers of assets
    /// @param assets the assets
    /// @param providers the providers
    function setAssetProviders(address[] memory assets, Providers[] memory providers) external onlyOwner {
        _setAssetProviders(assets, providers);
    }

    /// @notice Internal function to set or replace providers for each asset
    /// @param assets the assets
    /// @param providers the providers
    function _setAssetProviders(address[] memory assets, Providers[] memory providers) internal {
        if (assets.length != providers.length) {
            revert Errors.InvalidParams();
        }

        for (uint256 i = 0; i < assets.length; i++) {
            _providers[assets[i]] = providers[i];

            if (address(providers[i].primary) == address(0)) {
                revert Errors.InvalidParams();
            }

            emit AssetProvidersUpdated(assets[i], address(providers[i].primary), address(providers[i].backup));
        }
    }

    function getAssetPrice(address asset) external view override returns (uint256 priceInBase) {
        if (asset == _props.base) {
            return 10 ** _props.decimals;
        }

        uint256 assetPrice = _getAssetPrice(asset);

        /// Asset is already denominated in base asset so return it as is.
        if (_isNormalized[asset]) {
            priceInBase = assetPrice;
        } else {
            /// If asset isn't in base asset, it should be 18 fixed point USD value.
            uint256 baseAssetPriceUsd = _getAssetPrice(_props.base);
            priceInBase = (assetPrice * 10 ** _props.decimals) / baseAssetPriceUsd;
        }
    }

    function _getAssetPrice(address asset) internal view returns (uint256 assetPrice) {
        Providers memory provider = _providers[asset];

        if (address(provider.primary) == address(0)) {
            revert UnsupportedAsset(asset);
        }

        try provider.primary.getAssetPrice(asset) returns (uint256 _primaryPrice) {
            assetPrice = _primaryPrice;
        } catch {
            try provider.backup.getAssetPrice(asset) returns (uint256 _fallbackPrice) {
                assetPrice = _fallbackPrice;
            } catch {
                revert PriceRetrievalFailed(asset, address(provider.primary), address(provider.backup));
            }
        }
    }

    function getAssetPriceProviders(address asset) public view returns (Providers memory) {
        return _providers[asset];
    }
}
