// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "../interfaces/IProtocolGovernor.sol";
import "../libraries/GovernorLib.sol";
import "../libraries/Errors.sol";

/// @title Pyth
/// @dev Adds a method to the contract that allows bundling of Pyth price updates.
abstract contract PythPusher {
    IPyth pyth;

    function _initializePyth(address protocolGovernor_) internal {
        pyth = IPyth(IProtocolGovernor(protocolGovernor_).getImmutableAddress(GovernorLib.PYTH));
    }

    function updatePythPriceFeeds(bytes[] memory updateData) public payable {
        if (updateData.length > 0) {
            uint256 fee = pyth.getUpdateFee(updateData);
            pyth.updatePriceFeeds{ value: fee }(updateData);
        }
    }
}
