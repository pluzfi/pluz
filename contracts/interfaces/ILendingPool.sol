// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

interface ILendingPool {
    function allowedLenders(address lender) external view returns (bool);

    function deposit(uint256 amount) external returns (uint256);
    function withdraw(uint256 amount) external returns (uint256);

    function getMinimumOpenBorrow() external view returns (uint256);
    function setMinimumOpenBorrow(uint256 amount) external;

    function setInterestRateStrategy(address newStrategy) external;

    function getDebtAmount(address borrower) external view returns (uint256);
    function getDepositAmount(address lender) external view returns (uint256);
    function getTotalSupply() external view returns (uint256);
    function getTotalBorrow() external view returns (uint256);

    function getUAsset() external view returns (IERC20);
    function getAsset() external view returns (IERC20);
    function getNormalizedIncome() external view returns (UD60x18);
    function getNormalizedDebt() external view returns (UD60x18);
    function accrueInterest() external;

    // PermissionedLendingPool Only
    function updateLenderStatus(address lender, bool status) external;

    // AccountManager
    function borrow(uint256 amount, address onBehalfOf) external returns (uint256);

    ///@dev Repays loan of `onBehalfOf`, transferring funds from `onBehalfOf`
    function repay(uint256 amount, address onBehalfOf) external returns (uint256);

    ///@dev Repays loan of `onBehalfOf`, transferring funds from `from`
    function repay(uint256 amount, address onBehalfOf, address from) external returns (uint256);
}
