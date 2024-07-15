// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Errors } from "../../libraries/Errors.sol";
import "../../strategyVault/uniswap/OmegaUniswapV2Strategy.sol";
import "../JuiceModule.sol";
import "../periphery/BlastGas.sol";
import "../periphery/BlastPoints.sol";

interface IHyperlockPointsDeposit {
    // Stake ERC20 token, `_lock` is the amount of time to lock for in seconds
    function stake(address _lpToken, uint256 _amount, uint256 _lock) external;
    // unstake ERC20 token
    function unstake(address _lpToken, uint256 _amount) external;
}

contract JuiceHyperlockERC20PointsDepositStrategy is OmegaUniswapV2Strategy, JuiceModule, BlastPoints, BlastGas {
    using SafeERC20 for IERC20;

    IHyperlockPointsDeposit public constant HYPERLOCK_POINTS =
        IHyperlockPointsDeposit(0xC3EcaDB7a5faB07c72af6BcFbD588b7818c4a40e);

    constructor(
        address protocolGovernor_,
        address pointsOperator_,
        VaultParams memory vaultParams_,
        InitParams memory params
    )   
        JuiceModule(protocolGovernor_)
        BlastGas(protocolGovernor_)
        BlastPoints(protocolGovernor_, pointsOperator_)
        OmegaUniswapV2Strategy(protocolGovernor_, vaultParams_, params)
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
        pair.approve(address(HYPERLOCK_POINTS), receivedShares);
        HYPERLOCK_POINTS.stake(address(pair), receivedShares, 0);
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
        HYPERLOCK_POINTS.unstake(address(pair), shares);
        receivedAssets = _removeLiquidity(caller, shares, data, recipient);
    }
}
