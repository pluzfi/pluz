// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../JuiceModule.sol";

/// @title BlastGas
/// @notice Exposes a method to claim gas refunds from the contract and send them to the protocol.
contract BlastGas {
    IProtocolGovernor private _protocolGovernor;

    event GasRefundClaimed(address indexed recipient, uint256 gasClaimed);

    constructor(address protocolGovernor_) {
        _protocolGovernor = IProtocolGovernor(protocolGovernor_);

        IBlast blast = IBlast(_protocolGovernor.getImmutableAddress(GovernorLib.BLAST));
        blast.configureClaimableGas();
    }

    /// @notice Claims the maximum possible gas from the contract with some recipient.
    /// @dev This is permissionless because funds will go to the protocol gasFeeWallet and the maximum possible gas will
    /// be claimed each time.
    /// @dev IBlast.claimMaxGas guarnatees a 100% claim rate, but not all pending gas fees will be claimed.
    /// @dev To check the current gas fee information of a contract, call IBlast.readGasParams(contractAddress).
    function claimMaxGas() external returns (uint256 gasClaimed) {
        IBlast blast = IBlast(_protocolGovernor.getImmutableAddress(GovernorLib.BLAST));
        address _feeCollector = _protocolGovernor.getAddress(GovernorLib.FEE_COLLECTOR);
        gasClaimed = blast.claimMaxGas(address(this), _feeCollector);
        emit GasRefundClaimed(_feeCollector, gasClaimed);
    }
}
