// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccount } from "./IAccount.sol";
import { IAccountManager } from "./IAccountManager.sol";

interface ILiquidationReceiver {
    struct Props {
        IERC20 asset;
        IAccountManager manager;
        IAccount account;
        address liquidationFeeTo;
    }

    function initialize(Props memory props_) external;
    function repay() external;
}
