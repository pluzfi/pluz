// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { ProtocolModule, ProtocolGovernor } from "../system/ProtocolModule.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MathUtils } from "../libraries/math/MathUtils.sol";
import { UD60x18, ud, UNIT, ZERO } from "@prb/math/src/UD60x18.sol";
import { IInterestRateStrategy } from "../interfaces/IInterestRateStrategy.sol";
import { ICollateralAggregator } from "../interfaces/ICollateralAggregator.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { OmegaDebtToken } from "./OmegaDebtToken.sol";
import { OmegaLiquidityToken } from "./OmegaLiquidityToken.sol";
import "../libraries/LendingLib.sol";
import "../libraries/Errors.sol";
import "../interfaces/IFlashLoanLender.sol";
import "../interfaces/ILendingPool.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "../external/pluz/IERC20Rebasing.sol";

// Note: Areas for improvement
// 1. Compound interest, need to understand how debt amount and utilization contribute to linear interest
// 2. Unit, what should be way/ray/percentage
//    a. Make a table for this or document it better inline
// 3. LTV vs liquidation threshold, maybe use threshold be consistent with aave

/// @notice Lending Pool Events
/// @dev Place all events used by the LendingPool contract here
abstract contract LendingPoolEvents {
    /// @notice A `lender` has deposited `amount` of assets into the pool
    event Deposit(address indexed lender, uint256 amount);
    /// @notice A `lender` has withdrawn `amount` of assets from the pool
    event Withdraw(address indexed lender, uint256 amount);
    /// @notice A `borrower` has borrowed `amount` of assets from the pool
    event Borrow(address indexed borrower, uint256 amount);
    /// @notice A `borrower` has repaid `amount` of assets to the pool
    event Repay(address indexed borrower, uint256 amount);
    /// @notice The borrow rate has been updated to `rate`, indicating a change in the interest rate for borrowers
    event BorrowRateUpdated(UD60x18 rate);
    /// @notice The borrow index has been updated to `index`, indicating the interest accrued on borrowers debt
    event BorrowIndexUpdated(UD60x18 index);
    /// @notice The liquidity rate has been updated to `rate`, indicating a change in the interest rate for lenders
    event LiquidityRateUpdated(UD60x18 rate);
    /// @notice The liquidity index has been updated to `index`, indicating the interest accrued on lenders deposits
    event LiquidityIndexUpdated(UD60x18 index);
    /// @notice The interest rate strategy has been updated to `newStrategy`
    event InterestRateStrategyUpdated(address newStrategy);
    /// @notice The deposit cap has been updated to `newDepositCap`
    event DepositCapUpdated(uint256 newDepositCap);
    /// @notice Event when a flash loan has occurred
    event FlashLoan(IERC20 indexed initiator, uint256 amount, uint256 fee);
    /// @notice Minimum borrow has been updated to `newMinimumBorrow`
    event MinimumBorrowUpdated(uint256 newMinimumBorrow);
}

