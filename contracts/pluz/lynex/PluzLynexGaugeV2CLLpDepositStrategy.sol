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

    function getReward() external;
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
        gamma.approve(address(LYNEX_GAUGE_V2), receivedShares);
        LYNEX_GAUGE_V2.deposit(receivedShares);
        stakingToken.mint(address(this), receivedShares);
        IERC20(address(stakingToken)).approve(address(rewardTracker), receivedShares);
        rewardTracker.stakeForAccount(address(this), recipient, address(stakingToken), receivedShares);
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
        _claimAndDistributeRewards();

        rewardTracker.unstakeForAccount(caller, address(stakingToken), shares, address(this));
        stakingToken.burn(address(this), shares);
        LYNEX_GAUGE_V2.withdraw(shares);
        receivedAssets = _removeLiquidity(caller, shares, data, recipient);
    }

    function _claimAndDistributeRewards() private {
        LYNEX_GAUGE_V2.getReward();

        uint256 totalRewards = rewardToken.balanceOf(address(this));
        if (totalRewards > 0) {
            uint256 treasuryShare = (totalRewards * treasuryRate) / 10000;
            rewardToken.safeTransfer(treasury, treasuryShare);

            uint256 remainingRewards = totalRewards - treasuryShare;
            rewardToken.safeTransfer(address(rewardDistributor), remainingRewards);
        }
    }

    function _claimRewards(address caller, address owner) internal override returns (uint256[] memory rewards) {
        _claimAndDistributeRewards();

        uint256[] memory claimableRewards = rewardTracker.claimable(caller);
        bool hasClaimable = false;

        for (uint256 i = 0; i < claimableRewards.length; i++) {
            if (claimableRewards[i] > 0) {
                hasClaimable = true;
                break;
            }
        }
        require(hasClaimable, "No rewards available for claim");

        rewards = rewardTracker.claimForAccount(caller, owner);
    }
}
