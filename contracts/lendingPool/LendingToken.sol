// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../solady/src/tokens/ERC20.sol";
import { ILendingPool } from "../interfaces/ILendingPool.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import "../solady/src/utils/FixedPointMathLib.sol";
import "../libraries/traits/AddressCheckerTrait.sol";
import "../libraries/Errors.sol";
import "../libraries/math/MathUtils.sol";

/// @title LendingToken
/// @notice ERC20 token representing the Lending pool positions
/// - Extends ERC20 by adding scaledBalanceOf() and scaledTotalSupply()
/// - Overrides balanceOf() and totalSupply() to return scaled values
/// - Disables transfers other than mint and burn
///
/// @dev The underlying tokens minted and burned are scaled by the normalized income index.
/// In this way, as the income index increases, the amount of the tokens increases and user
/// balances increase. This approach closely follows the approach used by the Aave Protocol.
abstract contract LendingToken is ERC20, AddressCheckerTrait {
    using FixedPointMathLib for uint256;

    ILendingPool internal immutable _pool;
    uint8 private immutable _decimals;

    string private _name;
    string private _symbol;

    // TODO: In the future the name and symbol should reflect the underlying asset name and symbol
    constructor(address pool_, uint8 decimals_, string memory name_, string memory symbol_) nonZeroAddress(pool_) {
        _pool = ILendingPool(pool_);
        _decimals = decimals_;
        _name = name_;
        _symbol = symbol_;
    }

    modifier onlyLendingPool() {
        if (msg.sender != address(_pool)) revert Errors.OnlyLendingPool();
        _;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice The total supply unscaled
    function scaledTotalSupply() public view returns (uint256) {
        return super.totalSupply();
    }

    /// @notice The balance of an account unscaled
    function scaledBalanceOf(address account) public view returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice Mint the token to an account, the amount of tokens to mint is scaled down
    /// based on the normalized debt index.
    /// @param account The account to mint the tokens to
    /// @param amount The scaled amount of tokens to mint
    /// @param index The normalized debt index
    function mint(address account, uint256 amount, UD60x18 index, MathUtils.ROUNDING mode) external onlyLendingPool {
        uint256 amountScaled = _scaleAmount(amount, index, mode);
        _mint(account, amountScaled);
    }

    /// @notice Burn the token from an account, the amount of tokens to burn is scaled down
    /// based on the normalized debt index.
    /// @param account The account to burn the tokens from
    /// @param amount The scaled amount of tokens to burn)
    /// @param index The normalized debt index
    /// @param max Whether or not to burn the maximum amount
    function burn(
        address account,
        uint256 amount,
        UD60x18 index,
        bool max,
        MathUtils.ROUNDING mode
    )
        external
        onlyLendingPool
    {
        uint256 burnAmount;
        if (max) {
            burnAmount = scaledBalanceOf(account);
        } else {
            burnAmount = _scaleAmount(amount, index, mode);
        }
        _burn(account, burnAmount);
    }

    function _scaleAmount(uint256 amount, UD60x18 index, MathUtils.ROUNDING mode) internal pure returns (uint256) {
        uint256 _index = index.unwrap();
        return mode == MathUtils.ROUNDING.UP ? amount.divWadUp(_index) : amount.divWad(_index);
    }

    /// @notice Disables transfers other than mint and burn
    /// @dev Done explicitly because solady transfers do not prevent transferring to zero address.
    function transfer(address, uint256) public pure override returns (bool) {
        revert Errors.TransferDisabled();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert Errors.TransferDisabled();
    }
}
