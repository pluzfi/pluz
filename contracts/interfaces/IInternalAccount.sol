// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../solady/src/tokens/ERC20.sol";
import "./IAccount.sol";

interface IInternalAccount is IAccount {
    function strategyDeposit(address strategy, uint256 amount) external;
    function strategyWithdraw(address strategy, uint256 amount) external;
    function liquidateStrategy(
        address strategy,
        address recipient,
        uint256 minAmount,
        bytes memory data
    )
        external
        payable;
}
