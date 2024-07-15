// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./JuiceGovernor.sol";
import "../system/ProtocolModule.sol";
import "../libraries/Roles.sol";

/**
 * @title JuiceModule
 */
abstract contract JuiceModule is AddressCheckerTrait {
    using Roles for IProtocolGovernor;

    IProtocolGovernor private _protocolGovernor;

    /**
     * @dev Constructor that initializes the Juice Governor for this contract.
     *
     * @param juiceGovernor_ The contract instance to use as the Juice Governor.
     */
    constructor(address juiceGovernor_) nonZeroAddressAndContract(juiceGovernor_) {
        _protocolGovernor = IProtocolGovernor(juiceGovernor_);
    }

    modifier onlyLendYieldSender() {
        _protocolGovernor._validateRole(msg.sender, Roles.LEND_YIELD_SENDER, "LEND_YIELD_SENDER");
        _;
    }

    function _getBlast() internal view returns (IBlast) {
        return IBlast(_protocolGovernor.getImmutableAddress(GovernorLib.BLAST));
    }

    function _getBlastPoints() internal view returns (IBlastPoints) {
        return IBlastPoints(_protocolGovernor.getImmutableAddress(GovernorLib.BLAST_POINTS));
    }
}