/// @title   Lending Pool
/// @notice  The LendingPool contract manages the depositing and borrowing of assets
contract LendingPool is Pausable, ILendingPool, IFlashLoanLender, ProtocolModule, LendingPoolEvents, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The debt token
    OmegaDebtToken public immutable debtToken;

    /// @notice The liquidity token
    OmegaLiquidityToken public immutable liquidityToken;

    /// @notice Contract that calculates the interest rate
    IInterestRateStrategy public strategy;

    /// @notice The reserve state
    LendingLib.Reserve public reserve;

    /// @notice The cap to apply to deposits
    uint256 public depositCap;

    /// @notice Minimum amount of fees that can be collected
    uint256 private _minimumFeeCollectionAmount;

    /// @notice Minimum open borrow a user can have.
    uint256 internal _minimumOpenBorrow;

    /// @notice The user asset
    IERC20 private immutable _actualAsset;

    struct BaseInitParams {
        address interestRateStrategy;
        uint256 minimumOpenBorrow;
    }

    constructor(
        address protocolGovernor_,
        BaseInitParams memory params
    )
        nonZeroAddress(_getLendAsset())
        nonZeroAddress(params.interestRateStrategy)
        ProtocolModule(protocolGovernor_)
        nonZeroAddress(_getFeeCollector())
    {
        reserve = LendingLib.Reserve({
            asset: IERC20(_getLendAsset()),
            assetBalance: 0,
            borrowRate: ZERO,
            liquidityRate: ZERO,
            liquidityIndex: UNIT,
            borrowIndex: UNIT,
            lastUpdateTimestamp: block.timestamp
        });

        /// TODO: create params struct and tune these params
        uint8 decimals = IERC20Metadata(address(reserve.asset)).decimals();
        _minimumFeeCollectionAmount = 10 ** decimals;

        debtToken = new OmegaDebtToken(address(this), decimals);
        liquidityToken = new OmegaLiquidityToken(address(this), decimals);

        strategy = IInterestRateStrategy(params.interestRateStrategy);
        _minimumOpenBorrow = params.minimumOpenBorrow;

        // The initial deposit cap is set ot the max
        depositCap = type(uint256).max;

        _actualAsset = IERC20(IERC20Rebasing(address(reserve.asset)).getActualAsset());
        // Approve rebasing token to transfer assets
        _actualAsset.safeIncreaseAllowance(address(reserve.asset), type(uint256).max);
    }

    ////////////////////
    // Administrative functions
    ////////////////////

    /// @notice Change the contract defining how interest rates respond to utilization
    /// @param newStrategy Address of interest rate strategy to update to
    function setInterestRateStrategy(address newStrategy) external nonZeroAddress(newStrategy) onlyOwner {
        strategy = IInterestRateStrategy(newStrategy);
        (UD60x18 liquidityRate, UD60x18 borrowRate) = strategy.calculateInterestRate(ud(0.5e18));
        // strategy address can't be zero and at 50% utilization, borrow rate must be greater than liquidity rate
        if (borrowRate <= liquidityRate) revert Errors.InvalidParams();
        // Accrue interest
        _accrueInterest();
        // Update interest rate
        _updateInterestRate();
        emit InterestRateStrategyUpdated(newStrategy);
    }

    function getMinimumOpenBorrow() external view returns (uint256) {
        return _minimumOpenBorrow;
    }

    function setMinimumOpenBorrow(uint256 minimumOpenBorrow) external onlyOwner {
        _minimumOpenBorrow = minimumOpenBorrow;
    }

    function updateLenderStatus(address lender, bool status) external virtual override { }

    function setDepositCap(uint256 newDepositCap) external onlyOwner {
        depositCap = newDepositCap;
        emit DepositCapUpdated(newDepositCap);
    }

    /// @notice Let the owner pause deposits and borrows
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Let the owner unpause deposits and borrows
    function unpause() external onlyOwner {
        _unpause();
    }

    ////////////////////
    // Lending Methods
    ////////////////////

    /// @notice Public function for accruing interest rate so that users don't have to perform actions to update
    /// indices.
    function accrueInterest() public {
        _accrueInterest();
        _updateInterestRate();
    }

    function _convertAmount(uint256 amount, IERC20Rebasing asset) internal view returns (uint256) {
        uint256 actualDecimals = asset.getActualAssetDecimals();
        uint256 convertedAmount = amount;

        if (actualDecimals == 6) {
            convertedAmount = amount / 10**12;
        } else if (actualDecimals != 18) {
            // Ensure only 6 or 18 decimals are handled
            revert Errors.InvalidDecimals();
        }

        return convertedAmount;
    }

    /// @notice         Deposit underlying assets into the pool
    /// @param amount   The amount of underlying assets to deposit
    function deposit(uint256 amount)
        public
        virtual
        whenProtocolNotDeprecated
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (depositCap != type(uint256).max && amount + getTotalSupply() > depositCap) {
            revert Errors.DepositCapExceeded();
        }

        _beforeAction();

        reserve.assetBalance += amount;
        
        uint256 convertAmount = _convertAmount(amount, IERC20Rebasing(address(reserve.asset)));

        _actualAsset.safeTransferFrom(msg.sender, address(this), convertAmount);
        IERC20Rebasing(address(reserve.asset)).wrap(amount);
        liquidityToken.mint(msg.sender, amount, reserve.liquidityIndex, MathUtils.ROUNDING.DOWN);

        _mintToTreasury();
        _updateInterestRate();

        emit Deposit(msg.sender, amount);
        return amount;
    }

    /// @notice Withdraw underlying assets from the pool. If argument is uint256 max, then withdraw everything.
    /// @param amount The amount of underlying assets to withdraw
    function withdraw(uint256 amount) public virtual whenNotPaused nonReentrant returns (uint256) {
        uint256 amountToWithdraw = amount;
        
        _beforeAction();

        bool isMaxWithdraw = false;

        uint256 userBalance = liquidityToken.balanceOf(msg.sender);

        if (amount >= userBalance) {
            amountToWithdraw = userBalance;
            isMaxWithdraw = true;
        }

        uint256 convertAmount = _convertAmount(amountToWithdraw, IERC20Rebasing(address(reserve.asset)));
        
        reserve.assetBalance -= amountToWithdraw;

        liquidityToken.burn(msg.sender, amountToWithdraw, reserve.liquidityIndex, isMaxWithdraw, MathUtils.ROUNDING.UP);
        IERC20Rebasing(address(reserve.asset)).unwrap(amountToWithdraw);
        _actualAsset.safeTransfer(msg.sender, convertAmount);

        _mintToTreasury();
        _updateInterestRate();

        emit Withdraw(msg.sender, amountToWithdraw);
        return amountToWithdraw;
    }

    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes memory userData
    )
        external
        virtual
        nonZeroAddress(receiverAddress)
        whenNotPaused
        nonReentrant
        returns (bytes memory)
    {
        if (asset != address(reserve.asset)) {
            revert Errors.InvalidFlashLoanAsset();
        }

        uint256 balanceBefore = reserve.asset.balanceOf(address(this));
        uint256 expectedFee = ud(amount).mul(_flashLoanFee()).unwrap();

        if (amount > balanceBefore) {
            revert Errors.InvalidFlashLoanBalance();
        }

        reserve.asset.safeTransfer(receiverAddress, amount);

        (bool success, bytes memory result) = IFlashLoanRecipient(receiverAddress).receiveFlashLoanSimple(
            msg.sender, reserve.asset, amount, expectedFee, userData
        );

        if (!success) {
            revert Errors.InvalidFlashLoanRecipientReturn();
        }

        uint256 balanceAfter = reserve.asset.balanceOf(address(this));
        if (balanceBefore > balanceAfter) {
            revert Errors.InvalidPostFlashLoanBalance();
        }

        uint256 fee = balanceAfter - balanceBefore;
        if (expectedFee > fee) {
            revert Errors.InsufficientFlashLoanFeeAmount();
        }

        if (fee > 0) {
            reserve.asset.safeTransfer(_getFeeCollector(), fee);
        }

        emit FlashLoan(reserve.asset, amount, fee);

        return result;
    }

    //////////////////////////
    // Account Managers only
    //////////////////////////

    function borrow(
        uint256 amount,
        address onBehalfOf
    )
        external
        whenProtocolNotDeprecated
        whenNotPaused
        onlyAccountManager
        nonReentrant
        returns (uint256)
    {
        if (amount > reserve.asset.balanceOf(address(this))) {
            revert Errors.InsufficientLiquidity();
        }

        uint256 convertAmount = _convertAmount(amount, IERC20Rebasing(address(reserve.asset)));

        _beforeAction();

        reserve.assetBalance -= amount;

        debtToken.mint(onBehalfOf, amount, reserve.borrowIndex, MathUtils.ROUNDING.UP);
        IERC20Rebasing(address(reserve.asset)).unwrap(amount);
        _actualAsset.safeTransfer(onBehalfOf, convertAmount);

        _mintToTreasury();
        _updateInterestRate();

        if (amount < _minimumOpenBorrow) {
            revert Errors.InvalidMinimumOpenBorrow();
        }

        emit Borrow(onBehalfOf, amount);

        return amount;
    }

    function repay(
        uint256 amount,
        address onBehalfOf
    )
        external
        whenNotPaused
        onlyAccountManager
        nonReentrant
        returns (uint256)
    {
        return _repay(amount, onBehalfOf, onBehalfOf);
    }

    function repay(
        uint256 amount,
        address onBehalfOf,
        address from
    )
        public
        virtual
        whenNotPaused
        onlyAccountManager
        nonReentrant
        returns (uint256)
    {
        return _repay(amount, onBehalfOf, from);
    }

    ////////////////////////
    // Tokenization Methods
    ////////////////////////

    /// @notice             Get the borrower's debt balance
    /// @param borrower     The address of the borrower
    /// @return debt        The amount of debt the borrower has
    function getDebtAmount(address borrower) external view returns (uint256 debt) {
        debt = debtToken.balanceOf(borrower);
    }

    /// @notice             Get the lender's deposit balance
    /// @param lender       The address of the lender
    /// @return balance     The amount of the lender's deposit
    function getDepositAmount(address lender) external view returns (uint256 balance) {
        balance = liquidityToken.balanceOf(lender);
    }

    /// @notice Get the total amount of liquidity
    function getTotalSupply() public view returns (uint256) {
        return ud(liquidityToken.scaledTotalSupply()).mul(reserve.liquidityIndex).unwrap();
    }

    /// @notice Get the total amount of outstanding debt
    function getTotalBorrow() public view returns (uint256) {
        return ud(debtToken.scaledTotalSupply()).mul(reserve.borrowIndex).unwrap();
    }

    //////////////////////////
    // Views
    //////////////////////////

    /// @notice Returns the actual asset used for wrap/unwrap
    function getActualAsset() public view returns (IERC20) {
        return _actualAsset;
    }

    /// @notice Returns the asset used for deposits/borrows
    function getAsset() public view returns (IERC20) {
        return reserve.asset;
    }

    /// @notice Returns the current liquidity rate
    function getLiquidityRate() public view returns (UD60x18) {
        return reserve.liquidityRate;
    }

    /// @notice Returns the current borrow rate
    function getBorrowRate() public view returns (UD60x18) {
        return reserve.borrowRate;
    }

    /// @notice Returns the ongoing normalized income for the reserve
    ///  A value of 1e18 means there is no income. As time passes, the income is accrued
    ///  A value of 2*1e18 means for each unit of asset one unit of income has been accrued
    /// @return normalizedIncome The normalized income.
    function getNormalizedIncome() public view virtual returns (UD60x18) {
        uint256 timestamp = reserve.lastUpdateTimestamp;

        // slither-disable-next-line incorrect-equality
        if (timestamp == block.timestamp) {
            return reserve.liquidityIndex;
        }

        return MathUtils.calculateCompoundedInterest(reserve.liquidityRate, timestamp).mul(reserve.liquidityIndex);
    }

    /// @notice Returns the ongoing normalized variable debt for the reserve
    ///  A value of 1e18 means there is no debt. As time passes, the income is accrued
    ///  A value of 2*1e18 means that for each unit of debt, one unit worth of interest has been accumulated
    /// @return normalizedDebt The normalized variable debt.
    function getNormalizedDebt() public view returns (UD60x18) {
        uint256 timestamp = reserve.lastUpdateTimestamp;

        // slither-disable-next-line incorrect-equality
        if (timestamp == block.timestamp) {
            return reserve.borrowIndex;
        }

        return MathUtils.calculateCompoundedInterest(reserve.borrowRate, timestamp).mul(reserve.borrowIndex);
    }

    function allowedLenders(address lender) external view virtual override returns (bool) { }

    /////////////
    // Internal
    /////////////

    /// @notice Repay `amount` of assets to the pool for a `borrower`
    /// @param amount The amount of underlying assets to repay
    /// @param borrower The borrower to repay for
    /// @param from The address from which to transfer the funds
    function _repay(uint256 amount, address borrower, address from) internal returns (uint256) {
        _beforeAction();

        uint256 paybackAmount = amount;

        // Repay rest of debt
        uint256 debtAmount = debtToken.balanceOf(borrower);

        bool isMaxRepay = false;

        if (paybackAmount >= debtAmount) {
            paybackAmount = debtAmount;
            isMaxRepay = true;
        }

        uint256 convertAmount = _convertAmount(paybackAmount, IERC20Rebasing(address(reserve.asset)));

        reserve.assetBalance += paybackAmount;

        debtToken.burn(borrower, paybackAmount, reserve.borrowIndex, isMaxRepay, MathUtils.ROUNDING.DOWN);

        _actualAsset.safeTransferFrom(from, address(this), convertAmount);
        IERC20Rebasing(address(reserve.asset)).wrap(paybackAmount);

        _mintToTreasury();
        _updateInterestRate();

        uint256 remainingDebt = debtToken.balanceOf(borrower);
        if (remainingDebt > 0 && remainingDebt < _minimumOpenBorrow) {
            revert Errors.InvalidMinimumOpenBorrow();
        }

        emit Repay(borrower, paybackAmount);
        return paybackAmount;
    }

    /// @notice  Update the liquidity and borrow indices based off the last interest rates.
    /// @dev     This function should be called before any deposit, withdraw, borrow, or repay
    /// @dev     This mirrors Aave Protocol's update index functions
    function _accrueInterest() internal {
        // Get the current interest rate

        if (reserve.liquidityRate > ZERO) {
            // Calculate cumulative liquidity interest since last update
            UD60x18 cumulatedLiquidityInterest =
                MathUtils.calculateCompoundedInterest(reserve.liquidityRate, reserve.lastUpdateTimestamp);

            // Accumulate interest into the liquidity index
            reserve.liquidityIndex = cumulatedLiquidityInterest.mul(reserve.liquidityIndex);

            // Calculate cumulative borrow interest since last update
            UD60x18 cumulatedBorrowInterest =
                MathUtils.calculateCompoundedInterest(reserve.borrowRate, reserve.lastUpdateTimestamp);

            reserve.borrowIndex = cumulatedBorrowInterest.mul(reserve.borrowIndex);

            emit LiquidityIndexUpdated(reserve.liquidityIndex);
            emit BorrowIndexUpdated(reserve.borrowIndex);
        }

        reserve.lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @dev Update the current interest rate based on the strategy
     */
    function _updateInterestRate() internal {
        // Calculate the current interest rate

        // Available liquidity is the amount current balance left in the reserve
        uint256 totalDebt = getTotalBorrow();
        uint256 availableLiquidity = reserve.assetBalance;

        // Utilization is: debt / (available liquidity + debt)
        UD60x18 utilization = ZERO;
        if (totalDebt > 0) {
            utilization = ud(totalDebt).div(ud(availableLiquidity + totalDebt));
        }

        UD60x18 baseLiquidityRate;

        (baseLiquidityRate, reserve.borrowRate) = strategy.calculateInterestRate(utilization);

        // The effective liquidity rate is the liquidity rate minus the lending fee
        // If lenders should earn 10% and lending fee is 10%, then they should earn 10% * (100% - 10%) or 9%.
        reserve.liquidityRate = baseLiquidityRate.mul(UNIT.sub(_lendingFee()));

        emit BorrowRateUpdated(reserve.borrowRate);
        emit LiquidityRateUpdated(reserve.liquidityRate);
    }

    function _mintToTreasury() internal {
        uint256 totalLiquidityTokens = liquidityToken.totalSupply();
        uint256 totalDebtAndUnusedTokens = debtToken.totalSupply() + reserve.assetBalance;

        if (totalDebtAndUnusedTokens > totalLiquidityTokens) {
            uint256 liquidityTokensToMint = totalDebtAndUnusedTokens - totalLiquidityTokens;
            // Because the math rounds down, dust will be accumulated in pool. This ensures we aren't pulling that dust
            // every time.
            if (liquidityTokensToMint > _minimumFeeCollectionAmount) {
                liquidityToken.mint(
                    _getFeeCollector(), liquidityTokensToMint, reserve.liquidityIndex, MathUtils.ROUNDING.DOWN
                );
            }
        }
    }

    function _beforeAction() internal virtual {
        _accrueInterest();
    }
}
