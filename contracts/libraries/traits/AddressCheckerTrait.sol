// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../Errors.sol";

/// @title Address checker trait
/// @notice Introduces methods and modifiers for checking addresses
abstract contract AddressCheckerTrait {
    /// @dev Prevents a contract using an address if it is a zero address
    modifier nonZeroAddress(address _address) {
        if (_address == address(0)) {
            revert Errors.ZeroAddress();
        }
        _;
    }

    /// @dev Prevents a contract using an address if it is either a zero address or is not an existing contract
    modifier nonZeroAddressAndContract(address _address) {
        if (_address == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (!_contractExists(_address)) {
            revert Errors.ContractDoesNotExist();
        }
        _;
    }

    /// @notice Returns true if addr is a contract address
    /// @param addr The address to check
    function _contractExists(address addr) internal view returns (bool) {
        return addr.code.length > 0;
    }
}
