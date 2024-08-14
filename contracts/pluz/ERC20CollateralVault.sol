// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "../libraries/Errors.sol";
import "../libraries/traits/AddressCheckerTrait.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../solady/src/tokens/ERC20.sol";
import "../solady/src/utils/FixedPointMathLib.sol";
import "../external/pluz/IERC20Rebasing.sol";

/// @notice A vault that holds a single asset as collateral.
/// @dev It discards stealth donations and tracks its underlying collateral balance manually.
/// It is non-transferrable because of how it is used to track the collateral backing loans taken by user owned smart
/// contract accounts.
abstract contract ERC20CollateralVault is ERC20, AddressCheckerTrait {
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    IERC20 internal immutable _actualAsset;
    
    IERC20 internal immutable _collateral;

    uint256 internal _totalCollateralAssets;

    uint8 internal immutable _collateralAssetDecimals;

    string private _name;
    string private _symbol;

    constructor(
        address collateral_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    )
        nonZeroAddressAndContract(collateral_)
    {
        _collateral = IERC20(collateral_);
        _actualAsset = IERC20(IERC20Rebasing(collateral_).getActualAsset());
        _collateralAssetDecimals = decimals_;
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _collateralAssetDecimals;
    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 updatedAssets, uint256 shares) {
        (updatedAssets, shares) = _deposit(msg.sender, receiver, assets);
    }

    function withdraw(
        uint256 shares,
        address receiver
    )
        public
        virtual
        returns (uint256 updatedAssets, uint256 updatedShares)
    {
        (updatedAssets, updatedShares) = _withdraw(msg.sender, receiver, shares);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256 updatedAssets, uint256 shares) {
        shares = _convertToShares(assets);
        updatedAssets = assets;
    }

    function previewWithdraw(uint256 shares) public view virtual returns (uint256 assets, uint256 updatedShares) {
        assets = _convertToAssets(shares);
        updatedShares = shares;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets
    )
        internal
        virtual
        returns (uint256 updatedAssets, uint256 shares)
    {
        (updatedAssets, shares) = previewDeposit(assets);
        _totalCollateralAssets += updatedAssets;
        _actualAsset.safeTransferFrom(caller, address(this), updatedAssets);
        IERC20Rebasing(address(_collateral)).wrap(updatedAssets);
        _mint(receiver, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        uint256 shares
    )
        internal
        virtual
        returns (uint256 updatedAssets, uint256 updatedShares)
    {
        (updatedAssets, updatedShares) = previewWithdraw(shares);
        _totalCollateralAssets -= updatedAssets;
        _burn(caller, updatedShares);
        IERC20Rebasing(address(_collateral)).unwrap(updatedAssets);
        _actualAsset.safeTransfer(receiver, updatedAssets);
    }

    function _withdrawAssets(address caller, address receiver, uint256 assets) internal virtual {
        // Round up the amount of shares to burn given some assets.
        uint256 shares = assets.mulDivUp(totalSupply(), totalAssets());
        _totalCollateralAssets -= assets;
        _burn(caller, shares);
        IERC20Rebasing(address(_collateral)).unwrap(assets);
        _actualAsset.safeTransfer(receiver, assets);
    }

    /// @dev Returns the shares minted for given assets, rounding down.
    function _convertToShares(uint256 assets) internal view returns (uint256) {
        return totalSupply() == 0 ? assets : assets * totalSupply() / totalAssets();
    }

    /// @dev Returns the assets transferred for given shares, rounding down.
    function _convertToAssets(uint256 shares) internal view returns (uint256) {
        return totalSupply() == 0 ? shares : shares * totalAssets() / totalSupply();
    }

    function balanceOfAssets(address account) public view returns (uint256 assets) {
        return _convertToAssets(balanceOf(account));
    }

    function totalAssets() public view virtual returns (uint256) {
        return _totalCollateralAssets;
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
