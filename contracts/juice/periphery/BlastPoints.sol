// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../JuiceModule.sol";

/// @title BlastPoints
/// @notice Configures a hot wallet that operates the points API for this contract.
contract BlastPoints {
    IProtocolGovernor private _protocolGovernor;

    event PointsOperatorConfigured(address indexed operator);

    constructor(address protocolGovernor_, address pointsOperator_) {
        _protocolGovernor = IProtocolGovernor(protocolGovernor_);

        IBlastPoints blast = IBlastPoints(_protocolGovernor.getImmutableAddress(GovernorLib.BLAST_POINTS));
        blast.configurePointsOperator(pointsOperator_);
    }
}
