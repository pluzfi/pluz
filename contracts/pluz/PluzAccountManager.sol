// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "../managers/StrategyAccountManager.sol";
import "../interfaces/IAssetPriceProvider.sol";
import "../libraries/accounts/AccountLib.sol";
import "../libraries/Errors.sol";
import "./PluzModule.sol";
import "./PluzAccount.sol";
import "./ERC20CollateralVault.sol";
import "./periphery/PluzGas.sol";
import "./periphery/PluzPoints.sol";
import "../periphery/PythPusher.sol";
import "../external/pluz/IERC20Rebasing.sol";

abstract contract PluzAccountManagerEvents {
    /// @notice A user has created an account.
    event AccountCreated(address indexed owner, address account);
    /// @notice A user has deposited WETH into the contract.
    event CollateralDeposit(address indexed owner, address account, uint256 amount);
    /// @notice A user has withdrawn WETH from the contract.
    event CollateralWithdrawal(address indexed owner, address account, uint256 amount);
    /// @notice When yield is accrued
    event YieldAccrued(uint256 amount);
    /// @notice CollateralLiquidation
    event CollateralLiquidation(
        address account, uint256 collateralAmount, uint256 bonusCollateral, uint256 debtAmountNeeded
    );
}

/// @title PluzAccountManager supports one account implementation
/// @notice The AccountManager contract deploys Account contracts.
contract PluzAccountManager is
    StrategyAccountManager,
    PythPusher,
    PluzModule,
    PluzAccountManagerEvents,
    ERC20CollateralVault,
    Initializable,
    PluzGas,
    PluzPoints
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using Address for address;

    UD60x18 public constant LIQUIDATION_BONUS = UD60x18.wrap(1.05e18); // 105% or 5%

    uint256 public MINIMUM_COMPOUND_AMOUNT = 1e6;

    /// @notice The max loan to value for Accounts
    /// @dev If 200%, loan can be maximum 200% of their collateral value
    UD60x18 public maxLtv;

    /// @notice The liquidation threshold for accounts
    /// @dev (Investment value + Equity value) / Debt value > collateralRatio
    UD60x18 public collateralRatio;

    /// @notice The implementation address of the Internal/External
    /// Account contracts to use for cloning
    address public immutable pluzAccountImplementation;

    mapping(address => address) private _ownerAccountCache;

    bool public isAutoCompounding;

    struct InitParams {
        address pluzAccount;
        bool isAutoCompounding;
        address liquidationReceiver;
        address collateral;
        UD60x18 maxLtv;
        UD60x18 collateralRatio;
        string name;
        string symbol;
        uint8 decimals;
    }

    /// @notice Constructs the factory
    constructor(
        address protocolGovernor_,
        InitParams memory params
    )
        PluzModule(protocolGovernor_)
        PluzPoints(protocolGovernor_)
        PluzGas(protocolGovernor_)
        StrategyAccountManager(protocolGovernor_, params.liquidationReceiver)
        ERC20CollateralVault(params.collateral, params.name, params.symbol, params.decimals)
        nonZeroAddressAndContract(params.pluzAccount)
    {
        pluzAccountImplementation = params.pluzAccount;
        maxLtv = params.maxLtv;
        collateralRatio = params.collateralRatio;
        _initializePyth(protocolGovernor_);
        IERC20Rebasing(address(params.collateral)).configure(YieldMode.CLAIMABLE);
        isAutoCompounding = params.isAutoCompounding;

        // Approve rebasing token to transfer actual assets
        _actualAsset.safeIncreaseAllowance(address(_collateral), type(uint256).max);
    }

    function initialize() external virtual initializer {
        IERC20Rebasing(address(_collateral)).setAuthorizedAccount();
    }

    function toggleAutoCompounding() public onlyOwner {
        isAutoCompounding = !isAutoCompounding;
    }

    /// @dev Updates maxLtv and collateralRatio.
    /// collateralRatio must always be less than maxLtv.
    function updateLiquidationParameters(UD60x18 maxLtv_, UD60x18 collateralRatio_) external onlyOwner {
        if (collateralRatio_ > maxLtv_) {
            revert Errors.InvalidParams();
        }
        maxLtv = maxLtv_;
        collateralRatio = collateralRatio_;
    }

    /// @dev This call requires that this contract is the account manager on the lending pool
    function createAccount() public nonReentrant returns (address payable account) {
        account = _createAccount(msg.sender);
    }

    function _createAccount(address caller) internal returns (address payable account) {
        address owner = caller;

        if (_ownerAccountCache[owner] != address(0)) {
            revert Errors.InvalidParams();
        }

        account = payable(Clones.cloneDeterministic(pluzAccountImplementation, _salt(owner)));

        // Record the account was created
        isCreatedAccount[account] = true;
        _ownerAccountCache[owner] = account;
        _accountOwnerCache[account] = owner;
        accountCount += 1;

        emit AccountCreated(owner, account);

        // Initialize the account
        PluzAccount(account).initialize(owner);
    }

    function createNewAccountDepositCollateralAndBorrow(
        uint256 depositAmount,
        uint256 borrowAmount,
        bytes[] memory pythPriceUpdates
    )
        external
        nonReentrant
        returns (address payable account)
    {
        updatePythPriceFeeds(pythPriceUpdates);
        account = _createAccount(msg.sender);
        _deposit(depositAmount, msg.sender);
        _borrow(account, borrowAmount);
    }

    /// @dev Takes assets from `msg.sender`, deposits them into the contract, and mints shares to the receiver.
    /// The shares are nontransferrable and reside in the receiver's address, but are used to credit the receiver's
    /// account contract.
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override
        nonReentrant
        returns (uint256 updatedAssets, uint256 shares)
    {
        (updatedAssets, shares) = _deposit(assets, receiver);
    }

    function _deposit(uint256 assets, address receiver) internal returns (uint256 updatedAssets, uint256 shares) {
        if (isAutoCompounding) {
            compound();
        }
        (updatedAssets, shares) = super.deposit(assets, receiver);
        emit CollateralDeposit(receiver, getAccount(receiver), assets);
    }

    /// @dev Burns shares from the account of `msg.sender` and sends them to the receiver.
    /// `msg.sender` must be owner of account that owns the shares.
    function withdraw(
        uint256 shares,
        address receiver
    )
        public
        override
        nonReentrant
        returns (uint256 updatedAssets, uint256 updatedShares)
    {
        (updatedAssets, updatedShares) = _withdraw(msg.sender, receiver, shares, new bytes[](0));
    }

    function _withdraw(
        address caller,
        address receiver,
        uint256 shares,
        bytes[] memory pythPricesUpdates
    )
        internal
        returns (uint256 updatedAssets, uint256 updatedShares)
    {
        if (isAutoCompounding) {
            compound();
        }
        (updatedAssets, updatedShares) = super._withdraw(caller, receiver, shares);
        address account = getAccount(caller);
        updatePythPriceFeeds(pythPricesUpdates);
        _requireSolvent(account);
        emit CollateralWithdrawal(caller, receiver, updatedAssets);
    }

    function compound() public returns (uint256 earned) {
        IERC20Rebasing collateral = IERC20Rebasing(address(_collateral));
        earned = collateral.getClaimableAmount(address(this));

        // Avoid compounding dust.
        // We assume the claim just works.
        if (earned >= MINIMUM_COMPOUND_AMOUNT) {
            _totalCollateralAssets += earned;
            earned = IERC20Rebasing(address(_collateral)).claim(address(this), earned);
            emit YieldAccrued(earned);
        }
    }

    function withdraw(
        uint256 shares,
        address receiver,
        bytes[] memory pythPriceUpdates
    )
        external
        payable
        nonReentrant
        returns (uint256 updatedAssets, uint256 updatedShares)
    {
        (updatedAssets, updatedShares) = _withdraw(msg.sender, receiver, shares, pythPriceUpdates);
    }

    ///////////////////////////
    // COLLATERAL LIQUIDATIONS
    ///////////////////////////

    /// @dev This calculation assumes that debt asset and collateral asset have the same decimals and have 18 decimal
    /// precision.
    function liquidateCollateral(address account, uint256 debtToCover, address liquidationFeeTo) public {
        AccountLib.Health memory health = getAccountHealth(account);

        if (!health.isLiquidatable) revert Errors.AccountHealthy();

        // Mark account as liquidatable if it isn't already.
        if (_accountLiquidationStartTime[account] == 0) {
            _accountLiquidationStartTime[account] = block.timestamp;
            emit AccountLiquidationStarted(account);
            this._afterLiquidationStarted(account);
        }

        // The collateral is credited to the owner of the Account, not the Account itself.
        address accountOwner = _accountOwnerCache[account];
        uint256 debtAmount = getDebtAmount(account);

        AccountLib.CollateralLiquidation memory _result =
            _simulateCollateralLiquidation(accountOwner, debtAmount, debtToCover);

        // Transfer collateral to caller and their fee wallet
        _withdrawAssets(accountOwner, msg.sender, _result.collateralAmount - _result.bonusCollateral);
        _withdrawAssets(accountOwner, liquidationFeeTo, _result.bonusCollateral);

        // Transfer debt from sender to account.
        uint256 convertAmount = _convertAmount(_result.actualDebtToLiquidate, IERC20Rebasing(address(_lendAsset)));
        _lendPoolActualAsset.safeTransferFrom(msg.sender, account, convertAmount);
        IAccount(account).repay(_result.actualDebtToLiquidate);

        emit CollateralLiquidation(
            account, _result.collateralAmount, _result.bonusCollateral, _result.actualDebtToLiquidate
        );
    }

    function simulateCollateralLiquidation(
        address account,
        uint256 debtToCover
    )
        external
        view
        returns (AccountLib.CollateralLiquidation memory)
    {
        // The collateral is credited to the owner of the Account, not the Account itself.
        address accountOwner = _accountOwnerCache[account];
        uint256 debtAmount = getDebtAmount(account);

        return _simulateCollateralLiquidation(accountOwner, debtAmount, debtToCover);
    }

    function _simulateCollateralLiquidation(
        address accountOwner,
        uint256 debtAmount,
        uint256 debtToCover
    )
        public
        view
        returns (AccountLib.CollateralLiquidation memory)
    {
        uint256 actualDebtToLiquidate = debtToCover > debtAmount ? debtAmount : debtToCover;
        uint256 collateralBalance = balanceOfAssets(accountOwner);
        (uint256 collateralAmount, uint256 bonusCollateral, uint256 debtAmountNeeded) =
            _calculateAvailableCollateralToLiquidate(actualDebtToLiquidate, collateralBalance);

        if (debtAmountNeeded < actualDebtToLiquidate) {
            actualDebtToLiquidate = debtAmountNeeded;
        }

        return AccountLib.CollateralLiquidation({
            actualDebtToLiquidate: actualDebtToLiquidate,
            collateralAmount: collateralAmount,
            bonusCollateral: bonusCollateral
        });
    }

    function _calculateAvailableCollateralToLiquidate(
        uint256 debtToCover,
        uint256 collateralBalance
    )
        internal
        view
        returns (uint256 collateralAmount, uint256 bonusCollateral, uint256 debtAmountNeeded)
    {
        UD60x18 collateralPrice = ud(_getPriceProvider().getAssetPrice(address(_collateral)));

        uint256 maxCollateralAssetsToLiquidate = ud(debtToCover).mul(LIQUIDATION_BONUS).div(collateralPrice).unwrap();
        if (maxCollateralAssetsToLiquidate > collateralBalance) {
            collateralAmount = collateralBalance;
            debtAmountNeeded = collateralPrice.mul(ud(collateralAmount)).div(LIQUIDATION_BONUS).unwrap();
        } else {
            collateralAmount = maxCollateralAssetsToLiquidate;
            debtAmountNeeded = debtToCover;
        }

        UD60x18 debtAmountInCollateral = ud(debtAmountNeeded).div(collateralPrice);
        bonusCollateral = ud(collateralAmount).sub(debtAmountInCollateral).unwrap();
    }

    function _getAccountMaxLtv(address) internal view override returns (UD60x18) {
        return maxLtv;
    }

    function totalAssets() public view virtual override returns (uint256) {
        return _totalCollateralAssets + IERC20Rebasing(address(_collateral)).getClaimableAmount(address(this));
    }

    /////////////////////////
    // Account Views
    /////////////////////////

    /// @notice Returns the Account contract address for a given owner, even if it hasn't been created yet.
    /// Returns address(0) if the account is not valid
    /// @param owner_  The owner of the Account contract
    function getAccount(address owner_) public view returns (address account) {
        account = _ownerAccountCache[owner_];
        if (account == address(0)) {
            account = Clones.predictDeterministicAddress(pluzAccountImplementation, _salt(owner_));
        }
    }

    function getOwner(address account) external view returns (address owner) {
        owner = _accountOwnerCache[account];
        require(owner != address(0), "Owner is zero address");
    }

    function getAccountHealth(address account) public view override returns (AccountLib.Health memory health) {
        uint256 investmentValue = getTotalAccountValue(account);
        uint256 collateralValue = getTotalCollateralValue(account);
        uint256 debtAmount = getDebtAmount(account);
        uint256 equity = collateralValue + investmentValue;

        health = AccountLib.Health({
            isLiquidatable: false,
            hasBadDebt: false,
            debtAmount: debtAmount,
            collateralValue: collateralValue,
            investmentValue: investmentValue
        });

        if (debtAmount > 0 && equity > 0) {
            health.isLiquidatable = equity < (ud(debtAmount).mul(collateralRatio)).unwrap();
        } else if (debtAmount > 0) {
            health.hasBadDebt = true;
        }
    }

    /// @dev The nontransferrable collateral vault shares are assigned to the owner of the account so we base
    /// @dev the value
    function getTotalCollateralValue(address account) public view override returns (uint256 totalValue) {
        address owner = _accountOwnerCache[account];
        uint256 assets = balanceOfAssets(owner);
        uint256 price = _getPriceProvider().getAssetPrice(address(_collateral));
        totalValue = (assets * price) / (10 ** _collateralAssetDecimals);
    }
}
