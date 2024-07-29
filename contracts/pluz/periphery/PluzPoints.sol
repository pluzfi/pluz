// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../PluzModule.sol";

/// @title PluzPoints
/// @notice Configures a hot wallet that operates the points API for this contract.
contract PluzPoints {
    IProtocolGovernor private _protocolGovernor;

    event PointsOperatorConfigured(address indexed operator);

    constructor(address protocolGovernor_) {
        _protocolGovernor = IProtocolGovernor(protocolGovernor_);

    }
}
