// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./ProtocolGovernor.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import { Errors } from "../libraries/Errors.sol";
import "../libraries/traits/AddressCheckerTrait.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import "../interfaces/IGasTank.sol";
import "../interfaces/IAssetPriceProvider.sol";
import "../interfaces/IProtocolGovernor.sol";
import "../interfaces/IStrategySlippageModel.sol";
import "../libraries/GovernorLib.sol";
import "../libraries/Roles.sol";

/**
 * @title ProtocolModule
 * @dev Contract for shared protocol functionality
 */
abstract contract ProtocolModule is Context, AddressCheckerTrait {
    using Roles for IProtocolGovernor;

    IProtocolGovernor internal immutable _protocolGovernor;

    /**
     * @dev Constructor that initializes the role store for this contract.
     * @param protocolGovernor_ The contract instance to use as the role store.
     */
    constructor(address protocolGovernor_) {
        _protocolGovernor = IProtocolGovernor(protocolGovernor_);
    }

    /////////////////
    /// PERMISSIONS
    /////////////////

    modifier whenProtocolNotDeprecated() {
        require(!_protocolGovernor.isProtocolDeprecated(), "PROTOCOL_DEPRECATED");
        _;
    }

    /**
     * @dev Only allows the contract's own address to call the function.
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Errors.UnauthorizedRole(msg.sender, "SELF");
        }
        _;
    }

    modifier onlyAccountManager() {
        if (!_protocolGovernor.isAccountManager(_msgSender())) {
            revert Errors.UnauthorizedRole(_msgSender(), "ACCOUNT_MANAGER");
        }
        _;
    }

    modifier onlyGasTankDepositor() {
        _protocolGovernor._validateRole(msg.sender, Roles.GAS_TANK_DEPOSITOR, "GAS_TANK_DEPOSITOR");
        _;
    }

    modifier onlyProtocolMaintainer() {
        _protocolGovernor._validateRole(msg.sender, Roles.PROTOCOL_MAINTAINER, "PROTOCOL_MAINTAINER");
        _;
    }

    /**
     * @dev Only allows addresses that are the protocol admin to call the function.
     */
    modifier onlyOwner() {
        if (!_isOwner(_msgSender())) {
            revert Errors.UnauthorizedRole(_msgSender(), "PROTOCOL_ADMIN");
        }
        _;
    }

    function _isOwner(address account) internal view returns (bool) {
        if (_protocolGovernor.getOwner() != account) {
            return false;
        }
        return true;
    }

    /////////////////////
    // ADDRESS PROVIDER
    /////////////////////

    function getProtocolGovernor() external view virtual returns (address) {
        return address(_protocolGovernor);
    }

    /// @notice Returns fee collector
    function _getFeeCollector() internal view returns (address) {
        return _protocolGovernor.getAddress(GovernorLib.FEE_COLLECTOR);
    }

    /// @notice Returns asset price provider address.
    /// @dev This price provider MUST return the asset prices denominated in lend asset.
    /// @dev If lend asset is USDC, asset prices must be in USDC.
    function _getPriceProvider() internal view returns (IAssetPriceProvider) {
        return IAssetPriceProvider(_protocolGovernor.getAddress(GovernorLib.PRICE_PROVIDER));
    }

    /// @notice Gas Tank
    function _getGasTank() internal view returns (IGasTank) {
        return IGasTank(_protocolGovernor.getAddress(GovernorLib.GAS_TANK));
    }

    function _getPyth() internal view returns (IPyth) {
        return IPyth(_protocolGovernor.getImmutableAddress(GovernorLib.PYTH));
    }

    function _getLendAsset() internal view returns (address) {
        return _protocolGovernor.getImmutableAddress(GovernorLib.LEND_ASSET);
    }

    function _getLendingPool() internal view returns (address) {
        return _protocolGovernor.getImmutableAddress(GovernorLib.LENDING_POOL);
    }

    function _getSlippageModel() internal view returns (IStrategySlippageModel) {
        return IStrategySlippageModel(_protocolGovernor.getAddress(GovernorLib.STRATEGY_SLIPPAGE_MODEL));
    }

    // FEE CONFIGURATION
    //////////////////////

    function _lendingFee() internal view returns (UD60x18) {
        return _protocolGovernor.getFee(GovernorLib.LENDING_FEE);
    }

    function _flashLoanFee() internal view returns (UD60x18) {
        return _protocolGovernor.getFee(GovernorLib.FLASH_LOAN_FEE);
    }

    function _protocolLiquidationShare() internal view returns (UD60x18) {
        return _protocolGovernor.getFee(GovernorLib.PROTOCOL_LIQUIDATION_SHARE);
    }

    function _liquidatorShare() internal view returns (UD60x18) {
        return _protocolGovernor.getFee(GovernorLib.LIQUIDATOR_SHARE);
    }
}
