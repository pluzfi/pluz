// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { UD60x18 } from "@prb/math/src/UD60x18.sol";

interface IInterestRateStrategy {
    function calculateInterestRate(UD60x18 utilization)
        external
        view
        returns (UD60x18 liquidityRate, UD60x18 borrowRate);
}
