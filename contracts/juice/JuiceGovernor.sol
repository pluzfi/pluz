// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../system/ProtocolGovernor.sol";
import "../external/blast/IBlast.sol";

/**
 * @title JuiceGovernor
 * @dev Allows for storing and management of protocol data related to our Blast deployment.
 */
contract JuiceGovernor is ProtocolGovernor {
    constructor(
        InitParams memory params,
        address blast,
        address blastPoints
    )
        ProtocolGovernor(params)
        nonZeroAddressAndContract(blast)
        nonZeroAddressAndContract(blastPoints)
    {
        _setImmutableAddress(GovernorLib.BLAST, blast);
        _setImmutableAddress(GovernorLib.BLAST_POINTS, blastPoints);
    }
}
 