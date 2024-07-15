// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lendingPool/LendingPool.sol";
import { mulDiv } from "@prb/math/src/Common.sol";
import "./JuiceModule.sol";
import "../external/blast/IERC20Rebasing.sol";
import "../libraries/Errors.sol";
import "./periphery/BlastGas.sol";
import "./periphery/BlastPoints.sol";

/// @title Juice Lending Pool
/// @notice This contract extends LendingPool to account for Blast native features - USDB yield and gas refunds.
contract JuiceLendingPool is LendingPool, JuiceModule, BlastGas, BlastPoints {
    using SafeERC20 for IERC20;

    uint256 public MINIMUM_COMPOUND_AMOUNT = 1e6;

    struct InitParams {
        address interestRateStrategy;
        address blastPointsOperator;
        uint256 minimumOpenBorrow;
        bool isAutoCompounding;
    }

    bool public isAutoCompounding;

    constructor(
        address protocolGovernor_,
        InitParams memory params
    )
        BlastGas(protocolGovernor_)
        BlastPoints(protocolGovernor_, params.blastPointsOperator)
        JuiceModule(protocolGovernor_)
        LendingPool(
            protocolGovernor_,
            LendingPool.BaseInitParams({
                interestRateStrategy: params.interestRateStrategy,
                minimumOpenBorrow: params.minimumOpenBorrow
            })
        )
    {
        isAutoCompounding = params.isAutoCompounding;
        IERC20Rebasing(address(reserve.asset)).configure(YieldMode.CLAIMABLE);
    }

    function toggleAutoCompounding() public onlyOwner {
        isAutoCompounding = !isAutoCompounding;
    }

    function getNormalizedIncome() public view override returns (UD60x18) {
        uint256 timestamp = reserve.lastUpdateTimestamp;

        // slither-disable-next-line incorrect-equality
        if (timestamp == block.timestamp) {
            return reserve.liquidityIndex;
        }

        uint256 claimableYield = IERC20Rebasing(address(reserve.asset)).getClaimableAmount(address(this));
        UD60x18 pendingUsdbYield = ud(reserve.assetBalance + claimableYield).div(ud(reserve.assetBalance));

        return MathUtils.calculateCompoundedInterest(reserve.liquidityRate, timestamp).mul(reserve.liquidityIndex).mul(
            pendingUsdbYield
        );
    }

    /// @notice Accrue USDB yield earned from idle reserve assets and distribute it to depositors.
    function compound() external nonReentrant returns (uint256 earned) {
        earned = _compound();
    }

    /// @notice Pull USDB yield from some address and distribute it to depositors.
    function sendYield(uint256 amount) external onlyLendYieldSender {
        uint256 reserveBalanceBefore = reserve.assetBalance;
        IERC20(reserve.asset).safeTransferFrom(msg.sender, address(this), amount);
        _accrueYield(reserveBalanceBefore, amount);
    }

    function _compound() internal returns (uint256 earned) {
        IERC20Rebasing usdb = IERC20Rebasing(address(reserve.asset));
        earned = usdb.getClaimableAmount(address(this));

        // Avoid compounding dust.
        if (earned >= MINIMUM_COMPOUND_AMOUNT) {
            uint256 reserveBalanceBefore = reserve.assetBalance;
            earned = usdb.claim(address(this), earned);
            _accrueYield(reserveBalanceBefore, earned);
        }
    }

    function _beforeAction() internal override {
        _accrueInterest();
        if (isAutoCompounding) {
            _compound();
        }
    }

    /// @notice Accrues yield into liquidityIndex.
    function _accrueYield(uint256 assetBalanceBefore, uint256 yieldClaimed) internal {
        reserve.assetBalance += yieldClaimed;
        reserve.liquidityIndex = (ud(reserve.assetBalance).mul(reserve.liquidityIndex)).div(ud(assetBalanceBefore));
        emit LiquidityIndexUpdated(reserve.liquidityIndex);
    }
}
