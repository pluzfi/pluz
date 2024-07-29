// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../system/ProtocolGovernor.sol";

/**
 * @title PluzGovernor
 * @dev Allows for storing and management of protocol data related to our Linea deployment.
 */
contract PluzGovernor is ProtocolGovernor {
    constructor(InitParams memory params)
        ProtocolGovernor(params)
    {

    }
}
