// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./LendingToken.sol";

/// @title OmegaLiquidityToken
/// @notice ERC20 token representing the Lending pool deposits
/// - Extends ERC20 by adding scaledBalanceOf() and scaledTotalSupply()
/// - Overrides balanceOf() and totalSupply() to return scaled values
/// - Disables transfers other than mint and burn
///
/// @dev The underlying tokens minted and burned are scaled by the normalized income index.
/// In this way, as the income index increases, the amount of the tokens increases and user
/// balances increase. This approach closely follows the approach used by the Aave Protocol.

contract OmegaLiquidityToken is LendingToken {
    constructor(
        address pool_,
        uint8 decimals_
    )
        nonZeroAddress(pool_)
        LendingToken(pool_, decimals_, "Omega Liquidity Token", "OLT")
    { }

    /// @notice The total supply of the token scaled by the normalized debt index
    function totalSupply() public view override returns (uint256) {
        return ud(scaledTotalSupply()).mul(_pool.getNormalizedIncome()).unwrap();
    }

    /// @notice The balance of an account scaled by the normalized debt index
    function balanceOf(address account) public view override returns (uint256) {
        uint256 accountBalance = super.balanceOf(account);
        if (accountBalance == 0) {
            return 0;
        }
        return ud(accountBalance).mul(_pool.getNormalizedIncome()).unwrap();
    }
}
