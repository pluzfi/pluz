// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { UD60x18, ud, UNIT, ZERO } from "@prb/math/src/UD60x18.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../libraries/Errors.sol";
import "../libraries/traits/AddressCheckerTrait.sol";
import "../libraries/GovernorLib.sol";
import "../interfaces/IProtocolGovernor.sol";
import "../libraries/Roles.sol";

abstract contract ProtocolGovernorEvents {
    event FeeUpdated(bytes32 indexed id, UD60x18 newLiquidationFee);
    event AddressSet(bytes32 indexed id, address newAddress);
    event ImmutableAddressSet(bytes32 indexed id, address newAddress);
    event ManagerStatusUpdated(address indexed manager, bool status);
    event InvestmentAccountRegistered(address indexed account);
    event InvestmentAccountCreditIncreased(address indexed account, uint256 amount);
    event InvestmentAccountCreditDecreased(address indexed account, uint256 amount);
    event RoleSet(bytes32 indexed role, address indexed account, bool status);
    event ProtocolDeprecatedStatusSet(bool status);
}

/**
 * @title ProtocolGovernor
 * @dev Allows for storing and management of common protocol data (roles, addresses, configuration).
 */
contract ProtocolGovernor is Ownable2Step, AddressCheckerTrait, ProtocolGovernorEvents, IProtocolGovernor {
    /// @notice Map of contract names to their contract addresses.
    mapping(bytes32 => address) internal _addresses;

    /// @notice Immutable map of contract names to their contract addresses.
    mapping(bytes32 => address) internal _immutableAddresses;

    /// @notice Map of fee IDs to their fees.
    /// @dev Fees cannot be greater than or equal to 100%.
    mapping(bytes32 => UD60x18) internal _fees;

    /// @notice Managers that can register accounts.
    mapping(address => bool) internal _managers;

    /// @notice Tracking roles granted to addresses.
    mapping(address => mapping(bytes32 => bool)) internal _roles;

    /// @notice If true, the protocol is deprecated and no longer accepting inflows (lending pool deposit, borrow,
    /// strategy deposit should be disabled).
    bool private _isProtocolDeprecated;

    /// @dev Parameters for initializing the Protocol Governor
    struct InitParams {
        address lendAsset; // Address of the asset
        address feeCollector;
        address pyth;
    }

    constructor(InitParams memory params)
        Ownable(msg.sender)
        nonZeroAddress(params.feeCollector)
        nonZeroAddressAndContract(params.lendAsset)
        nonZeroAddressAndContract(params.pyth)
    {
        _setImmutableAddress(GovernorLib.LEND_ASSET, params.lendAsset);
        _setImmutableAddress(GovernorLib.PYTH, params.pyth);
        _setAddress(GovernorLib.FEE_COLLECTOR, params.feeCollector);

        _fees[GovernorLib.LENDING_FEE] = ud(0.1e18);
        _fees[GovernorLib.PROTOCOL_LIQUIDATION_SHARE] = ud(0.05e18);
        _fees[GovernorLib.LIQUIDATOR_SHARE] = ZERO;
        _fees[GovernorLib.FLASH_LOAN_FEE] = ud(0);
    }

    /**
     * @dev Only allows addresses that are the protocol admin to call the function.
     */
    modifier onlyProtocolOwner() {
        if (owner() != _msgSender()) {
            revert Errors.UnauthorizedRole(_msgSender(), "PROTOCOL_ADMIN");
        }
        _;
    }

    modifier onlyManager() {
        if (!_managers[_msgSender()]) {
            revert Errors.UnauthorizedRole(_msgSender(), "ACCOUNT_MANAGER");
        }
        _;
    }

    function getOwner() external view returns (address) {
        return Ownable.owner();
    }

    function setProtocolDeprecatedStatus(bool status) external onlyProtocolOwner {
        _isProtocolDeprecated = status;
        emit ProtocolDeprecatedStatusSet(status);
    }

    function isProtocolDeprecated() external view returns (bool) {
        return _isProtocolDeprecated;
    }

    ////////////////////
    // ADDRESS PROVIDER
    //////////////////////

    /// @dev Sets an address by id
    function setAddress(bytes32 id, address addr) public onlyProtocolOwner {
        _setAddress(id, addr);
    }

    function _setAddress(bytes32 id, address addr) internal nonZeroAddress(addr) {
        _addresses[id] = addr;
        emit AddressSet(id, addr);
    }

    // @dev Initialize an address by id, this cannot be changed after being set.
    function setImmutableAddress(bytes32 id, address addr) public onlyProtocolOwner {
        _setImmutableAddress(id, addr);
    }

    function _setImmutableAddress(bytes32 id, address addr) internal nonZeroAddress(addr) {
        if (_immutableAddresses[id] != address(0)) {
            revert Errors.InvalidParams();
        }
        _immutableAddresses[id] = addr;
        emit ImmutableAddressSet(id, addr);
    }

    /// @dev Returns an address by id
    function getAddress(bytes32 id) external view returns (address) {
        return _addresses[id];
    }

    /// @dev Returns an immutable address by id
    function getImmutableAddress(bytes32 id) external view returns (address) {
        return _immutableAddresses[id];
    }

    ///////////////////////
    // FEE CONFIGURATION
    ///////////////////////

    /// @notice newFee cannot be 100% (it must be < 1e18)
    function setFee(bytes32 id, UD60x18 newFee) external onlyProtocolOwner {
        if (newFee >= UNIT) {
            revert Errors.InvalidParams();
        }
        _fees[id] = newFee;
        emit FeeUpdated(id, newFee);
    }

    function getFee(bytes32 id) external view returns (UD60x18) {
        return _fees[id];
    }

    /////////////////////
    // Protocol wide ACL
    /////////////////////

    function grantRole(bytes32 role, address account) external onlyProtocolOwner {
        _roles[account][role] = true;
        emit RoleSet(role, account, true);
    }

    function revokeRole(bytes32 role, address account) external onlyProtocolOwner {
        _roles[account][role] = false;
        emit RoleSet(role, account, false);
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[account][role];
    }

    function updateAccountManagerStatus(address manager, bool status) external onlyProtocolOwner {
        _managers[manager] = status;
        emit ManagerStatusUpdated(manager, status);
    }

    function isAccountManager(address manager) external view returns (bool) {
        return _managers[manager];
    }
}
