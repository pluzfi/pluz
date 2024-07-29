// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../PluzModule.sol";

/// @title PluzGas
/// @notice Exposes a method to claim gas refunds from the contract and send them to the protocol.
contract PluzGas {
    IProtocolGovernor private _protocolGovernor;

    constructor(address protocolGovernor_) {
        _protocolGovernor = IProtocolGovernor(protocolGovernor_);

    }

}
