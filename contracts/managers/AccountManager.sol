// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import "../solady/src/utils/FixedPointMathLib.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ProtocolModule, ProtocolGovernor } from "../system/ProtocolModule.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ERC2771Forwarder } from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import { ILendingPool } from "../interfaces/ILendingPool.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UD60x18, ud, UNIT, ZERO } from "@prb/math/src/UD60x18.sol";
import { BaseAccount } from "../accounts/BaseAccount.sol";
import { IAccount } from "../interfaces/IAccount.sol";
import { IAssetPriceOracle } from "../interfaces/IAssetPriceOracle.sol";
import { InternalAccount } from "../accounts/InternalAccount.sol";
import { ExternalAccount } from "../accounts/ExternalAccount.sol";
import "../interfaces/IStrategyVault.sol";
import "../interfaces/IAccountManager.sol";
import "../interfaces/IInternalAccount.sol";
import "../interfaces/IAssetPriceProvider.sol";
import "../interfaces/ILiquidationReceiver.sol";
import "../libraries/accounts/AccountLib.sol";
import "../libraries/Errors.sol";

/// @title Account Factory Events
/// @dev Place all events used by the AccountManager contract here
abstract contract AccountManagerEvents {
    /// @notice Additional fees charged to an account (in addition to their lending pool debt).
    event FeesCharged(address indexed account, uint256 amount);
    /// @notice Account liquidation started
    event AccountLiquidationStarted(address indexed account);
    /// @notice Account liquidation completed
    event AccountLiquidationCompleted(address indexed account);
    /// @notice A user has borrowed.
    event AccountBorrowed(address indexed owner, address indexed account, uint256 amount);
    /// @notice A user has repaid.
    event AccountRepaid(address indexed owner, address indexed account, uint256 amount);
    event LiquidationFeesTaken(
        address indexed feeCollector, address indexed liquidator, uint256 protocolShare, uint256 liquidatorShare
    );
    /// @dev LiquidationReceiver is created per (account, liquidationFeeTo).
    event LiquidationReceiverCreated(
        address indexed account, address indexed liquidationFeeTo, address liquidationReceiver
    );
    /// @notice User claimed assets from their account.
    event AccountClaimed(address indexed owner, address indexed account, uint256 amount);
}

