// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../solady/src/tokens/ERC20.sol";
import "../libraries/accounts/AccountLib.sol";
import "../interfaces/IAccountManager.sol";

interface IAccount {
    /// @notice How much was borrowed from the lending pool
    event Borrow(uint256 amount);
    /// @notice How much debt was paid back to the lending pool
    event Repay(uint256 amount);

    /// @dev Returns a unique identifier distinguishing this type of account
    function getKind() external view returns (bytes32);

    function getManager() external view returns (IAccountManager);
    function initialize(address owner_) external;

    function pause() external;
    function unpause() external;

    /// Owner interactions

    function borrow(uint256 amount) external payable;
    function repay(uint256 amount) external payable;
    function claim(uint256 amount) external payable;
    function claim(uint256 amount, address recipient) external payable;
}
