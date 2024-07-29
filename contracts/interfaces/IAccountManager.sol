// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import "../libraries/accounts/AccountLib.sol";
import "./ILiquidationReceiver.sol";

interface IAccountManager {
    function lendingPool() external view returns (address);
    function isApprovedStrategy(address strategy) external view returns (bool);
    function isLiquidationReceiver(address receiver) external view returns (bool);

    function pauseAccount(address account) external;
    function unpauseAccount(address account) external;

    function getFeeCollector() external view returns (address);
    function getLiquidationReceiver(
        address account,
        address liquidationFeeTo
    )
        external
        view
        returns (ILiquidationReceiver);
    function getLiquidationFee() external returns (AccountLib.LiquidationFee memory);

    // Following three functions are only callable by the target Account itself.
    function borrow(uint256 amount) external returns (uint256 borrowedAmount);
    function repay(address account, uint256 amount) external returns (uint256 repaidAmount);
    function claim(uint256 amount, address recipient) external;

    function liquidate(address account, address liquidationFeeTo) external returns (ILiquidationReceiver);

    /// @notice Deposits assets into a strategy on behalf of msg.sender, which must be an Account.
    function strategyDeposit(
        address owner,
        address strategy,
        uint256 assets,
        bytes memory data
    )
        external
        payable
        returns (uint256 shares);
    function strategyWithdrawal(address owner, address strategy, uint256 assets) external;

    function setAllowedAccountsMode(bool status) external;
    function setAllowedAccountStatus(address account, bool status) external;

    /// @dev Some strategies have an execution fee that needs to be paid for withdrawal so that must be sent to this
    /// function.
    function liquidateStrategy(
        address account,
        address liquidationFeeTo,
        address strategy,
        bytes memory data
    )
        external
        payable
        returns (ILiquidationReceiver);

    function emitLiquidationFeeEvent(
        address feeCollector,
        address liquidationFeeTo,
        uint256 protocolShare,
        uint256 liquidatorShare
    )
        external;

    function getLendingPoolUAsset() external view returns (IERC20);
    function getLendAsset() external view returns (IERC20);
    function getDebtAmount(address account) external view returns (uint256);
    function getTotalCollateralValue(address account) external view returns (uint256 totalValue);

    function getAccountLoan(address account) external view returns (AccountLib.Loan memory loan);
    function getAccountHealth(address account) external view returns (AccountLib.Health memory health);

    /// @notice Returns whether or not an account is liquidatable. If true, return the timestamp its liquidation started
    /// at.
    function getAccountLiquidationStatus(address account) external view returns (AccountLib.LiquidationStatus memory);
}
