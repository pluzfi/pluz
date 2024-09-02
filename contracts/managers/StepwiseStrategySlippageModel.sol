// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../interfaces/IStrategySlippageModel.sol";
import "../libraries/Errors.sol";
import { convert, ud } from "@prb/math/src/UD60x18.sol";

/// @notice Calculates the slippage rate based on the time
contract StepwiseStrategySlippageModel is IStrategySlippageModel {
    /// @dev Parameters should treat seconds and slippage points as values of 18 fixed point decimals.
    /// If t1 is 11 seconds, should be 11 * 1e18.
    /// If minimumSlippage is 5%, should be 5 * 1e18.
    struct Props {
        UD60x18 minimumSlippage;
        UD60x18 maximumSlippage;
        UD60x18 t1;
        UD60x18 t2;
        UD60x18 baseSlippage2;
        UD60x18 slope2;
        UD60x18 baseSlippage3;
        UD60x18 slope3;
    }

    Props internal _props;

    constructor(Props memory props) {
        _props = props;
    }

    /// @param timeInSeconds is seconds since liquidation started for some Account
    /// @dev Slippage tolerance is made up of 3 equations
    /// if dt < t1, then S = dt + minimumSlippage
    /// else if dt >= t1 && dt < t2, then S = (slope2 * dt) + baseSlippage2
    /// else, S = max( (slope3 * dt) + baseSlippage3, maximumSlippage )
    function calculateSlippage(uint256 timeInSeconds) external view override returns (UD60x18 slippageTolerance) {
        UD60x18 timeInMinutes = convert(timeInSeconds / 60);

        if (timeInMinutes < _props.t1) {
            slippageTolerance = timeInMinutes + _props.minimumSlippage;
        } else if (timeInMinutes >= _props.t1 && timeInMinutes < _props.t2) {
            slippageTolerance = (timeInMinutes * _props.slope2) + _props.baseSlippage2;
        } else {
            slippageTolerance = (timeInMinutes * _props.slope3) + _props.baseSlippage3;
        }

        if (slippageTolerance > _props.maximumSlippage) {
            slippageTolerance = _props.maximumSlippage;
        }

        slippageTolerance = slippageTolerance.mul(ud(1e16));
    }

    function getParameters() external view returns (Props memory props) {
        return _props;
    }
}
