// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity ^0.8.0;

/// @title Predeploys
/// @notice Contains constant addresses for contracts that are pre-deployed to the L2 system.
library Predeploys {

    /// @notice Address of the Shares predeploy.
    address internal constant SHARES = 0x9b2bfD735259f803EC05F5DA709eAB5a4c1D71B9;

    /// @notice Address of the rUSDC predeploy.
    address internal constant USDC_REBASING = 0x4300000000000000000000000000000000000003;

    /// @notice Address of the WETH predeploy.
    address internal constant WETH_REBASING = 0x4300000000000000000000000000000000000004;

}
