// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import { ERC2771Context } from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IAccountManager } from "../interfaces/IAccountManager.sol";
import { UD60x18, ud, UNIT, ZERO } from "@prb/math/src/UD60x18.sol";
import { AccountLib } from "../libraries/accounts/AccountLib.sol";
import "../libraries/traits/AddressCheckerTrait.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/ILendingPool.sol";
import "../libraries/Errors.sol";
import "../periphery/Multicall.sol";
import "../external/pluz/IERC20Rebasing.sol";

abstract contract BaseAccountEvents {
    /////////////////////////////
    // Events
    /////////////////////////////
    /// @notice Event emitted when an `amount` is claimed from the account
    event Claim(uint256 amount);
    /// @notice Event emitted when the liquidation fee is taken, records the fee `amount` taken and the `recipient`
    event LiquidationFeeTaken(address recipient, uint256 amount);
}

/// @title Base Account
/// @notice The Base Account contract is the parent contract for all investment accounts
/// @dev ERC2771Context is initialized with a null address because we override the isTrustedForwarder method to use the
/// Account Manager as the trustedForwarder.
abstract contract BaseAccount is
    BaseAccountEvents,
    Multicall,
    IAccount,
    AddressCheckerTrait,
    Initializable,
    Pausable,
    ERC2771Context(address(0))
{
    using SafeERC20 for IERC20;

    /////////////////////////////
    // Omega Protocol Contracts
    /////////////////////////////
    /// @dev Accounts use the other contracts in the protocol for various functions
    ///
    /// AccountManager - Referrences this contract for access control purposes
    /// LendingPool - Accesses this contract to borrow and repay as well as to
    ///               Read the debt and collateral amounts.
    /// offchain liquidations.

    /// @notice The Investment Account Manager
    IAccountManager internal _manager;

    /// @notice The asset used by this investment account
    IERC20 public asset;

    /// @notice The actual asset
    IERC20 public actualAsset;

    /////////////////////////////
    // State Variables
    /////////////////////////////

    /// @notice The owner of this account
    address public owner;

    /**
     * @dev Only allows the contract's own address to call the function.
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert Errors.UnauthorizedRole(msg.sender, "SELF");
        }
        _;
    }

    /// @notice Empty constructor because this contract is deployed as a clone in the manager
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize this investment account
    /// @param owner_ The borrower that owns this account
    function initialize(address owner_) external virtual initializer {
        _initialize(owner_);
    }

    /// @notice Initialize this investment account
    /// @param owner_ The borrower that owns this account
    function _initialize(address owner_) internal {
        _manager = IAccountManager(msg.sender);
        asset = _manager.getLendAsset();
        actualAsset = IERC20(IERC20Rebasing(address(asset)).getActualAsset());
        owner = owner_;

        // Approve repayments to the lending pool
        asset.safeIncreaseAllowance(_manager.lendingPool(), type(uint256).max);
        // Approve repayments to the lending pool
        actualAsset.safeIncreaseAllowance(_manager.lendingPool(), type(uint256).max);
        // Approve manager to transfer assets
        asset.safeIncreaseAllowance(address(_manager), type(uint256).max);
        // Approve rebasing token to transfer assets
        actualAsset.safeIncreaseAllowance(address(asset), type(uint256).max);
    }

    ////////////////////////////
    // Access Control Modifiers
    ////////////////////////////

    /// @notice Restricts access to the `manager` of the account
    modifier onlyAccountManager() {
        if (msg.sender != address(_manager)) revert Errors.Unauthorized();
        _;
    }

    /// @notice Restricts access to the `owner` of the account
    /// @dev We use _msgSender() to allow for meta transactions
    modifier onlyOwner() {
        if (_msgSender() != owner) revert Errors.Unauthorized();
        _;
    }

    modifier onlyRepayer() {
        if (!(_msgSender() == owner || _manager.isLiquidationReceiver(msg.sender) || msg.sender == address(_manager))) {
            revert Errors.Unauthorized();
        }
        _;
    }

    ///////////////////////
    // ERC2771 Context Methods
    ///////////////////////
    function isTrustedForwarder(address forwarder) public view virtual override(ERC2771Context) returns (bool) {
        return forwarder == address(_manager);
    }

    function _msgSender() internal view virtual override(Context, ERC2771Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    // slither-disable-next-line dead-code
    function _msgData() internal view virtual override(Context, ERC2771Context) returns (bytes calldata) {
        // slither-disable-next-line dead-code
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength() internal view virtual override(Context, ERC2771Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }

    ///////////////////////
    // Admin Methods
    ///////////////////////
    /// @notice The owner of the accountManager is allowed to:
    /// - Pause/unpause the contract

    /// @notice Lets the admin pause the account
    function pause() external onlyAccountManager {
        _pause();
    }

    /// @notice Lets the admin unpause the account
    function unpause() external onlyAccountManager {
        _unpause();
    }

    function multicall(bytes[] calldata data)
        public
        payable
        override
        onlyOwner
        whenNotPaused
        returns (bytes[] memory results)
    {
        results = super.multicall(data);
    }

    //////////////////////////
    // Lending Pool Methods
    //////////////////////////
    /// @notice Interactions to borrow and repay from the `lendingPool`

    /// @notice Borrow from the lending pool
    /// @dev Manager is in charge of making sure this account is still solvent after borrowing.
    /// @dev Loans are assessed by looking at the account's debt and collateral.
    /// @param amount The amount to borrow
    function borrow(uint256 amount) external payable virtual onlyOwner whenNotPaused {
        // Borrow funds
        uint256 amountBorrowed = _manager.borrow(amount);
        emit Borrow(amountBorrowed);
    }

    /// @notice Repay the lending pool
    /// @param amount The amount to repay
    function repay(uint256 amount) external payable virtual onlyRepayer {
        uint256 amountRepaid = _manager.repay(address(this), amount);
        emit Repay(amountRepaid);
    }

    /// @notice Repay the lending pool
    /// @param amountFrom Additional amount to pull from owner before repayment
    function repayFrom(uint256 amountFrom) external payable virtual onlyOwner {
        actualAsset.safeTransferFrom(_msgSender(), address(this), amountFrom);
        uint256 amountRepaid = _manager.repay(address(this), actualAsset.balanceOf(address(this)));
        emit Repay(amountRepaid);
    }

    ////////////////////
    // Views
    ////////////////////

    /// @notice Returns the AccountManager that created this Account.
    function getManager() external view returns (IAccountManager) {
        return _manager;
    }

    function claim(uint256 amount) external payable onlyOwner whenNotPaused {
        _manager.claim(amount, _msgSender());
        emit Claim(amount);
    }

    function claim(uint256 amount, address recipient) external payable onlyOwner whenNotPaused {
        _manager.claim(amount, recipient);
        emit Claim(amount);
    }
}
