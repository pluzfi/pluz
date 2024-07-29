// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./Errors.sol";
import "../interfaces/IProtocolGovernor.sol";

/// @notice List of permissions that can be granted to addresses.
library Roles {
    /// @notice Can call the `sendYield` function on the PluzLendingPool to redirect yield back to senders.
    bytes32 public constant LEND_YIELD_SENDER = keccak256(abi.encode("LEND_YIELD_SENDER"));

    /// @notice Gas tank depositor
    bytes32 public constant GAS_TANK_DEPOSITOR = keccak256(abi.encode("GAS_TANK_DEPOSITOR"));

    /// @notice Protocol maintainer
    /// @dev A trusted address that can perform maintenance tasks. This will likely be a hot wallet.
    bytes32 public constant PROTOCOL_MAINTAINER = keccak256(abi.encode("PROTOCOL_MAINTAINER"));

    function _validateRole(
        IProtocolGovernor governor,
        address account,
        bytes32 role,
        string memory roleName
    )
        internal
        view
    {
        if (!governor.hasRole(role, account)) {
            revert Errors.UnauthorizedRole(account, roleName);
        }
    }
}