/// @title AccountManager
/// @notice The AccountManager contract deploys Account contracts.
/// Investment Accounts are only createable by the owner of this contract or
/// accounts approved by the admin (known as account creators).
abstract contract AccountManager is IAccountManager, Pausable, AccountManagerEvents, ProtocolModule, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using Address for address;
    using FixedPointMathLib for uint256;

    error OldAccountDoesNotExist();
    error RemainingDebtLeft();

    /// @notice The LendingPool contract address for Investment Accounts to use
    ILendingPool internal immutable _lendingPool;

    IERC20 internal immutable _lendAsset;

    /// @notice An mapping of all Account contracts that have been created
    mapping(address => bool) public isCreatedAccount;

    /// @notice Account to their owner.
    mapping(address => address) internal _accountOwnerCache;

    mapping(address => uint256) internal _accountLiquidationStartTime;
    mapping(address => mapping(address => ILiquidationReceiver)) public liquidationReceiver;
    mapping(address => bool) internal _isLiquidationReceiver;

    /// @notice Counter to keep track of the number of Account contracts that have been created
    uint256 public accountCount;

    bool public allowedAccountsMode;

    mapping(address => bool) public isAccountAllowed;

    // Account configurations
    ///////////////////////////
    address immutable liquidationReceiverImpl;

    IAccountManager immutable oldAccountManager;

    modifier onlyAccount() {
        if (!isCreatedAccount[msg.sender]) {
            revert Errors.Unauthorized();
        }
        if (allowedAccountsMode && !isAccountAllowed[msg.sender]) {
            revert Errors.Unauthorized();
        }
        _;
    }

    modifier onlyAccountOwner(address account) {
        if (!isCreatedAccount[account]) {
            revert Errors.AccountNotCreated();
        }

        if (msg.sender != _accountOwnerCache[account]) {
            revert Errors.Unauthorized();
        }
        _;
    }

    /// @notice Constructs the factory
    constructor(
        address protocolGovernor_,
        address liquidationReceiverImpl_,
        IAccountManager oldAccountManager_
    )
        ProtocolModule(protocolGovernor_)
        nonZeroAddressAndContract(address(_getPriceProvider()))
        nonZeroAddressAndContract(_getLendingPool())
    {
        liquidationReceiverImpl = liquidationReceiverImpl_;
        _lendingPool = ILendingPool(_getLendingPool());
        _lendAsset = IERC20(_getLendAsset());
        oldAccountManager = oldAccountManager_;
        allowedAccountsMode = true;
    }

    //////////////////////////
    // Account Administration
    //////////////////////////

    function setAllowedAccountsMode(bool status) external onlyOwner {
        allowedAccountsMode = status;
    }

    function setAllowedAccountStatus(address account, bool status) external onlyOwner {
        isAccountAllowed[account] = status;
    }

    function isLiquidationReceiver(address receiver) external view returns (bool) {
        return _isLiquidationReceiver[receiver];
    }

    /// @notice Let the owner pause deposits and borrows
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Let the owner unpause deposits and borrows
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Lets the admin pause the account
    /// @dev We cannot pause an account that isn't solvent because a pause will disable it from being liquidated.
    function pauseAccount(address account) external onlyOwner {
        _requireSolvent(account);
        IAccount(account).pause();
    }

    /// @notice Lets the admin unpause the account
    function unpauseAccount(address account) external onlyOwner {
        IAccount(account).unpause();
    }

    /////////////////////////////
    // Account Functionality
    /////////////////////////////

    function borrow(uint256 amount) external virtual onlyAccount nonReentrant returns (uint256 borrowed) {
        borrowed = _borrow(msg.sender, amount);
    }

    function _borrow(address caller, uint256 amount) internal whenNotPaused returns (uint256 borrowed) {
        borrowed = _lendingPool.borrow(amount, caller);

        _requireSolvent(caller);

        emit AccountBorrowed(_accountOwnerCache[caller], caller, borrowed);

        this._afterBorrow(caller, borrowed);
    }

    function repay(address account, uint256 amount) external virtual nonReentrant returns (uint256 repaid) {
        // Debt repaid is onBehalfOf, funds are transferred from `from`.
        repaid = _lendingPool.repay(amount, account, msg.sender);

        emit AccountRepaid(_accountOwnerCache[account], account, repaid);

        this._afterRepay(account, repaid);
    }

    /// @dev Anyone can use an accounts existing funds + their own funds for interest and make the debt of old account
    /// go to zero
    function repayToCloseAccount(address account) external virtual nonReentrant returns (uint256 repaid) {
        if (!oldAccountManager.isCreatedAccount(account)) {
            revert OldAccountDoesNotExist(); //unauthorised
        }

        uint256 accountBalance = _lendAsset.balanceOf(account);
        //repay as much as possible from the account itself
        uint256 repaidAmountFromAccount;

        if (accountBalance > 0) {
            repaidAmountFromAccount = _lendingPool.repay(accountBalance, account, account);
        }

        uint256 remaningDebt = getDebtAmount(account);

        //take the remaining debt from the msg.sender (the tank or the user themselves)
        if (remaningDebt > 0) {
            _lendingPool.repay(remaningDebt + 3, account, msg.sender);
        }

        //has to make debt go to zero to
        if (getDebtAmount(account) > 0) {
            revert RemainingDebtLeft();
        }

        emit AccountRepaid(address(0), account, repaidAmountFromAccount + remaningDebt);

        this._afterRepay(account, repaid);
    }

    /// @notice Called by Account when its Owner wants to withdraw excess funds.
    /// @param amount The amount to withdraw
    /// @param recipient The address to send the assets to
    function claim(uint256 amount, address recipient) external nonZeroAddress(recipient) onlyAccount nonReentrant {
        uint256 debtAmount = getDebtAmount(msg.sender);

        if (debtAmount > 0) {
            uint256 investmentValue = getTotalAccountValue(msg.sender);
            uint256 profit = investmentValue.zeroFloorSub(debtAmount);

            if (amount > profit) {
                revert Errors.NotClaimableProfit();
            }
            _lendAsset.safeTransferFrom(msg.sender, recipient, amount);
            _requireSolvent(msg.sender);
        } else {
            _lendAsset.safeTransferFrom(msg.sender, recipient, amount);
        }

        emit AccountClaimed(_accountOwnerCache[msg.sender], msg.sender, amount);
    }

    /// @notice Mark an account as liquidatable.
    function liquidate(
        address account,
        address liquidationFeeTo
    )
        external
        returns (ILiquidationReceiver liquidationReceiver_)
    {
        return _startLiquidation(account, liquidationFeeTo);
    }

    function emitLiquidationFeeEvent(
        address feeCollector_,
        address liquidationFeeTo,
        uint256 protocolShare,
        uint256 liquidatorShare
    )
        external
    {
        if (!_isLiquidationReceiver[msg.sender]) revert Errors.Unauthorized();
        emit LiquidationFeesTaken(feeCollector_, liquidationFeeTo, protocolShare, liquidatorShare);
    }

    /// @dev Starts the liquidation process on an Account if it is liquidatable.
    function _startLiquidation(
        address account,
        address liquidationFeeTo
    )
        internal
        returns (ILiquidationReceiver liquidationReceiver_)
    {
        AccountLib.Health memory health = getAccountHealth(account);

        if (!health.isLiquidatable) revert Errors.AccountHealthy();

        liquidationReceiver_ = liquidationReceiver[account][liquidationFeeTo];

        // Create the liquidator receiver.
        if (address(liquidationReceiver_) == address(0)) {
            liquidationReceiver_ = ILiquidationReceiver(
                Clones.cloneDeterministic(liquidationReceiverImpl, keccak256(abi.encode(account, liquidationFeeTo)))
            );
            liquidationReceiver_.initialize(
                ILiquidationReceiver.Props({
                    account: IAccount(account),
                    manager: IAccountManager(address(this)),
                    liquidationFeeTo: liquidationFeeTo,
                    asset: _lendAsset
                })
            );
            liquidationReceiver[account][liquidationFeeTo] = liquidationReceiver_;
            _isLiquidationReceiver[address(liquidationReceiver_)] = true;
            emit LiquidationReceiverCreated(account, liquidationFeeTo, address(liquidationReceiver_));
        }

        // Account has idle borrowed funds, transfer them to the liquidator receiver.
        if (_lendAsset.balanceOf(address(account)) > 0) {
            _lendAsset.safeTransferFrom(
                address(account), address(liquidationReceiver_), _lendAsset.balanceOf(address(account))
            );
        }

        // Mark account as liquidatable if it isn't already.
        if (_accountLiquidationStartTime[account] == 0) {
            _accountLiquidationStartTime[account] = block.timestamp;
            emit AccountLiquidationStarted(account);
            this._afterLiquidationStarted(account);
        }
    }

    function _completeLiquidation(address account) external onlySelf {
        delete _accountLiquidationStartTime[account];
        emit AccountLiquidationCompleted(account);
        this._afterLiquidationCompleted(account);
    }

    /////////////////////////
    // Account Views
    /////////////////////////

    function lendingPool() external view returns (address) {
        return address(_lendingPool);
    }

    function getLiquidationReceiver(
        address account,
        address liquidationFeeTo
    )
        external
        view
        returns (ILiquidationReceiver)
    {
        return ILiquidationReceiver(
            Clones.predictDeterministicAddress(
                liquidationReceiverImpl, keccak256(abi.encode(account, liquidationFeeTo))
            )
        );
    }

    function getFeeCollector() external view returns (address) {
        return _getFeeCollector();
    }

    function getLendAsset() external view returns (IERC20) {
        return _lendingPool.getAsset();
    }

    function getAccountLiquidationStatus(address account) external view returns (AccountLib.LiquidationStatus memory) {
        return AccountLib.LiquidationStatus({
            isLiquidating: _accountLiquidationStartTime[account] > 0,
            liquidationStartTime: _accountLiquidationStartTime[account]
        });
    }

    function getLiquidationFee() external view returns (AccountLib.LiquidationFee memory fee) {
        fee.protocolShare = _protocolLiquidationShare();
        fee.liquidatorShare = _liquidatorShare();
    }

    function getDebtAmount(address account) public view virtual returns (uint256) {
        return _lendingPool.getDebtAmount(account);
    }

    function getAccountLoan(address account) public view returns (AccountLib.Loan memory) {
        uint256 collateralValue = getTotalCollateralValue(account);
        uint256 debt = getDebtAmount(account);
        UD60x18 ltv = ZERO;
        if (collateralValue > 0) {
            ltv = ud(debt).div(ud(collateralValue));
        }
        return AccountLib.Loan({
            debtAmount: debt,
            collateralValue: collateralValue,
            ltv: ltv,
            maxLtv: _getAccountMaxLtv(account)
        });
    }

    function getAccountHealth(address) public view virtual returns (AccountLib.Health memory health);

    /// @dev Total value of investments sitting in the Account.
    function getTotalAccountValue(address account) public view virtual returns (uint256 totalValue);

    /// @dev Total value of collateral attributed to the Account.
    function getTotalCollateralValue(address account) public view virtual returns (uint256 totalValue) { }

    /// @notice Used to ensure the account has performed an operation that doesn't put their loan into an insolvent
    /// state.
    function _requireSolvent(address account) internal view {
        // Actions depending on solvency cannot be performed during liquidation state.
        if (_accountLiquidationStartTime[account] > 0) {
            revert Errors.AccountBeingLiquidated();
        }

        // Only perform solvency check if Account has debt.
        if (getDebtAmount(account) > 0) {
            AccountLib.Health memory health = getAccountHealth(account);

            uint256 borrowLimit = ud(health.collateralValue).mul(_getAccountMaxLtv(account)).unwrap();

            // Check if borrowed debt is fully collateralized based off max ltv.
            if (health.debtAmount > borrowLimit) {
                revert Errors.AccountInsolvent();
            }

            // If debt is considered fully collateralized, check if the account can be liquidatable.
            if (health.isLiquidatable) {
                revert Errors.AccountInsolvent();
            }
        }
    }

    ///////////////////
    // HOOKS
    ///////////////////

    function _afterRepay(address account, uint256) external virtual onlySelf {
        if (_accountLiquidationStartTime[account] > 0) {
            AccountLib.Health memory health = getAccountHealth(account);
            if (!health.isLiquidatable) {
                this._completeLiquidation(account);
            }
        }
    }

    function _afterBorrow(address account, uint256 borrowed) external virtual onlySelf { }

    function _afterLiquidationStarted(address account) external virtual onlySelf { }

    function _afterLiquidationCompleted(address account) external virtual onlySelf { }

    //////////////////
    // INTERNAL
    //////////////////

    function _getAccountMaxLtv(address account) internal view virtual returns (UD60x18);

    /// @notice Hashes an address with this contract's address
    /// @param addr The address to convert
    function _salt(address addr) internal view virtual returns (bytes32) {
        return keccak256(abi.encodePacked(addr, address(this)));
    }
}
