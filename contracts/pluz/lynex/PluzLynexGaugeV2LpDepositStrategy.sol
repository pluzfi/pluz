// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "../../libraries/Errors.sol";
import "../../strategyVault/uniswap/GammaNarrowUniswapV3Strategy.sol";
import "../PluzModule.sol";
import "../periphery/PluzGas.sol";
import "../periphery/PluzPoints.sol";

interface ILynexGaugeV2CLDeposit {
    // deposit amount stakeToken
    function deposit(uint256 amount) external;
    // withdraw a certain amount of stakeToken
    function withdraw(uint256 amount) external;
}

contract PluzLynexGaugeV2CLLpDepositStrategy is GammaNarrowUniswapV3Strategy, PluzModule, PluzPoints, PluzGas {
    using SafeERC20 for IERC20;

    ILynexGaugeV2CLDeposit public constant LYNEX_GAUGE_V2 =
        ILynexGaugeV2CLDeposit(0xEf79A12c48973f0193E67730C8636485Da59f0FD);

    constructor(
        address protocolGovernor_,
        VaultParams memory vaultParams_,
        InitParams memory params
    )   
        PluzModule(protocolGovernor_)
        PluzGas(protocolGovernor_)
        PluzPoints(protocolGovernor_)
        GammaNarrowUniswapV3Strategy(protocolGovernor_, vaultParams_, params)
    { }

    function _deposit(
        uint256 assets,
        bytes memory data,
        address recipient
    )
        internal
        override
        returns (uint256 receivedShares)
    {
        receivedShares = super._deposit(assets, data, recipient);
        pair.approve(address(LYNEX_GAUGE_V2), receivedShares);
        LYNEX_GAUGE_V2.deposit(receivedShares);
    }

    function _withdraw(
        address caller,
        uint256 shares,
        bytes memory data,
        address recipient
    )
        internal
        override
        returns (uint256 receivedAssets)
    {
        LYNEX_GAUGE_V2.withdraw(shares);
        receivedAssets = _removeLiquidity(caller, shares, data, recipient);
    }
}
