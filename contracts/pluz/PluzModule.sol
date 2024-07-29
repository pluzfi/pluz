// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./PluzGovernor.sol";
import "../system/ProtocolModule.sol";
import "../libraries/Roles.sol";

/**
 * @title PluzModule
 */
abstract contract PluzModule is AddressCheckerTrait {
    using Roles for IProtocolGovernor;

    IProtocolGovernor private _protocolGovernor;

    /**
     * @dev Constructor that initializes the Pluz Governor for this contract.
     *
     * @param pluzGovernor_ The contract instance to use as the Pluz Governor.
     */
    constructor(address pluzGovernor_) nonZeroAddressAndContract(pluzGovernor_) {
        _protocolGovernor = IProtocolGovernor(pluzGovernor_);
    }

    modifier onlyLendYieldSender() {
        _protocolGovernor._validateRole(msg.sender, Roles.LEND_YIELD_SENDER, "LEND_YIELD_SENDER");
        _;
    }

}
